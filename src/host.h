#pragma once
#include <QObject>
#include <QTimer>
#include <QQuickView>

class Host : public QObject {
    Q_OBJECT
public:
    Host(QQuickView &view, int topOffset, bool selfTest);
    ~Host() override;
    void runSelfTest(const QString &directory);
public slots:
    void syncGeometry();
    void updateMode();
private:
    void updatePointer();
    QQuickView &view;
    QTimer pointerTimer;
    void *catcher = nullptr;
    void *previousApplication = nullptr;
    int topOffset;
    bool testing;
    bool expanded = false;
    bool suppressHoverUntilExit = false;
};
