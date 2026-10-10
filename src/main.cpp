#include <QGuiApplication>
#include <QCommandLineParser>
#include <QFont>
#include <QQuickItem>
#include <QQmlApplicationEngine>
#include <QQmlProperty>
#include "host.h"
#include "services/nativebridge.h"
#include "services/audio.h"

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("PillSpike");
    app.setFont(QFont("Helvetica Neue"));
    app.setQuitOnLastWindowClosed(true);
    QCommandLineParser parser;
    parser.setApplicationDescription("Isolated macOS / Qt Quick morphing pill spike");
    parser.addHelpOption();
    parser.addOption({"top-offset", "Pixels from the screen top; default matches omacosy.", "pixels", "0"});
    parser.addOption({"self-test", "Run native checks, save screenshots, and exit.", "directory"});
    parser.addOption({"trace-preview", "Log local mixer focus/value changes for input diagnostics."});
    parser.addOption({"test-audio", "Use the labelled in-memory Audio test fixture; never access hardware."});
    parser.process(app);
    bool ok;
    int offset = parser.value("top-offset").toInt(&ok);
    if (!ok || offset < 0 || offset > 500) {
        qCritical("--top-offset must be an integer between 0 and 500");
        return 2;
    }
    registerNativeServices();
    registerAudioService(parser.isSet("test-audio") || parser.isSet("self-test"));
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
    view->show();
    host.syncGeometry();
    if (parser.isSet("self-test")) host.runSelfTest(parser.value("self-test"));
    return app.exec();
}
