#include <QGuiApplication>
#include <QCommandLineParser>
#include <QFont>
#include <QQuickItem>
#include "host.h"

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
    parser.process(app);
    bool ok;
    int offset = parser.value("top-offset").toInt(&ok);
    if (!ok || offset < 0 || offset > 500) {
        qCritical("--top-offset must be an integer between 0 and 500");
        return 2;
    }
    QQuickView view;
    view.setTitle("PillSpike");
    view.setFlags(Qt::Tool | Qt::FramelessWindowHint);
    view.setColor(Qt::transparent);
    view.setResizeMode(QQuickView::SizeViewToRootObject);
    view.setSource(QUrl("qrc:/qml/Pill.qml"));
    if (view.status() != QQuickView::Ready) return 1;
    QObject::connect(view.rootObject(), SIGNAL(quitRequested()), &app, SLOT(quit()));
    Host host(view, offset, parser.isSet("self-test"));
    view.show();
    host.syncGeometry();
    if (parser.isSet("self-test")) host.runSelfTest(parser.value("self-test"));
    return app.exec();
}
