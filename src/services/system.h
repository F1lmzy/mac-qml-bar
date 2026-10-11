#pragma once
#include <QObject>
#include <QVariantMap>
#include <memory>

class System final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool testBackend READ testBackend CONSTANT)
    Q_PROPERTY(QVariantMap brightness READ brightness NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap display READ display NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap battery READ battery NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap wifi READ wifi NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap bluetooth READ bluetooth NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap spotify READ spotify NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap desktop READ desktop NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap menus READ menus NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap weather READ weather NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap theme READ theme NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap outputDevices READ outputDevices NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap windowManager READ windowManager NOTIFY stateChanged)
public:
    explicit System(bool fake = false, QObject *parent = nullptr);
    ~System() override;
    bool testBackend() const { return m_fake; }
    QVariantMap brightness() const { return state("brightness"); }
    QVariantMap display() const { return state("display"); }
    QVariantMap battery() const { return state("battery"); }
    QVariantMap wifi() const { return state("wifi"); }
    QVariantMap bluetooth() const { return state("bluetooth"); }
    QVariantMap spotify() const { return state("spotify"); }
    QVariantMap desktop() const { return state("desktop"); }
    QVariantMap menus() const { return state("menus"); }
    QVariantMap weather() const { return state("weather"); }
    QVariantMap theme() const { return state("theme"); }
    QVariantMap outputDevices() const { return state("outputDevices"); }
    QVariantMap windowManager() const { return state("windowManager"); }
    void prepareForExit();
    Q_INVOKABLE void invoke(const QString &domain, const QString &action, const QVariant &argument = QVariant());
signals:
    void stateChanged();
    void focusTransferred();
    void errorOccurred(const QString &domain, const QString &operation, const QString &code, const QString &message);
private:
    QVariantMap state(const QString &domain) const { return m_states.value(domain).toMap(); }
    struct Native;
    std::unique_ptr<Native> m_native;
    QVariantMap m_states;
    bool m_fake;
    QString m_focusField;
    QString m_focusTarget;
};
void registerSystemService(bool fake = false);
