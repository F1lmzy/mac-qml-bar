#include <QtTest>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QQuickItem>
#include <QImage>
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QTemporaryDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QProcessEnvironment>
#include <maccer_agent.h>
#include "../src/services/launcher.h"

class LauncherServiceTest final : public QObject {
    Q_OBJECT
private slots:
    void malformedAbiRequestReturnsOwnedError() {
        MaccerAgent *agent = maccer_agent_create(true);
        QVERIFY(agent);
        char *error = maccer_agent_send(agent, "{");
        QVERIFY(error);
        QVERIFY(*error != '\0');
        maccer_agent_string_free(error);
        maccer_agent_destroy(agent);
    }

    void fixtureReadinessAndLatestSearchResults() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral("s"));
        service.setQuery(QStringLiteral("safari"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.query(), QStringLiteral("safari"));
        QVERIFY(!service.results().isEmpty());
        const QVariantMap result = service.results().first().toMap();
        QCOMPARE(result.value("provider").toString(), QStringLiteral("apps"));
        QCOMPARE(result.value("title").toString(), QStringLiteral("Safari"));
        QVERIFY(result.contains("actions"));
    }

    void activationUsesVisibleActionAndCancelClearsState() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral("Safari"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QVERIFY(!service.results().isEmpty());
        const QVariantMap item = service.results().first().toMap();
        const QString provider = item.value("provider").toString();
        const QString id = item.value("id").toString();
        const QString action = item.value("actions").toList().first().toMap().value("id").toString();
        QSignalSpy closed(&service, &LauncherService::closeRequested);
        service.activate(provider, id, action);
        QTRY_COMPARE_WITH_TIMEOUT(closed.count(), 1, 5000);

        service.setQuery(QStringLiteral("Terminal"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QVERIFY(!service.results().isEmpty());
        service.cancel();
        QVERIFY(service.results().isEmpty());
        QVERIFY(!service.searching());
        QVERIFY(!service.busy());
        QVERIFY(service.outputTitle().isEmpty());
        QVERIFY(service.outputText().isEmpty());
    }

    void iconsSurvivePartialResultReplacement() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral("Safari"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        const QByteArray request = QByteArray::number(service.m_request);
        const QByteArray results = "{\"type\":\"results\",\"request\":" + request +
            ",\"items\":[{\"provider\":\"apps\",\"id\":\"safari\",\"title\":\"Safari\",\"iconSource\":\"\"}],\"complete\":false}";
        service.applyEvent(results);
        service.applyEvent("{\"type\":\"icon\",\"request\":" + request +
            ",\"provider\":\"apps\",\"id\":\"safari\",\"source\":\"data:image/png;base64,fixture\"}");
        QCOMPARE(service.results().first().toMap().value("iconSource").toString(),
                 QStringLiteral("data:image/png;base64,fixture"));
        service.applyEvent(results);
        QCOMPARE(service.results().first().toMap().value("iconSource").toString(),
                 QStringLiteral("data:image/png;base64,fixture"));
        service.cancel();
        service.applyEvent(results);
        QVERIFY(service.results().isEmpty());
    }

    void nativePixelsDisplayAndStayWarmAcrossQueries() {
        QQmlEngine engine;
        LauncherService service(true, &engine);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral("Safari"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(service.results().first().toMap().value("iconSource").toString()
                                    .startsWith(QStringLiteral("image://maccer-icons/")), 5000);
        const QString source = service.results().first().toMap().value("iconSource").toString();
        auto *provider = static_cast<QQuickImageProvider *>(engine.imageProvider(QStringLiteral("maccer-icons")));
        QVERIFY2(provider, "The pill must display maccer pixels through an in-memory image provider.");
        QSize size;
        const QImage pixels = provider->requestImage(source.mid(QStringLiteral("image://maccer-icons/").size()), &size, {});
        QCOMPARE(size, QSize(2, 2));
        QVERIFY(!pixels.isNull());
        QCOMPARE(pixels.pixelColor(0, 0).red(), 220);
        QCOMPARE(pixels.pixelColor(0, 0).green(), 80);
        QCOMPARE(pixels.pixelColor(0, 0).alpha(), 255);
        QCOMPARE(provider->requestImage(source.mid(QStringLiteral("image://maccer-icons/").size()), &size, QSize(1, 1)).size(),
                 QSize(1, 1));
        QCOMPARE(size, QSize(2, 2)); // Natural dimensions, not the requested scaled size.

        QQmlComponent component(&engine);
        component.setData("import QtQuick\nImage { asynchronous: true }", QUrl());
        QScopedPointer<QObject> image(component.create());
        QVERIFY2(image, qPrintable(component.errorString()));
        image->setProperty("source", source);
        QTRY_COMPARE_WITH_TIMEOUT(image->property("status").toInt(), 1, 5000); // Image.Ready
        QCOMPARE(image->property("implicitWidth").toInt(), 2);

        service.cancel();
        service.setQuery(QStringLiteral("saf"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.results().first().toMap().value("iconSource").toString(), source);
        // The provider owns copied pixels; neither cancellation nor service shutdown
        // invalidates an image already supplied to Qt.
        QCOMPARE(provider->requestImage(source.mid(QStringLiteral("image://maccer-icons/").size()), nullptr, {}), pixels);
        QVERIFY(provider->requestImage(QStringLiteral("not-a-token"), nullptr, {}).isNull());
    }

    void imageProviderOutlivesTheService() {
        QQmlEngine engine;
        auto service = std::make_unique<LauncherService>(true, &engine);
        QTRY_VERIFY_WITH_TIMEOUT(service->ready(), 5000);
        service->setQuery(QStringLiteral("Safari"));
        QTRY_VERIFY_WITH_TIMEOUT(!service->searching(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(service->results().first().toMap().value("iconSource").toString()
                                    .startsWith(QStringLiteral("image://maccer-icons/")), 5000);
        const QString source = service->results().first().toMap().value("iconSource").toString();
        service.reset(); // Rust handle and owned buffers are gone.
        auto *provider = static_cast<QQuickImageProvider *>(engine.imageProvider(QStringLiteral("maccer-icons")));
        QVERIFY(provider);
        const QImage image = provider->requestImage(source.mid(QStringLiteral("image://maccer-icons/").size()), nullptr, {});
        QCOMPARE(image.size(), QSize(2, 2));
        QCOMPARE(image.pixelColor(0, 0).red(), 220);
    }

    void safeOutputAndRepeatedKeepOpenActions() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral("!fixture"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QVERIFY(!service.results().isEmpty());
        const QVariantMap item = service.results().first().toMap();
        const QString provider = item.value("provider").toString();
        const QString id = item.value("id").toString();
        service.activate(provider, id, QStringLiteral("output"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(), 5000);
        QCOMPARE(service.outputTitle(), QStringLiteral("Fixture output"));
        QCOMPARE(service.outputText(), QStringLiteral("<b>literal output</b>"));
        service.activate(provider, id, QStringLiteral("keep"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(), 5000);
        QCOMPARE(service.lastError(), QStringLiteral("Fixture action completed"));
        service.activate(provider, id, QStringLiteral("keep"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.busy(), 5000);
        QCOMPARE(service.lastError(), QStringLiteral("Fixture action completed"));
        service.cancel();
    }

    void providerPickerReturnsQueryWithoutNativeEffects() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral(";"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QVERIFY(!service.results().isEmpty());
        const QVariantMap item = service.results().first().toMap();
        QSignalSpy nextQuery(&service, &LauncherService::queryRequested);
        service.activate(item.value("provider").toString(), item.value("id").toString(), QStringLiteral("select"));
        QTRY_COMPARE_WITH_TIMEOUT(nextQuery.count(), 1, 5000);
        QVERIFY(!nextQuery.first().first().toString().isEmpty());
    }

    void queryBeforeReadyAndCancellationRemainUsable() {
        LauncherService service(true);
        service.setQuery(QStringLiteral("日本語"));
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.results().size(), 1);
        QCOMPARE(service.results().first().toMap().value("title").toString(), QStringLiteral("日本語"));
        service.cancel();
        service.setQuery(QStringLiteral("Terminal"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.results().size(), 1);
        QCOMPARE(service.results().first().toMap().value("title").toString(), QStringLiteral("Terminal"));
    }

    void rejectsNulInsteadOfTruncatingQuery() {
        LauncherService service(true);
        service.setQuery(QString::fromUtf8("safari\0ignored", 14));
        QCOMPARE(service.lastError(), QStringLiteral("Search text cannot contain a NUL character."));
        QVERIFY(!service.searching());
    }

    void fixtureModeIgnoresServiceSocketEnvironment() {
        qputenv("MACCER_SERVICE_SOCKET", QByteArray("/tmp/maccer-ignored/rpc"));
        LauncherService service(true);
        qunsetenv("MACCER_SERVICE_SOCKET");
        QVERIFY(!service.serviceMode());
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QStringLiteral("Safari"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QVERIFY(!service.results().isEmpty());
    }

    void serviceModeConnectFailureDoesNotFallBackToEmbedded() {
        const QByteArray socket = QDir::temp()
            .filePath(QStringLiteral("maccer-missing-%1/rpc")
                          .arg(QCoreApplication::applicationPid()))
            .toUtf8();
        qputenv("MACCER_SERVICE_SOCKET", socket);
        LauncherService service(false);
        qunsetenv("MACCER_SERVICE_SOCKET");
        QVERIFY(service.serviceMode());
        QTRY_VERIFY_WITH_TIMEOUT(!service.lastError().isEmpty(), 5000);
        QVERIFY(!service.ready());
        // No embedded fallback: a query stays empty instead of resolving locally.
        service.setQuery(QStringLiteral("Safari"));
        QTest::qWait(200);
        QVERIFY(service.results().isEmpty());
    }

    void presentEventIsServiceOnlyAndIndependentOfSearchRequest() {
        // Embedded/fixture backends never own presentation and must ignore the
        // event even if something injects it.
        {
            LauncherService service(true);
            QSignalSpy shows(&service, &LauncherService::showRequested);
            service.applyEvent("{\"type\":\"present\"}");
            service.applyEvent("{\"type\":\"presentationError\",\"message\":\"ignored\"}");
            QCOMPARE(shows.count(), 0);
            QVERIFY(service.shortcutError().isEmpty());
        }
        // In service mode the backend-owned presentation request is delivered
        // regardless of the search/request watermark and with no active view.
        const QByteArray socket = QDir::temp()
            .filePath(QStringLiteral("maccer-present-%1/rpc")
                          .arg(QCoreApplication::applicationPid()))
            .toUtf8();
        qputenv("MACCER_SERVICE_SOCKET", socket);
        LauncherService service(false);
        qunsetenv("MACCER_SERVICE_SOCKET");
        QVERIFY(service.serviceMode());
        service.cancel();
        service.m_request = 4242;
        service.m_resultRequest = 7;
        QSignalSpy shows(&service, &LauncherService::showRequested);
        service.applyEvent("{\"type\":\"present\"}");
        QCOMPARE(shows.count(), 1);
        service.applyEvent("{\"type\":\"present\"}");
        QCOMPARE(shows.count(), 2);
        // A control-channel failure surfaces without disturbing search state.
        QSignalSpy changes(&service, &LauncherService::stateChanged);
        service.applyEvent("{\"type\":\"presentationError\",\"message\":\"control channel failed\"}");
        QCOMPARE(service.shortcutError(), QStringLiteral("control channel failed"));
        QCOMPARE(changes.count(), 1);
    }

    void providerScopedTracksResultRoutesAndClearsOnHome() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        QVERIFY(!service.providerScoped());
        const QByteArray request = QByteArray::number(service.m_request);
        service.applyEvent("{\"type\":\"results\",\"request\":" + request +
            ",\"route\":{\"type\":\"provider\",\"providerId\":\"apps\"},\"items\":[],\"complete\":true}");
        QVERIFY(service.providerScoped());
        service.applyEvent("{\"type\":\"outcome\",\"request\":" + request +
            ",\"kind\":\"setQuery\",\"text\":\"\",\"route\":{\"type\":\"home\"}}");
        QVERIFY(!service.providerScoped());
        service.applyEvent("{\"type\":\"results\",\"request\":" + request +
            ",\"route\":{\"type\":\"provider\",\"providerId\":\"themes\"},\"items\":[],\"complete\":true}");
        QVERIFY(service.providerScoped());
        service.cancel();
        QVERIFY(!service.providerScoped());
    }

    void homeIsIgnoredOutsideServiceMode() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        const quint64 before = service.m_request;
        QSignalSpy queries(&service, &LauncherService::queryRequested);
        service.home();
        QCOMPARE(service.m_request, before);
        QCOMPARE(queries.count(), 0);
        QVERIFY(!service.providerScoped());
    }

    void serviceCatalogPreviewsNeverApplyOrChangeActiveColors() {
        QString binary = qEnvironmentVariable("MACCER_SERVICE_BIN");
        if (binary.isEmpty()) binary = qEnvironmentVariable("MACCER_SOURCE", QDir::homePath() + "/Documents/maccer") + "/target/debug/maccer-service";
        if (!QFileInfo::exists(binary)) QSKIP("set MACCER_SERVICE_BIN to test the real catalog provider");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const auto write = [](const QString &path, const QByteArray &bytes) {
            QFile file(path);
            return file.open(QIODevice::WriteOnly) && file.write(bytes) == bytes.size();
        };
        const auto colors = [](const QStringList &keys) {
            QJsonObject values;
            for (const QString &key : keys) values.insert(key, "#123456");
            return values;
        };
        QStringList ansi{"background", "foreground", "cursor", "accent", "selection_background", "selection_foreground"};
        for (int i = 0; i < 16; ++i) ansi.append(QStringLiteral("color%1").arg(i));
        QJsonObject active{{"schema", 1}, {"slug", "active-original"}, {"name", "Active Original"}, {"variant", "dark"}, {"alpha_byte", 230},
            {"palette", colors(ansi)}, {"tokens", colors({"surface", "surface_container_low", "surface_container", "surface_container_high", "surface_container_highest", "on_surface", "on_surface_variant", "outline", "outline_variant", "primary", "on_primary", "primary_container", "on_primary_container", "secondary", "info", "success", "warning", "error", "muted"})},
            {"border", colors({"active", "inactive"})}, {"bar", colors({"background", "background_solid", "item_bg", "accent", "label", "icon", "muted", "red", "green", "yellow"})}};
        QJsonObject preview = active;
        preview.insert("slug", "preview-only"); preview.insert("name", "Owned Preview");
        QJsonObject previewColors = preview.value("palette").toObject(); previewColors.insert("accent", "#abcdef"); preview.insert("palette", previewColors);
        QVERIFY(QDir().mkpath(dir.filePath("bin")));
        QVERIFY(QDir().mkpath(dir.filePath("state")));
        QVERIFY(write(dir.filePath("state/current.json"), QJsonDocument(active).toJson()));
        QVERIFY(write(dir.filePath("catalog.json"), QJsonDocument(QJsonObject{{"schema", 1}, {"themes", QJsonArray{preview}}}).toJson()));
        const QString helper = dir.filePath("bin/mac-themer");
        // Owned fake helper: catalog is read-only; apply records an owned marker
        // and reports success without touching the user's desktop or state.
        QVERIFY(write(helper,
            "#!/bin/sh\n"
            "if [ \"$1\" = catalog ] && [ \"$2\" = --json ]; then\n"
            "  /bin/cat \"$MACTHEMER_RUN/catalog.json\"\n"
            "  exit 0\n"
            "fi\n"
            "if [ \"$1\" = apply ]; then\n"
            "  printf '%s\\n' \"$2\" >> \"$MACTHEMER_RUN/applied.log\"\n"
            "  printf '{\"schema\":1,\"status\":\"applied\",\"theme\":\"%s\",\"warnings\":[]}\\n' \"$2\"\n"
            "  exit 0\n"
            "fi\n"
            "exit 9\n"));
        QVERIFY(QFile::setPermissions(helper, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        QVERIFY(write(dir.filePath("config.toml"), "[providers.apps]\nenabled = false\n[providers.web]\nenabled = false\n[providers.clipboard]\nenabled = false\n"));
        const QString socket = dir.filePath("rpc");
        QProcess daemon;
        struct Guard { QProcess *p; ~Guard() {if (p->state() != QProcess::NotRunning) {p->terminate(); if (!p->waitForFinished(5000)) {p->kill(); p->waitForFinished(2000);}}} } guard{&daemon};
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("MACTHEMER_BIN", dir.filePath("bin")); env.insert("MACTHEMER_STATE", dir.filePath("state")); env.insert("MACTHEMER_RUN", dir.path()); env.insert("MACTHEMER_HOME", dir.path());
        daemon.setProcessEnvironment(env);
        daemon.start(binary, {"--apps", "--config", dir.filePath("config.toml"), "--history", dir.filePath("usage.sqlite3"), "--socket", socket});
        QVERIFY(daemon.waitForStarted(5000));
        QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(socket), 8000);
        const QByteArray oldSocket = qgetenv("MACCER_SERVICE_SOCKET");
        qputenv("MACCER_SERVICE_SOCKET", socket.toUtf8());
        LauncherService svc(false);
        if (oldSocket.isNull()) qunsetenv("MACCER_SERVICE_SOCKET"); else qputenv("MACCER_SERVICE_SOCKET", oldSocket);
        QTRY_VERIFY_WITH_TIMEOUT(svc.ready(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(svc.themeState().value("available").toBool(), 5000);
        const QVariantMap before = svc.themeState();
        svc.setQuery("owned prev");
        QTRY_VERIFY_WITH_TIMEOUT(!svc.searching(), 5000);
        QCOMPARE(svc.results().size(), 1);
        const QVariantMap item = svc.results().first().toMap();
        QCOMPARE(item.value("id").toString(), QStringLiteral("themes:preview-only"));
        svc.requestDetails("themes", item.value("id").toString());
        QTRY_VERIFY_WITH_TIMEOUT(!svc.previewContent().isEmpty(), 5000);
        bool foundPreviewAccent = false;
        for (const QVariant &block : svc.previewContent()) {
            const QVariantMap content = block.toMap();
            if (content.value("type").toString() != "colorPalette") continue;
            const QVariantList swatches = content.value("colors").toList();
            QVERIFY(swatches.size() <= 16);
            for (const QVariant &swatch : swatches) if (swatch.toMap().value("value").toString() == "#abcdef") foundPreviewAccent = true;
        }
        QVERIFY(foundPreviewAccent);
        // The live provider must require consent. An old binary is a failure,
        // not a skipped substitute for the actual end-to-end Apply test.
        QVariantMap applyAction;
        for (const QVariant &candidate : item.value("actions").toList()) {
            const QVariantMap descriptor = candidate.toMap();
            if (descriptor.value("id").toString() == QStringLiteral("apply")) applyAction = descriptor;
        }
        const QString applyPrompt = applyAction.value("confirmation").toString();
        const QString appliedLog = dir.filePath("applied.log");
        const quint64 request = svc.m_request;
        QVERIFY2(!applyPrompt.isEmpty(), "build the current maccer-service with confirmed Apply support");
        svc.activate("themes", item.value("id").toString(), "apply");
        QCOMPARE(svc.m_request, request); // Staged only; no operation sent.
        QVERIFY(!svc.pendingConfirmation().isEmpty());
        QCOMPARE(svc.pendingConfirmation().value("action").toString(), QStringLiteral("apply"));
        QCOMPARE(svc.pendingConfirmation().value("prompt").toString(), applyPrompt);
        QVERIFY(!QFileInfo::exists(appliedLog));
        svc.cancelActivation();
        QVERIFY(svc.pendingConfirmation().isEmpty());
        QCOMPARE(svc.m_request, request);
        QVERIFY(!QFileInfo::exists(appliedLog));
        // Query and navigation changes also discard staged consent.
        svc.activate("themes", item.value("id").toString(), "apply");
        QVERIFY(!svc.pendingConfirmation().isEmpty());
        svc.setQuery(QStringLiteral("owned prev"));
        QTRY_VERIFY_WITH_TIMEOUT(!svc.searching(), 5000);
        QVERIFY(svc.pendingConfirmation().isEmpty());
        QVERIFY(!QFileInfo::exists(appliedLog));
        svc.activate("themes", item.value("id").toString(), "apply");
        QVERIFY(!svc.pendingConfirmation().isEmpty());
        svc.confirmActivation();
        QCOMPARE(svc.m_request, request + 2); // setQuery and the single confirmation each advanced once.
        QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(appliedLog), 8000);
        QFile log(appliedLog);
        QVERIFY(log.open(QIODevice::ReadOnly));
        QCOMPARE(QString::fromUtf8(log.readAll()).trimmed(), QStringLiteral("preview-only"));
        // Only the owned helper recorded anything; the active palette is unchanged.
        QCOMPARE(svc.themeState(), before);
        QVERIFY(daemon.state() == QProcess::Running);
    }

    void actualSharedWebAndClipboardActionsUseOnlyOwnedData() {
        const QString binary = qEnvironmentVariable("MACCER_SHARED_FIXTURE_BIN");
        QVERIFY2(QFileInfo::exists(binary), "Run scripts/launcher-test.sh to build the owned shared-provider fixture");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        const QString socket = dir.filePath("rpc");
        const QString effects = dir.filePath("effects.jsonl");
        QProcess daemon;
        struct Guard { QProcess *p; ~Guard() { if (p->state() != QProcess::NotRunning) { p->terminate(); if (!p->waitForFinished(5000)) { p->kill(); p->waitForFinished(2000); } } } } guard{&daemon};
        daemon.start(binary, {socket, effects});
        QVERIFY(daemon.waitForStarted(5000));
        QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(socket), 5000);
        const QByteArray previous = qgetenv("MACCER_SERVICE_SOCKET");
        qputenv("MACCER_SERVICE_SOCKET", socket.toUtf8());
        LauncherService service(false);
        LauncherService peer(false);
        if (previous.isNull()) qunsetenv("MACCER_SERVICE_SOCKET"); else qputenv("MACCER_SERVICE_SOCKET", previous);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready() && peer.ready(), 5000);
        // Load the actual QML launcher, not a substitute query-refresh callback.
        const QString launcherQml = QFINDTESTDATA("../qml/ricelin/Launcher.qml");
        QVERIFY(!launcherQml.isEmpty());
        QQmlEngine engine;
        engine.addImportPath(QFileInfo(launcherQml).absoluteDir().filePath("../modules"));
        QQmlComponent component(&engine, QUrl::fromLocalFile(launcherQml));
        QScopedPointer<QObject> surface(component.createWithInitialProperties({{"service", QVariant::fromValue(&service)}}));
        QVERIFY2(surface, qPrintable(component.errorString()));
        QQuickWindow window;
        window.setColor(Qt::black); // Standalone surface normally inherits Pill's dark background.
        window.resize(480, 380);
        auto *item = qobject_cast<QQuickItem *>(surface.data());
        QVERIFY(item);
        item->setParentItem(window.contentItem());
        window.show();
        surface->setProperty("open", true);
        auto *field = surface->findChild<QObject *>("launcherInput");
        QVERIFY(field);
        auto search = [&](const QString &query) { field->setProperty("text", query); };
        auto log = [&]() { QFile file(effects); if (!file.open(QIODevice::ReadOnly)) return QList<QByteArray>{}; return file.readAll().trimmed().split('\n'); };
        auto hasAction = [](const QVariantMap &item, const QString &id) {
            for (const QVariant &action : item.value("actions").toList()) if (action.toMap().value("id").toString() == id) return true;
            return false;
        };
        QSignalSpy closed(&service, &LauncherService::closeRequested);
        search(QString::fromUtf8("café & tea"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.results().size(), 2);
        const QVariantMap google = service.results().first().toMap();
        QCOMPARE(google.value("title").toString(), QStringLiteral("Search with Google"));
        auto *list = surface->findChild<QObject *>("launcherResults");
        QVERIFY(list);
        QTRY_COMPARE_WITH_TIMEOUT(list->property("count").toInt(), 2, 5000);
        const QString screenshots = QFileInfo(QCoreApplication::applicationFilePath()).absoluteDir().filePath("../screenshots");
        QVERIFY(QDir().mkpath(screenshots));
        QTRY_VERIFY_WITH_TIMEOUT(window.isExposed(), 5000);
        QVERIFY(window.grabWindow().save(screenshots + "/launcher-shared-web.png"));
        QVERIFY(QMetaObject::invokeMethod(surface.data(), "activate", Q_ARG(QVariant, false)));
        QTRY_COMPARE_WITH_TIMEOUT(closed.count(), 1, 5000);
        QCOMPARE(QJsonDocument::fromJson(log().last()).object().value("text").toString(), QStringLiteral("https://www.google.com/search?q=caf%C3%A9+%26+tea"));
        search("? owned");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        service.activate("web", "web:google", "copy-url");
        QTRY_COMPARE_WITH_TIMEOUT(closed.count(), 2, 5000);
        QCOMPARE(QJsonDocument::fromJson(log().last()).object().value("text").toString(), QStringLiteral("https://www.google.com/search?q=owned"));
        search(":");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.results().size(), 2);
        QTRY_COMPARE_WITH_TIMEOUT(list->property("count").toInt(), 2, 5000);
        const QString second = service.results().first().toMap().value("id").toString();
        QVERIFY(!hasAction(service.results().first().toMap(), "paste"));
        service.requestDetails("clipboard", second);
        QTRY_VERIFY_WITH_TIMEOUT(!service.previewContent().isEmpty(), 5000);
        QCOMPARE(service.previewContent().first().toMap().value("text").toString(), QStringLiteral("Owned second entry\nSecond preview body"));
        auto *preview = surface->findChild<QObject *>("launcherPreview");
        QVERIFY(preview);
        QTRY_VERIFY_WITH_TIMEOUT(preview->property("visible").toBool(), 5000);
        QVERIFY(window.grabWindow().save(screenshots + "/launcher-shared-clipboard.png"));
        QVERIFY(QMetaObject::invokeMethod(surface.data(), "showActions"));
        int pinIndex = -1;
        const QVariantList actions = service.results().first().toMap().value("actions").toList();
        for (int i = 0; i < actions.size(); ++i) if (actions[i].toMap().value("id").toString() == "pin") pinIndex = i;
        QVERIFY(pinIndex >= 0);
        surface->setProperty("actionIndex", pinIndex);
        QVERIFY(QMetaObject::invokeMethod(surface.data(), "activate", Q_ARG(QVariant, false)));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching() && !service.busy() && !service.results().isEmpty() && service.results().first().toMap().value("subtitle").toString() == "Pinned", 5000);
        QCOMPARE(service.query(), QStringLiteral(":"));
        peer.setQuery(":");
        QTRY_VERIFY_WITH_TIMEOUT(!peer.searching(), 5000);
        QCOMPARE(peer.results().first().toMap().value("subtitle").toString(), QStringLiteral("Pinned"));
        service.activate("clipboard", second, "unpin");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching() && !service.busy() && !service.results().isEmpty() && hasAction(service.results().first().toMap(), "pin"), 5000);
        service.activate("clipboard", second, "copy");
        QTRY_COMPARE_WITH_TIMEOUT(closed.count(), 3, 5000);
        const QJsonObject copied = QJsonDocument::fromJson(log().last()).object();
        QCOMPARE(copied.value("kind").toString(), QStringLiteral("copy"));
        QCOMPARE(copied.value("text").toString(), QStringLiteral("Owned second entry\nSecond preview body"));
        service.setQuery(":");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        service.activate("clipboard", second, "delete");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching() && !service.busy() && service.results().size() == 1, 5000);
        service.cancel();
        peer.setQuery(":");
        QTRY_VERIFY_WITH_TIMEOUT(!peer.searching(), 5000);
        QCOMPARE(peer.results().size(), 1); // Disconnecting a view does not own history.
        QObject::connect(&peer, &LauncherService::queryRequested, &peer, &LauncherService::setQuery);
        peer.activate("clipboard", peer.results().first().toMap().value("id").toString(), "clear");
        QTRY_VERIFY_WITH_TIMEOUT(!peer.searching() && !peer.busy() && peer.results().isEmpty(), 5000);
        QCOMPARE(log().size(), 3); // Only Google open, URL copy and entry copy.
        QVERIFY(daemon.state() == QProcess::Running);
    }

    void serviceTypingRetainsDisplayButRevokesOldAuthority() {
        LauncherService service(true);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery("Safari");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        service.m_serviceMode = true; // Inert agent; exercise the service display policy.
        service.m_hasDetails = true;
        const quint64 oldRequest = service.m_request;
        service.m_detailProvider = "apps";
        service.m_detailId = "safari";
        service.m_detailRequest = 17;
        service.m_previewContent = {QVariantMap{{"type", "text"}, {"text", "Owned old preview"}}};
        const QVariantList rows = service.results();
        const QVariantList preview = service.previewContent();
        service.setQuery("next query");
        QVERIFY(service.searching());
        QCOMPARE(service.results(), rows);
        QCOMPARE(service.previewContent(), preview);
        QCOMPARE(service.m_resultRequest, quint64(0));
        QVERIFY(service.m_detailId.isEmpty());
        const quint64 pending = service.m_request;
        const QVariantMap item = rows.first().toMap();
        service.activate(item.value("provider").toString(), item.value("id").toString(), "open");
        service.requestDetails("apps", "safari");
        service.confirmActivation();
        QCOMPARE(service.m_request, pending);
        service.applyEvent("{\"type\":\"details\",\"request\":" + QByteArray::number(oldRequest) + ",\"detailRequest\":17,\"provider\":\"apps\",\"id\":\"safari\",\"content\":[]}");
        QCOMPARE(service.previewContent(), preview);
        // A failed replacement must not reauthorize retained display-only rows.
        service.applyEvent("{\"type\":\"error\",\"request\":" + QByteArray::number(pending) + ",\"message\":\"Owned failure\"}");
        QVERIFY(!service.searching());
        service.activate(item.value("provider").toString(), item.value("id").toString(), "open");
        service.requestDetails("apps", "safari");
        QCOMPARE(service.m_request, pending);
        QVERIFY(service.m_detailId.isEmpty());
        service.applyEvent("{\"type\":\"results\",\"request\":" + QByteArray::number(pending) + ",\"items\":[],\"complete\":true}");
        QVERIFY(service.results().isEmpty());
        QVERIFY(service.previewContent().isEmpty());
        service.m_previewLoading = true;
        service.setQuery("another pending query");
        QVERIFY(service.previewLoading()); // Keep even an existing loading panel stable.
    }

    void serviceModeBrowsesConfiguredGoogleWithoutDesktopEffects() {
        QString source = qEnvironmentVariable("MACCER_SOURCE");
        if (source.isEmpty()) source = QDir::homePath() + QStringLiteral("/Documents/maccer");
        QString binary = qEnvironmentVariable("MACCER_SERVICE_BIN");
        if (binary.isEmpty()) binary = source + QStringLiteral("/target/debug/maccer-service");
        QVERIFY2(QFileInfo::exists(binary), "Build the current maccer-service before running launcher tests");
        QTemporaryDir dir;
        QVERIFY(dir.isValid());
        QFile config(dir.filePath("config.toml"));
        QVERIFY(config.open(QIODevice::WriteOnly));
        config.write("[providers.apps]\nenabled=false\n[providers.themes]\nenabled=false\n[providers.clipboard]\nenabled=false\n");
        config.close();
        const QString socket = dir.filePath("rpc");
        QProcess daemon;
        struct Guard { QProcess *p; ~Guard() { if (p->state() != QProcess::NotRunning) { p->terminate(); if (!p->waitForFinished(5000)) { p->kill(); p->waitForFinished(2000); } } } } guard{&daemon};
        QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
        env.insert("MACTHEMER_STATE", dir.filePath("state"));
        daemon.setProcessEnvironment(env);
        daemon.start(binary, {"--apps", "--config", dir.filePath("config.toml"), "--history", dir.filePath("history.sqlite3"), "--socket", socket});
        QVERIFY(daemon.waitForStarted(5000));
        QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(socket), 8000);
        const QByteArray previous = qgetenv("MACCER_SERVICE_SOCKET");
        qputenv("MACCER_SERVICE_SOCKET", socket.toUtf8());
        LauncherService service(false);
        if (previous.isNull()) qunsetenv("MACCER_SERVICE_SOCKET"); else qputenv("MACCER_SERVICE_SOCKET", previous);
        QTRY_VERIFY_WITH_TIMEOUT(service.ready(), 5000);
        service.setQuery(QString::fromUtf8("café & tea"));
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        QCOMPARE(service.results().size(), 2);
        const QVariantMap google = service.results().first().toMap();
        QCOMPARE(google.value("provider").toString(), QStringLiteral("web"));
        QCOMPARE(google.value("title").toString(), QStringLiteral("Search with Google"));
        QCOMPARE(google.value("actions").toList().first().toMap().value("id").toString(), QStringLiteral("search"));
        QVERIFY(!google.contains("payload"));
        QVERIFY(!google.contains("url"));
        service.setQuery(": private fixture");
        QTRY_VERIFY_WITH_TIMEOUT(!service.searching(), 5000);
        for (const QVariant &row : service.results())
            QVERIFY(row.toMap().value("provider").toString() != QStringLiteral("clipboard"));
        QVERIFY(daemon.state() == QProcess::Running);
        // Deliberately do not activate a real URL or touch the system clipboard.
    }

    void serviceModeSearchesAndNavigatesHomeAgainstRealFixtureService() {
        QString binary = qEnvironmentVariable("MACCER_SERVICE_BIN");
        if (binary.isEmpty()) {
            QString source = qEnvironmentVariable("MACCER_SOURCE");
            if (source.isEmpty()) source = QDir::homePath() + QStringLiteral("/Documents/maccer");
            binary = source + QStringLiteral("/target/debug/maccer-service");
        }
        if (!QFileInfo::exists(binary))
            QSKIP("set MACCER_SERVICE_BIN to a maccer-service fixture binary to run this test");
        QTemporaryDir dir; // 0700 by default, as the service requires.
        QVERIFY(dir.isValid());
        const QString socket = dir.filePath(QStringLiteral("rpc"));
        QProcess service;
        struct Guard {
            QProcess *process;
            ~Guard() {
                if (process->state() != QProcess::NotRunning) {
                    process->terminate();
                    if (!process->waitForFinished(2000)) process->kill();
                }
            }
        } guard{&service};
        service.start(binary, {QStringLiteral("--fixture"), QStringLiteral("--socket"), socket});
        QVERIFY2(service.waitForStarted(5000), qPrintable(service.errorString()));
        for (int i = 0; i < 300 && !QFileInfo::exists(socket); ++i) QTest::qWait(10);
        QVERIFY(QFileInfo::exists(socket));

        qputenv("MACCER_SERVICE_SOCKET", socket.toUtf8());
        LauncherService svc(false);
        qunsetenv("MACCER_SERVICE_SOCKET");
        QVERIFY(svc.serviceMode());
        QTRY_VERIFY_WITH_TIMEOUT(svc.ready(), 5000);
        QTRY_VERIFY_WITH_TIMEOUT(svc.themeState().value("available").toBool(), 5000);
        const QVariantMap themeState = svc.themeState();
        const QVariantMap palette = themeState.value("palette").toMap();
        QCOMPARE(palette.value("schema").toInt(), 1);
        QCOMPARE(palette.value("slug").toString(), QStringLiteral("maccer-fixture"));
        QVERIFY(!themeState.value("canSelect").toBool());
        QVERIFY(!themeState.value("canNext").toBool());
        QVERIFY(themeState.value("themes").toList().isEmpty());
        const QByteArray invalidTheme = "{\"type\":\"themeState\",\"state\":{\"revision\":\"bad\",\"available\":true,\"palette\":{\"schema\":1},\"error\":null}}";
        svc.applyEvent(invalidTheme);
        QCOMPARE(svc.themeState(), themeState);
        svc.setQuery(QStringLiteral("saf"));
        QTRY_VERIFY_WITH_TIMEOUT(!svc.searching(), 5000);
        QVERIFY(!svc.results().isEmpty());
        QVERIFY2(!svc.providerScoped(), "home search results must report the home route");
        svc.setQuery(QStringLiteral("Catppuccin"));
        QTRY_VERIFY_WITH_TIMEOUT(!svc.searching(), 5000);
        QVariantMap theme;
        for (const QVariant &entry : svc.results()) {
            if (entry.toMap().value("provider").toString() == QStringLiteral("themes")) theme = entry.toMap();
        }
        QVERIFY(!theme.isEmpty());
        const quint64 beforeDetails = svc.m_request;
        svc.requestDetails(QStringLiteral("themes"), theme.value("id").toString());
        QTRY_VERIFY_WITH_TIMEOUT(!svc.previewContent().isEmpty(), 5000);
        QVERIFY(!svc.previewLoading());
        QCOMPARE(svc.m_request, beforeDetails);
        QCOMPARE(svc.previewContent().first().toMap().value("type").toString(), QStringLiteral("colorPalette"));
        // A selected-result preview cannot be replaced by another selection's reply.
        svc.applyEvent("{\"type\":\"details\",\"request\":" + QByteArray::number(svc.m_request) +
            ",\"detailRequest\":" + QByteArray::number(svc.m_detailRequest) +
            ",\"provider\":\"themes\",\"id\":\"wrong\",\"content\":[]}");
        QVERIFY(!svc.previewContent().isEmpty());
        svc.clearDetails();
        QVERIFY(svc.previewContent().isEmpty());
        svc.applyEvent("{\"type\":\"details\",\"request\":" + QByteArray::number(svc.m_request) +
            ",\"detailRequest\":" + QByteArray::number(svc.m_detailRequest) +
            ",\"provider\":\"themes\",\"id\":\"wrong\",\"content\":[]}");
        QVERIFY(svc.previewContent().isEmpty());
        const quint64 oldSnapshot = svc.m_resultRequest;
        svc.applyEvent("{\"type\":\"assetExpired\",\"request\":" + QByteArray::number(oldSnapshot) + "}");
        QCOMPARE(svc.m_request, oldSnapshot + 1);
        QVERIFY(svc.results().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!svc.searching(), 5000);
        QVERIFY(!svc.results().isEmpty());
        QCOMPARE(svc.query(), QStringLiteral("Catppuccin"));
        const quint64 refreshed = svc.m_request;
        svc.applyEvent("{\"type\":\"assetExpired\",\"request\":" + QByteArray::number(oldSnapshot) + "}");
        QCOMPARE(svc.m_request, refreshed); // Stale expiry cannot start another refresh.
        QSignalSpy queries(&svc, &LauncherService::queryRequested);
        svc.home();
        QTRY_COMPARE_WITH_TIMEOUT(queries.count(), 1, 5000);
        QCOMPARE(queries.first().first().toString(), QString());
        QVERIFY(!svc.busy());
        QVERIFY(!svc.providerScoped());
        svc.cancel();
        QCOMPARE(svc.themeState(), themeState); // Persistent state is not view authority.
    }
};

QTEST_MAIN(LauncherServiceTest)
#include "tst_launcher.moc"
