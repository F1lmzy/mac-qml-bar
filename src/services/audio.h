#pragma once
#include <QObject>
#include <QtNumeric>
#include <memory>

// Main-thread-owned view of the default output device. All state is observed:
// setVolume/setMuted never update these properties optimistically, and unknown
// values stay flagged instead of being replaced with plausible numbers.
class Audio final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(QString outputDeviceId READ outputDeviceId NOTIFY stateChanged)
    Q_PROPERTY(bool volumeKnown READ volumeKnown NOTIFY stateChanged)
    Q_PROPERTY(qreal volume READ volume NOTIFY stateChanged)
    Q_PROPERTY(bool muteKnown READ muteKnown NOTIFY stateChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY stateChanged)
    Q_PROPERTY(bool canSetVolume READ canSetVolume NOTIFY stateChanged)
    Q_PROPERTY(bool canMute READ canMute NOTIFY stateChanged)
    Q_PROPERTY(QString lastErrorCode READ lastErrorCode NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(bool testBackend READ testBackend CONSTANT)
public:
    explicit Audio(bool testBackend = false, QObject *parent = nullptr);
    ~Audio() override;

    bool available() const { return m_available; }
    QString outputDeviceId() const { return m_outputDeviceId; }
    bool volumeKnown() const { return m_volumeKnown; }
    qreal volume() const { return m_volume; }
    bool muteKnown() const { return m_muteKnown; }
    bool muted() const { return m_muted; }
    bool canSetVolume() const { return m_canSetVolume; }
    bool canMute() const { return m_canMute; }
    QString lastErrorCode() const { return m_lastErrorCode; }
    QString lastError() const { return m_lastError; }
    bool testBackend() const { return m_testBackend; }

    Q_INVOKABLE void setVolume(qreal value);
    Q_INVOKABLE void setMuted(bool value);

signals:
    void stateChanged();
    void errorOccurred(const QString &operation, const QString &code, const QString &message);

private:
    void apply(const QVariantMap &snapshot);

    struct Native;
    std::unique_ptr<Native> m_native;
    const bool m_testBackend;
    bool m_available = false;
    QString m_outputDeviceId;
    bool m_volumeKnown = false;
    qreal m_volume = qQNaN();
    bool m_muteKnown = false;
    bool m_muted = false;
    bool m_canSetVolume = false;
    bool m_canMute = false;
    QString m_lastErrorCode;
    QString m_lastError;
};

void registerAudioService(bool testBackend = false);
