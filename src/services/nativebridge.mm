#import <Foundation/Foundation.h>
#import "PillNative-Swift.h"
#include "nativebridge.h"
#include <QCoreApplication>
#include <QQmlEngine>
#include <QThread>
#include <qqml.h>

struct NativeBridge::Native {
    PillNativeBackend *backend = [[PillNativeBackend alloc] init];
};

NativeBridge::NativeBridge(QObject *parent)
    : QObject(parent ? parent : QCoreApplication::instance()) {
    // Parenting pins affinity to the main thread and prevents moveToThread.
    if (![NSThread isMainThread] || thread() != QThread::currentThread())
        qFatal("NativeBridge must be created on the macOS main / Qt owner thread");
    m_native = std::make_unique<Native>();
    [m_native->backend startWithCallback:^{
        // Swift promises main-thread callback delivery, serialized with stop.
        // Thus this pointer remains valid while posting. Qt's context removes
        // any pending invocation if the object is destroyed before delivery.
        QMetaObject::invokeMethod(this, [this] {
            if (m_ready) return;
            m_ready = true;
            emit readyChanged();
        }, Qt::QueuedConnection);
    }];
}

NativeBridge::~NativeBridge() {
    if (![NSThread isMainThread] || thread() != QThread::currentThread())
        qFatal("NativeBridge must be destroyed on its macOS main / Qt owner thread");
    [m_native->backend stop]; // Clears the block before releasing its raw Qt pointer.
}

void registerNativeServices() {
    qmlRegisterSingletonType<NativeBridge>("Pill.MacOS", 1, 0, "Bridge",
        [](QQmlEngine *engine, QJSEngine *) -> QObject * {
            return new NativeBridge(engine);
        });
}
