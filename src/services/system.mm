#import <Foundation/Foundation.h>
#import "PillNative-Swift.h"
#include "system.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJSValue>
#include <QPointer>
#include <QQmlEngine>
#include <QThread>
#include <qqml.h>

struct System::Native { PillSystemService *service = nil; };
static void ownerThread(const QObject *object) {
    if (![NSThread isMainThread] || object->thread() != QThread::currentThread())
        qFatal("System services require the main / Qt owner thread");
}
System::System(bool fake, QObject *parent) : QObject(parent ? parent : QCoreApplication::instance()), m_fake(fake) {
    ownerThread(this); m_native = std::make_unique<Native>();
    m_native->service = [[PillSystemService alloc] initWithFake:fake];
    [m_native->service startWithCallback:^(NSString *domain, NSDictionary *snapshot) {
        ownerThread(this);
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:&error];
        QVariantMap state;
        if (data) state = QJsonDocument::fromJson(QByteArray((const char *)data.bytes, data.length)).toVariant().toMap();
        else state = {{"available", false}, {"lastErrorCode", "invalidResponse"}, {"lastError", "Invalid native snapshot"}};
        const QString key = QString::fromNSString(domain);
        QMetaObject::invokeMethod(this, [this, key, state] {
            m_states.insert(key, state);
            QPointer<System> alive(this);
            emit stateChanged();
            if (!alive) return;
            if (key == "windowManager" && !m_focusTarget.isEmpty()) {
                if (!state.value("lastErrorCode").toString().isEmpty()) { m_focusTarget.clear(); m_focusField.clear(); }
                else if (state.value("available").toBool() && state.value(m_focusField).toString() == m_focusTarget) {
                    m_focusTarget.clear(); m_focusField.clear(); emit focusTransferred();
                    if (!alive) return;
                }
            }
            if (alive && !state.value("errorOperation").toString().isEmpty())
                emit errorOccurred(key, state.value("errorOperation").toString(), state.value("lastErrorCode").toString(), state.value("lastError").toString());
        }, Qt::QueuedConnection);
    }];
}
System::~System() { ownerThread(this); [m_native->service stop]; }
void System::prepareForExit() { ownerThread(this); [m_native->service prepareForExit]; }
void System::invoke(const QString &domain, const QString &action, const QVariant &argument) {
    ownerThread(this);
    // Wrap scalars in an array so JSON handles booleans/null/numbers faithfully.
    const QVariant plain = argument.metaType() == QMetaType::fromType<QJSValue>()
        ? argument.value<QJSValue>().toVariant() : argument;
    const QByteArray json = QJsonDocument(QJsonArray{QJsonValue::fromVariant(plain)}).toJson(QJsonDocument::Compact);
    if (domain == "windowManager" && (action == "switchWorkspace" || action == "focusWindow")) {
        m_focusField = action == "switchWorkspace" ? "focusedWorkspace" : "focusedWindow";
        m_focusTarget = windowManager().value(m_focusField).toString() != plain.toString() ? plain.toString() : QString();
    }
    NSData *data = [NSData dataWithBytes:json.constData() length:json.size()];
    NSArray *array = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    [m_native->service invokeWithDomain:domain.toNSString() action:action.toNSString() argument:array.firstObject ?: [NSNull null]];
}
void registerSystemService(bool fake) {
    qmlRegisterSingletonType<System>("Pill.MacOS", 1, 0, "System", [fake](QQmlEngine *engine, QJSEngine *) -> QObject * { return new System(fake, engine); });
}
