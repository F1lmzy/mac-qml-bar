#import <Foundation/Foundation.h>
#import "PillNative-Swift.h"
#include "../src/services/system.h"
#include <QSignalSpy>
#include <QThread>
#include <QtTest>
#include <QQmlComponent>
#include <QQmlEngine>

class SystemTest : public QObject {
    Q_OBJECT
private slots:
    void callbacksAndConfirmedActions() {
        System system(true);
        bool mainThread = true;
        connect(&system, &System::stateChanged, this, [&] { mainThread &= QThread::currentThread() == system.thread(); });
        QTRY_VERIFY(system.brightness().value("known").toBool());
        QTRY_VERIFY(system.windowManager().value("available").toBool());
        QCOMPARE(system.brightness().value("value").toDouble(), 0.7);
        system.invoke("brightness", "set", QVariantMap{{"value", 0.61}, {"displayId", "42"}});
        QCOMPARE(system.brightness().value("value").toDouble(), 0.7);
        QTRY_COMPARE(system.brightness().value("value").toDouble(), 0.61);
        system.invoke("wifi", "requestPermission");
        QTRY_VERIFY(system.wifi().value("ssidKnown").toBool());
        QCOMPARE(system.wifi().value("ssid").toString(), QString("TEST network"));
        QVERIFY(mainThread);
    }
    void confirmedWorkspaceChangeDiscardsOldFocusRestore() {
        System system(true);
        QTRY_VERIFY(system.windowManager().contains("focusedWorkspace"));
        QSignalSpy transferred(&system, &System::focusTransferred);
        system.invoke("windowManager", "switchWorkspace", QString("web"));
        QCOMPARE(transferred.count(), 0);
        QTRY_COMPARE(system.windowManager().value("focusedWorkspace").toString(), QString("web"));
        QCOMPARE(transferred.count(), 1);
    }
    void invalidAndStaleInputsAreReported() {
        System system(true);
        QTRY_VERIFY(system.brightness().value("known").toBool());
        QSignalSpy errors(&system, &System::errorOccurred);
        system.invoke("brightness", "set", QVariantMap{{"value", 0.9}, {"displayId", "missing"}});
        QTRY_VERIFY(errors.count() > 0);
        QCOMPARE(system.brightness().value("value").toDouble(), 0.7);
        errors.clear();
        system.invoke("desktop", "restart", QVariantMap{{"confirmed", false}});
        QTRY_VERIFY(errors.count() > 0);
        QCOMPARE(errors.first().at(2).toString(), QString("confirmationRequired"));
    }
    void allFixtureDomainsArrive() {
        System system(true);
        QTRY_VERIFY(system.outputDevices().contains("devices"));
        QTRY_VERIFY(system.bluetooth().contains("permission"));
        QTRY_VERIFY(system.display().contains("nightShiftKnown"));
        QTRY_VERIFY(system.menus().contains("frontPid"));
        QTRY_VERIFY(system.weather().contains("enabled"));
        QTRY_VERIFY(system.spotify().contains("title"));
        QTRY_VERIFY(system.battery().contains("charge"));
        QTRY_VERIFY(system.theme().contains("canNext"));
    }
    void destructionCancelsAllPendingDeliveries() {
        int delivered = 0;
        for (int i = 0; i < 100; ++i) {
            auto *system = new System(true);
            connect(system, &System::stateChanged, this, [&] { ++delivered; });
            system->invoke("brightness", "set", QVariantMap{{"value", 0.9}, {"displayId", "42"}});
            delete system;
        }
        QTest::qWait(100);
        QCOMPARE(delivered, 0);
        QCOMPARE([PillSystemService liveInstanceCount], 0);
    }
    void deletingDuringDeliveryIsSafe() {
        auto *system = new System(true);
        connect(system, &System::stateChanged, this, [&] { delete system; system = nullptr; });
        QTRY_VERIFY(system == nullptr);
        QCOMPARE([PillSystemService liveInstanceCount], 0);
    }
    void nativeStopAndRestartSuppressOldDeliveries() {
        __block int oldCalls = 0, newCalls = 0;
        @autoreleasepool {
            PillSystemService *service = [[PillSystemService alloc] initWithFake:YES];
            [service startWithCallback:^(NSString *, NSDictionary *) { ++oldCalls; }];
            [service stop]; [service stop];
            QTest::qWait(30);
            QCOMPARE(oldCalls, 0);
            [service startWithCallback:^(NSString *, NSDictionary *) { ++newCalls; }];
            QTRY_VERIFY(newCalls > 0);
            QCOMPARE(oldCalls, 0);
            [service stop];
        }
        QCOMPARE([PillSystemService liveInstanceCount], 0);
    }
    void qmlMapsStayObserved() {
        registerSystemService(true);
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQml\nimport Pill.MacOS 1.0\nQtObject {"
                          "property real level: System.brightness.known ? System.brightness.value : -1;"
                          "function change() { System.invoke('brightness', 'set', {value: .42, displayId: '42'}) } }", QUrl());
        QScopedPointer<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        QTRY_COMPARE(object->property("level").toReal(), 0.7);
        QVERIFY(QMetaObject::invokeMethod(object.data(), "change"));
        QCOMPARE(object->property("level").toReal(), 0.7);
        QTRY_COMPARE(object->property("level").toReal(), 0.42);
    }
};
QTEST_MAIN(SystemTest)
#include "tst_system.moc"
