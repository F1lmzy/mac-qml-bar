#include <QGuiApplication>
#include <QCommandLineParser>
#include <QFont>
#include <QQuickItem>
#include <QQmlApplicationEngine>
#include <QQmlProperty>
#include <maccer_agent.h>
#include <memory>
#include "host.h"
#include "services/nativebridge.h"
#include "services/audio.h"
#include "services/system.h"
#include "services/launcher.h"

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("PillSpike");
    app.setFont(QFont("Helvetica Neue"));
    app.setQuitOnLastWindowClosed(true);
    QCommandLineParser parser;
    parser.setApplicationDescription("Isolated macOS / Qt Quick morphing pill spike");
    parser.addHelpOption();
    parser.addOption({"top-offset", "Pixels from the screen top; default matches omacosy.", "pixels", "2"});
    parser.addOption({"self-test", "Run native checks, save screenshots, and exit.", "directory"});
    parser.addOption({"trace-preview", "Log local mixer focus/value changes for input diagnostics."});
    parser.addOption({"test-audio", "Use labelled in-memory services; legacy alias for --test-services."});
    parser.addOption({"test-services", "Use labelled in-memory services; no hardware, permissions, helpers or network."});
    parser.addOption({"show-launcher", "Open the embedded maccer launcher on startup."});
    parser.process(app);
    bool ok;
    int offset = parser.value("top-offset").toInt(&ok);
    if (!ok || offset < 0 || offset > 500) {
        qCritical("--top-offset must be an integer between 0 and 500");
        return 2;
    }
    const bool testServices = parser.isSet("test-services") || parser.isSet("test-audio") || parser.isSet("self-test");
    std::unique_ptr<MaccerFrontendClaim, decltype(&maccer_agent_frontend_claim_free)> frontendClaim(nullptr, maccer_agent_frontend_claim_free);
    const QByteArray serviceSocket = qgetenv("MACCER_SERVICE_SOCKET");
    if (!testServices && !serviceSocket.isEmpty()) {
        char *error = nullptr;
        frontendClaim.reset(maccer_agent_claim_frontend(serviceSocket.constData(), "pill", &error));
        if (!frontendClaim) {
            qCritical("Pill frontend startup refused: %s", error ? error : "frontend admission failed");
            maccer_agent_string_free(error);
            return 2;
        }
    }
    registerNativeServices();
    registerAudioService(testServices);
    registerSystemService(testServices);
    registerLauncherService(testServices);
    QQmlApplicationEngine engine;
    engine.addImportPath("qrc:/qml/modules");
    engine.load(QUrl("qrc:/qml/shell.qml"));
    if (engine.rootObjects().size() != 1) { qCritical("Expected one shell.qml root"); return 1; }
    auto *view = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
    QVariant valid;
    if (!view || !QMetaObject::invokeMethod(view, "validate", Q_RETURN_ARG(QVariant, valid)) || !valid.toBool()) {
        qCritical("Invalid or unsupported PanelWindow declaration");
        return 1;
    }
    auto *pill = qobject_cast<QQuickItem *>(QQmlProperty::read(view, "pill").value<QObject *>());
    if (!pill) { qCritical("shell.qml must expose its pill Item"); return 1; }
    pill->setProperty("tracePreview", parser.isSet("trace-preview"));
    QObject::connect(pill, SIGNAL(quitRequested()), &app, SLOT(quit()));
    Host host(*view, *pill, offset, parser.isSet("self-test"));
    if (auto *system = engine.singletonInstance<System *>(qmlTypeId("Pill.MacOS", 1, 0, "System"))) {
        QObject::connect(system, &System::focusTransferred, &host, &Host::forgetFocusRestore);
        QObject::connect(&app, &QCoreApplication::aboutToQuit, system, &System::prepareForExit);
    }
    if (auto *launcher = engine.singletonInstance<LauncherService *>(qmlTypeId("Pill.MacOS", 1, 0, "Maccer"))) {
        QObject::connect(launcher, &LauncherService::focusTransferred, &host, &Host::forgetFocusRestore);
    }
    view->show();
    host.syncGeometry();
    if (parser.isSet("show-launcher")) QMetaObject::invokeMethod(pill, "openLauncher");
    if (parser.isSet("self-test")) host.runSelfTest(parser.value("self-test"));
    return app.exec();
}
