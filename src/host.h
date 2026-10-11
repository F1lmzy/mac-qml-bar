#pragma once
#include <QObject>
#include <QTimer>
#include <QQuickWindow>
#include <QQuickItem>

class Host : public QObject {
    Q_OBJECT
public:
    Host(QQuickWindow &view, QQuickItem &pill, int topOffset, bool selfTest);
    ~Host() override;
    void runSelfTest(const QString &directory);
public slots:
    void syncGeometry();
    void updateMode();
    void forgetFocusRestore();
private:
    void updatePointer();
    QQuickWindow &view;
    QQuickItem &pill;
    QTimer pointerTimer;
    void *catcher = nullptr;
    void *previousApplication = nullptr;
    int topOffset;
    bool testing;
    bool expanded = false;
    bool suppressHoverUntilExit = false;
};
