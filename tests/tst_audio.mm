#import <Foundation/Foundation.h>
#import "PillNative-Swift.h"
#include "../src/services/audio.h"
#include <QSignalSpy>
#include <QThread>
#include <QtTest>
#include <QQmlComponent>
#include <QQmlEngine>

class AudioTest : public QObject {
    Q_OBJECT
private slots:
    void callbackAndActionsUseOwnerThread() {
        Audio audio(true);
        QSignalSpy errors(&audio, &Audio::errorOccurred);
        bool correctThread = true;
        connect(&audio, &Audio::stateChanged, this, [&] {
            correctThread &= QThread::currentThread() == audio.thread();
        });
        QTRY_VERIFY(audio.available());
        QCOMPARE(audio.volume(), 0.45);
        audio.setVolume(0.61);
        QTRY_COMPARE(audio.volume(), 0.61);
        audio.setMuted(true);
        QTRY_VERIFY(audio.muted());
        QCOMPARE(audio.volume(), 0.61); // Mute never zeroes observed scalar.
        audio.setVolume(qQNaN());
        audio.setVolume(0.62); // A later valid request must not swallow invalid input.
        QTRY_VERIFY(errors.count() > 0);
        QCOMPARE(errors.first().at(1).toString(), QString("invalidInput"));
        QTRY_COMPARE(audio.volume(), 0.62);
        QVERIFY(correctThread);
    }

    void rapidRequestsCoalesceToLastValue() {
        Audio audio(true);
        QTRY_VERIFY(audio.volumeKnown());
        for (int i = 0; i < 50; ++i) audio.setVolume(i / 100.0);
        QTRY_COMPARE(audio.volume(), 0.49);
    }

    void destructionCancelsPendingCallbacks() {
        int calls = 0;
        for (int i = 0; i < 100; ++i) {
            auto *audio = new Audio(true);
            connect(audio, &Audio::stateChanged, this, [&] { ++calls; });
            audio->setVolume(0.9);
            delete audio;
        }
        QTest::qWait(100);
        QCOMPARE(calls, 0);
        QCOMPARE([PillAudioService liveInstanceCount], 0);
    }

    void destructionFromStateChangedIsSafe() {
        auto *audio = new Audio(true);
        connect(audio, &Audio::stateChanged, this, [&] {
            delete audio;
            audio = nullptr;
        });
        QTRY_VERIFY(audio == nullptr);
        QCOMPARE([PillAudioService liveInstanceCount], 0);
    }

    void nativeStopSuppressesCallbackWhileRetained() {
        __block int calls = 0;
        @autoreleasepool {
            PillAudioService *service = [[PillAudioService alloc] initWithFake:YES];
            [service startWithCallback:^(NSDictionary *) { ++calls; }];
            [service stop];
            [service stop];
            QTest::qWait(50);
            QCOMPARE(calls, 0);
        }
        QCOMPARE([PillAudioService liveInstanceCount], 0);
    }

    void qmlActionsNeverOptimisticallyChangeObservedValue() {
        registerAudioService(true);
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQml\nimport Pill.MacOS 1.0\nQtObject {"
                          "property real observed: Audio.volume;"
                          "function change() { Audio.setVolume(0.83) }"
                          "}", QUrl());
        QScopedPointer<QObject> object(component.create());
        QVERIFY2(object, qPrintable(component.errorString()));
        QTRY_COMPARE(object->property("observed").toReal(), 0.45);
        QVERIFY(QMetaObject::invokeMethod(object.data(), "change"));
        QCOMPARE(object->property("observed").toReal(), 0.45);
        QTRY_COMPARE(object->property("observed").toReal(), 0.83);
    }
};
QTEST_MAIN(AudioTest)
#include "tst_audio.moc"
