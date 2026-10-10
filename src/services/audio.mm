#import <Foundation/Foundation.h>
#import "PillNative-Swift.h"
#include "audio.h"
#include <QCoreApplication>
#include <QMetaObject>
#include <QPointer>
#include <QQmlEngine>
#include <QThread>
#include <QVariantMap>
#include <qqml.h>

struct Audio::Native {
    PillAudioService *service = nil;
};

static void requireOwnerThread(const QObject *object, const char *operation) {
    if (![NSThread isMainThread] || object->thread() != QThread::currentThread())
        qFatal("Audio %s must run on the macOS main / Qt owner thread", operation);
}

static QString snapshotString(NSDictionary *snapshot, NSString *key) {
    id value = snapshot[key];
    return [value isKindOfClass:[NSString class]] ? QString::fromNSString(value) : QString();
}

Audio::Audio(bool testBackend, QObject *parent)
    : QObject(parent ? parent : QCoreApplication::instance()), m_testBackend(testBackend) {
    requireOwnerThread(this, "construction");
    m_native = std::make_unique<Native>();
    m_native->service = [[PillAudioService alloc] initWithFake:testBackend];
    [m_native->service startWithCallback:^(NSDictionary *snapshot) {
        // Swift delivers this block on the main thread. Copy typed fields out
        // here, then post a context-bound invocation so destruction removes any
        // delivery that has not run yet.
        QVariantMap state;
        state.insert("available", [snapshot[@"available"] boolValue]);
        state.insert("outputDeviceId", snapshotString(snapshot, @"outputDeviceId"));
        state.insert("volumeKnown", [snapshot[@"volumeKnown"] boolValue]);
        state.insert("volume", [snapshot[@"volume"] doubleValue]);
        state.insert("muteKnown", [snapshot[@"muteKnown"] boolValue]);
        state.insert("muted", [snapshot[@"muted"] boolValue]);
        state.insert("canSetVolume", [snapshot[@"canSetVolume"] boolValue]);
        state.insert("canMute", [snapshot[@"canMute"] boolValue]);
        state.insert("lastErrorCode", snapshotString(snapshot, @"lastErrorCode"));
        state.insert("lastError", snapshotString(snapshot, @"lastError"));
        state.insert("errorOperation", snapshotString(snapshot, @"errorOperation"));
        QMetaObject::invokeMethod(this, [this, state] { apply(state); }, Qt::QueuedConnection);
    }];
}

Audio::~Audio() {
    requireOwnerThread(this, "destruction");
    // Clears the native callback before releasing the block that holds `this`.
    [m_native->service stop];
}

void Audio::apply(const QVariantMap &snapshot) {
    m_available = snapshot.value("available").toBool();
    m_outputDeviceId = snapshot.value("outputDeviceId").toString();
    m_volumeKnown = snapshot.value("volumeKnown").toBool();
    m_volume = snapshot.value("volume").toReal();
    m_muteKnown = snapshot.value("muteKnown").toBool();
    m_muted = snapshot.value("muted").toBool();
    m_canSetVolume = snapshot.value("canSetVolume").toBool();
    m_canMute = snapshot.value("canMute").toBool();
    m_lastErrorCode = snapshot.value("lastErrorCode").toString();
    m_lastError = snapshot.value("lastError").toString();
    QPointer<Audio> guard(this);
    emit stateChanged();
    if (!guard) return; // A stateChanged slot deleted this object.
    const QString operation = snapshot.value("errorOperation").toString();
    if (!operation.isEmpty())
        emit errorOccurred(operation, m_lastErrorCode, m_lastError);
}

void Audio::setVolume(qreal value) {
    requireOwnerThread(this, "setVolume");
    [m_native->service setVolume:static_cast<double>(value) device:m_outputDeviceId.toUInt()];
}

void Audio::setMuted(bool value) {
    requireOwnerThread(this, "setMuted");
    [m_native->service setMuted:value device:m_outputDeviceId.toUInt()];
}

void registerAudioService(bool testBackend) {
    qmlRegisterSingletonType<Audio>("Pill.MacOS", 1, 0, "Audio",
        [testBackend](QQmlEngine *engine, QJSEngine *) -> QObject * {
            return new Audio(testBackend, engine);
        });
}
