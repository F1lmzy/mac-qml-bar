#import <Foundation/Foundation.h>
#import "PillNative-Swift.h"
#include <QtTest>
#include <QQmlComponent>
#include <QQmlEngine>
#include "../src/services/nativebridge.h"

class NativeBridgeTest : public QObject {
    Q_OBJECT
private slots:
    void callbackUpdatesQtPropertyOnOwnerThread() {
        NativeBridge bridge;
        QVERIFY(!bridge.ready());
        QSignalSpy changed(&bridge, &NativeBridge::readyChanged);
        bool onOwnerThread = false;
        connect(&bridge, &NativeBridge::readyChanged, &bridge, [&] {
            onOwnerThread = QThread::currentThread() == bridge.thread();
        });
        QTRY_VERIFY(bridge.ready());
        QCOMPARE(changed.count(), 1);
        QVERIFY(onOwnerThread);
    }

    void destructionCancelsPendingDelivery() {
        int deliveredAfterDelete = 0;
        for (int i = 0; i < 100; ++i) {
            auto *bridge = new NativeBridge;
            connect(bridge, &NativeBridge::readyChanged, this, [&] { ++deliveredAfterDelete; });
            delete bridge; // Native dispatch is still pending.
        }
        QTest::qWait(50);
        QCOMPARE(deliveredAfterDelete, 0);
        QCOMPARE([PillNativeBackend liveInstanceCount], 0);
    }

    void repeatedCompletedLifetimesReleaseNativeBackend() {
        for (int i = 0; i < 20; ++i) {
            auto *bridge = new NativeBridge;
            QTRY_VERIFY(bridge->ready());
            delete bridge;
            QCOMPARE([PillNativeBackend liveInstanceCount], 0);
        }
    }

    void stopClearsCallbackAndAllowsNativeRelease() {
        __block int callbacks = 0;
        @autoreleasepool {
            PillNativeBackend *backend = [[PillNativeBackend alloc] init];
            [backend startWithCallback:^{ ++callbacks; }];
            [backend stop];
            [backend stop]; // Teardown is idempotent.
            QTest::qWait(50); // Keep backend alive while canceled delivery drains.
            QCOMPARE(callbacks, 0);
        }
        QCOMPARE(callbacks, 0);
        QCOMPARE([PillNativeBackend liveInstanceCount], 0);
    }

    void destructionInsideDeliveryIsSafe() {
        auto *bridge = new NativeBridge;
        connect(bridge, &NativeBridge::readyChanged, this, [&] {
            delete bridge;
            bridge = nullptr;
        });
        QTRY_VERIFY(bridge == nullptr);
        QTest::qWait(50);
        QCOMPARE([PillNativeBackend liveInstanceCount], 0);
    }

    void restartRejectsTheOldPendingCallback() {
        __block int stale = 0;
        __block int current = 0;
        @autoreleasepool {
            PillNativeBackend *backend = [[PillNativeBackend alloc] init];
            [backend startWithCallback:^{ ++stale; }];
            [backend stop];
            [backend startWithCallback:^{ ++current; }];
            QTRY_COMPARE(current, 1);
            QCOMPARE(stale, 0);
            [backend stop];
        }
        QCOMPARE([PillNativeBackend liveInstanceCount], 0);
    }

    void qmlModuleExposesOnlyBridgeHealth() {
        registerNativeServices();
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQml\nimport Pill.MacOS 1.0\n"
                          "QtObject { property bool connected: Bridge.ready }", QUrl());
        QScopedPointer<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        QTRY_VERIFY(object->property("connected").toBool());
        QVERIFY(!object->property("volume").isValid());
    }

    void cleanupTestCase() {
        QTest::qWait(50);
        QCOMPARE([PillNativeBackend liveInstanceCount], 0);
    }
};

QTEST_MAIN(NativeBridgeTest)
#include "tst_nativebridge.moc"
