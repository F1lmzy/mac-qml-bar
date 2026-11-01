#pragma once

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QTimer>
#include <QByteArray>
#include <QHash>
#include <memory>

struct MaccerAgent;
class LauncherIconStore;

class LauncherService final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool testBackend READ testBackend CONSTANT)
    Q_PROPERTY(bool serviceMode READ serviceMode CONSTANT)
    Q_PROPERTY(bool providerScoped READ providerScoped NOTIFY stateChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY stateChanged)
    Q_PROPERTY(QVariantList results READ results NOTIFY stateChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY stateChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(QString query READ query NOTIFY stateChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY stateChanged)
    Q_PROPERTY(QString shortcutError READ shortcutError NOTIFY stateChanged)
    Q_PROPERTY(QString outputTitle READ outputTitle NOTIFY stateChanged)
    Q_PROPERTY(QString outputText READ outputText NOTIFY stateChanged)
    Q_PROPERTY(QVariantList previewContent READ previewContent NOTIFY stateChanged)
    Q_PROPERTY(bool previewLoading READ previewLoading NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap pendingConfirmation READ pendingConfirmation NOTIFY stateChanged)
    Q_PROPERTY(QVariantMap themeState READ themeState NOTIFY themeStateChanged)
public:
    explicit LauncherService(bool testBackend = false, QObject *parent = nullptr);
    ~LauncherService() override;

    bool testBackend() const { return m_testBackend; }
    bool serviceMode() const { return m_serviceMode; }
    bool providerScoped() const { return m_providerScoped; }
    bool ready() const { return m_ready; }
    QVariantList results() const { return m_results; }
    bool searching() const { return m_searching; }
    bool busy() const { return m_busy; }
    QString query() const { return m_query; }
    QString lastError() const { return m_lastError; }
    QString shortcutError() const { return m_shortcutError; }
    QString outputTitle() const { return m_outputTitle; }
    QString outputText() const { return m_outputText; }
    QVariantList previewContent() const { return m_previewContent; }
    bool previewLoading() const { return m_previewLoading; }
    // Non-empty only while a service action whose descriptor carries a
    // confirmation prompt is staged and still awaiting explicit consent.
    QVariantMap pendingConfirmation() const { return m_pendingConfirmation; }
    QVariantMap themeState() const { return m_themeState; }

    Q_INVOKABLE void setQuery(const QString &query);
    Q_INVOKABLE void activate(const QString &provider, const QString &id, const QString &action);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE void home();
    Q_INVOKABLE void copyOutput();
    Q_INVOKABLE void requestDetails(const QString &provider, const QString &id);
    Q_INVOKABLE void clearDetails();
    Q_INVOKABLE void confirmActivation();
    Q_INVOKABLE void cancelActivation();

signals:
    void stateChanged();
    void themeStateChanged();
    void closeRequested();
    void queryRequested(const QString &query);
    void focusTransferred();
    void toggleRequested();
    // Service-owned shortcut requested presentation. Emitted only in service
    // mode; the frontend opens (never toggles closed) on this signal.
    void showRequested();

private slots:
    void poll();

private:
    friend class LauncherServiceTest;
    bool sendSearch(quint64 request);
    QString confirmationFor(const QString &provider, const QString &id, const QString &action) const;
    void dispatchActivation(const QString &provider, const QString &id, const QString &action, bool confirmed);
    void clearConfirmation();
    void resetDetails();
    void applyEvent(const QByteArray &json);
    void setError(const QString &message);
    void cacheNativeIcon(const QString &source);
    std::shared_ptr<LauncherIconStore> m_iconStore;
    MaccerAgent *m_agent = nullptr;
    bool m_active = false;
    QTimer m_pollTimer;
    const bool m_testBackend;
    bool m_serviceMode = false;
    bool m_providerScoped = false;
    bool m_ready = false;
    bool m_searching = false;
    bool m_busy = false;
    quint64 m_request = 0;
    quint64 m_resultRequest = 0;
    QString m_query;
    QString m_lastError;
    QString m_shortcutError;
    QString m_outputTitle;
    QString m_outputText;
    QVariantList m_results;
    QHash<QString, QString> m_pendingIcons;
    bool m_hasDetails = false;
    bool m_previewLoading = false;
    quint64 m_detailRequest = 0;
    QString m_detailProvider;
    QString m_detailId;
    QVariantList m_previewContent;
    QVariantMap m_pendingConfirmation;
    QVariantMap m_themeState;
};

void registerLauncherService(bool testBackend = false);
