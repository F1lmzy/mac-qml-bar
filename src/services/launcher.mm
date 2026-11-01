#import <Foundation/Foundation.h>
#include "launcher.h"
#include <maccer_agent.h>

#include <QCoreApplication>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>
#include <QVariantMap>
#include <QQmlEngine>
#include <QClipboard>
#include <qqml.h>
#include <QQuickImageProvider>
#include <QImage>
#include <QCache>
#include <QMutex>
#include <QMutexLocker>
#include <QRegularExpression>
#include <cmath>

// The image-loading thread reads only copied pixels, never the Rust handle.
// Cache lifetime is shared with the engine's image provider, not the service.
class LauncherIconStore final {
public:
    QImage image(const QString &token) {
        QMutexLocker lock(&mutex);
        const QImage *image = images.object(token);
        return image ? *image : QImage();
    }
    void insert(const QString &token, const QImage &image) {
        QMutexLocker lock(&mutex);
        images.insert(token, new QImage(image));
    }
private:
    QMutex mutex;
    QCache<QString, QImage> images{512};
};

namespace {
class LauncherImageProvider final : public QQuickImageProvider {
public:
    explicit LauncherImageProvider(std::shared_ptr<LauncherIconStore> store)
        : QQuickImageProvider(QQuickImageProvider::Image), m_store(std::move(store)) {}
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override {
        const QImage image = m_store->image(id);
        if (size) *size = image.size();
        return requestedSize.isValid() && !image.isNull()
            ? image.scaled(requestedSize, Qt::KeepAspectRatio, Qt::SmoothTransformation) : image;
    }
private:
    std::shared_ptr<LauncherIconStore> m_store;
};
}

namespace {
constexpr int kPollIntervalMs = 16;
constexpr int kMaxEventsPerPoll = 128;
constexpr qsizetype kMaxQueryBytes = 4096;

void requireOwnerThread(const QObject *object, const char *operation) {
    if (![NSThread isMainThread] || object->thread() != QThread::currentThread())
        qFatal("Maccer %s must run on the macOS main / Qt owner thread", operation);
}

QString eventError(const QJsonValue &value) {
    if (value.isString()) return value.toString();
    if (value.isObject()) {
        const QJsonObject object = value.toObject();
        const QString message = object.value("message").toString();
        return message.isEmpty() ? QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact)) : message;
    }
    return {};
}

// Only service-mode result snapshots carry a route. Embedded events leave the
// provider scope untouched so the picker keeps its original behaviour.
// Validate only the rendering contract. Resolution and last-good ownership stay
// in Maccer; this guard prevents malformed colors from reaching QML bindings.
bool validSharedPalette(const QJsonObject &palette) {
    const auto identity = [&](const char *key) {
        const QJsonValue value = palette.value(QLatin1String(key));
        return value.isString() && !value.toString().isEmpty() && value.toString().toUtf8().size() <= 256;
    };
    if (palette.value("schema").toDouble(-1) != 1 || !identity("name") || !identity("slug")) return false;
    const QString variant = palette.value("variant").toString();
    if (variant != QStringLiteral("dark") && variant != QStringLiteral("light")) return false;
    const QJsonValue alphaValue = palette.value("alpha_byte");
    const double alpha = alphaValue.toDouble(-1);
    if (!alphaValue.isDouble() || !std::isfinite(alpha) || alpha < 0 || alpha > 255 || std::floor(alpha) != alpha) return false;
    static const QRegularExpression color(QStringLiteral("^#[0-9a-fA-F]{6}$"));
    const auto group = [&](const char *name, const QStringList &keys) {
        const QJsonObject values = palette.value(QLatin1String(name)).toObject();
        for (const QString &key : keys) {
            const QJsonValue value = values.value(key);
            if (!value.isString() || !color.match(value.toString()).hasMatch()) return false;
        }
        return true;
    };
    QStringList ansi{"background", "foreground", "cursor", "accent", "selection_background", "selection_foreground"};
    for (int i = 0; i < 16; ++i) ansi.append(QStringLiteral("color%1").arg(i));
    return group("palette", ansi) && group("tokens", {"surface", "surface_container_low", "surface_container", "surface_container_high", "surface_container_highest", "on_surface", "on_surface_variant", "outline", "outline_variant", "primary", "on_primary", "primary_container", "on_primary_container", "secondary", "info", "success", "warning", "error", "muted"}) &&
        group("border", {"active", "inactive"}) && group("bar", {"background", "background_solid", "item_bg", "accent", "label", "icon", "muted", "red", "green", "yellow"});
}

QVariantMap readOnlyThemeState() {
    return {{"available", false}, {"canNext", false}, {"canSelect", false}, {"canResyncWallpaper", false},
            {"canNextBackground", false}, {"canSetBackground", false}, {"busy", false}, {"catalogLoading", false},
            {"themes", QVariantList{}}, {"wallpapers", QVariantList{}},
            {"catalogError", QStringLiteral("Theme catalogs and changes are not available in shared-service mode yet.")}};
}

bool routeIsProviderScoped(const QJsonValue &route) {
    return route.isObject()
        && route.toObject().value("type").toString() == QStringLiteral("provider");
}
}

LauncherService::LauncherService(bool testBackend, QObject *parent)
    : QObject(parent ? parent : QCoreApplication::instance()), m_testBackend(testBackend) {
    requireOwnerThread(this, "construction");
    m_iconStore = std::make_shared<LauncherIconStore>();
    m_themeState = readOnlyThemeState();
    if (auto *engine = qobject_cast<QQmlEngine *>(parent))
        engine->addImageProvider(QStringLiteral("maccer-icons"), new LauncherImageProvider(m_iconStore));
    // Service mode is opt-in through the environment and never applies to the
    // hermetic test backend. A failed connection is reported and never silently
    // falls back to the embedded providers.
    const QByteArray socketPath = testBackend ? QByteArray() : qgetenv("MACCER_SERVICE_SOCKET");
    if (!socketPath.isEmpty()) {
        m_serviceMode = true;
        // The shared service owns the global shortcut, so claim the "pill"
        // presentation lease on the adapter's dedicated control connection.
        // Search, cancellation and actions stay independent of presentation.
        m_agent = maccer_agent_connect_frontend(socketPath.constData(), "pill");
        if (!m_agent)
            m_lastError = QStringLiteral("Could not connect to the maccer service.");
    } else {
        m_agent = maccer_agent_create(testBackend);
        if (!m_agent)
            m_lastError = QStringLiteral("Could not create the maccer provider service.");
    }
    if (m_agent) {
        connect(&m_pollTimer, &QTimer::timeout, this, &LauncherService::poll);
        m_pollTimer.setInterval(kPollIntervalMs);
        m_pollTimer.start();
    }
}

LauncherService::~LauncherService() {
    requireOwnerThread(this, "destruction");
    m_pollTimer.stop();
    if (m_agent) {
        maccer_agent_destroy(m_agent);
        m_agent = nullptr;
    }
}

void LauncherService::cacheNativeIcon(const QString &source) {
    const QString prefix = QStringLiteral("image://maccer-icons/");
    if (!m_agent || !source.startsWith(prefix)) return;
    const QString token = source.mid(prefix.size());
    if (!m_iconStore->image(token).isNull()) return;
    const QByteArray bytes = token.toUtf8();
    const std::unique_ptr<MaccerIconPixels, decltype(&maccer_agent_icon_free)>
        pixels(maccer_agent_icon(m_agent, bytes.constData()), maccer_agent_icon_free);
    if (!pixels || !pixels->bgra || !pixels->width || !pixels->height ||
        pixels->width > 64 || pixels->height > 64 ||
        pixels->len != size_t(pixels->width) * pixels->height * 4) return;
    // macOS targets are little-endian: ARGB32's memory layout is straight BGRA.
    // Copy before freeing the Rust allocation. No PNG decode or native lookup.
    const QImage image(pixels->bgra, int(pixels->width), int(pixels->height),
                       int(pixels->width * 4), QImage::Format_ARGB32);
    m_iconStore->insert(token, image.copy());
}

void LauncherService::setError(const QString &message) {
    m_previewLoading = false;
    m_lastError = message;
    m_searching = false;
    m_busy = false;
    emit stateChanged();
}

bool LauncherService::sendSearch(quint64 request) {
    if (!m_agent || !m_ready) return false;
    const QJsonObject message{{"op", "search"}, {"request", static_cast<qint64>(request)}, {"query", m_query}};
    const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
    if (char *error = maccer_agent_send(m_agent, bytes.constData())) {
        const QString text = QString::fromUtf8(error);
        maccer_agent_string_free(error);
        setError(text);
        return false;
    }
    m_searching = true;
    m_busy = false;
    m_lastError.clear();
    m_outputTitle.clear();
    m_outputText.clear();
    emit stateChanged();
    return true;
}

void LauncherService::resetDetails() {
    m_detailProvider.clear();
    m_detailId.clear();
    m_previewContent.clear();
    m_previewLoading = false;
}

void LauncherService::clearConfirmation() {
    if (m_pendingConfirmation.isEmpty()) return;
    m_pendingConfirmation.clear();
    emit stateChanged();
}

// Returns the descriptor's plain-text confirmation prompt for the displayed
// action, or an empty string when the action needs no explicit consent. Only
// actions already present in the current service snapshot are considered.
QString LauncherService::confirmationFor(const QString &provider, const QString &id, const QString &action) const {
    for (const QVariant &entry : m_results) {
        const QVariantMap item = entry.toMap();
        if (item.value("provider").toString() != provider || item.value("id").toString() != id) continue;
        for (const QVariant &candidate : item.value("actions").toList()) {
            const QVariantMap descriptor = candidate.toMap();
            if (descriptor.value("id").toString() == action)
                return descriptor.value("confirmation").toString();
        }
    }
    return {};
}

void LauncherService::clearDetails() {
    requireOwnerThread(this, "clearDetails");
    if (m_detailProvider.isEmpty() && m_previewContent.isEmpty() && !m_previewLoading) return;
    resetDetails();
    emit stateChanged();
}

void LauncherService::requestDetails(const QString &provider, const QString &id) {
    requireOwnerThread(this, "requestDetails");
    if (!m_serviceMode || !m_hasDetails || !m_agent || !m_ready || !m_active || m_busy || m_searching || !m_resultRequest) return;
    if (provider == m_detailProvider && id == m_detailId) return;
    bool available = false;
    for (const QVariant &entry : m_results) {
        const QVariantMap item = entry.toMap();
        if (item.value("provider").toString() == provider && item.value("id").toString() == id && item.value("detailsAvailable").toBool()) available = true;
    }
    resetDetails();
    if (!available) { emit stateChanged(); return; }
    m_detailProvider = provider;
    m_detailId = id;
    ++m_detailRequest;
    m_previewLoading = true;
    const QJsonObject message{{"op", "details"}, {"request", static_cast<qint64>(m_detailRequest)},
        {"search_request", static_cast<qint64>(m_resultRequest)}, {"provider", provider}, {"id", id}};
    const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
    if (char *error = maccer_agent_send(m_agent, bytes.constData())) {
        m_previewLoading = false;
        m_lastError = QString::fromUtf8(error);
        maccer_agent_string_free(error);
    }
    emit stateChanged();
}

void LauncherService::setQuery(const QString &query) {
    requireOwnerThread(this, "setQuery");
    if (query.contains(QChar::Null)) {
        cancel();
        setError(QStringLiteral("Search text cannot contain a NUL character."));
        return;
    }
    if (query.toUtf8().size() > kMaxQueryBytes) {
        cancel();
        setError(QStringLiteral("Search text exceeds the 4096-byte limit."));
        return;
    }
    ++m_request;
    m_query = query;
    if (m_serviceMode) {
        // Retain display-only rows, cached icons and preview until replacement.
        // Revoke their action/detail identity even if the new search fails.
        m_resultRequest = 0;
        m_detailProvider.clear();
        m_detailId.clear();
    } else {
        resetDetails();
        m_results.clear();
    }
    m_pendingConfirmation.clear();
    m_pendingIcons.clear();
    m_lastError.clear();
    m_outputTitle.clear();
    m_outputText.clear();
    m_active = true;
    m_busy = false;
    m_searching = m_ready;
    emit stateChanged();
    if (m_ready) sendSearch(m_request);
}

void LauncherService::activate(const QString &provider, const QString &id, const QString &action) {
    requireOwnerThread(this, "activate");
    if (!m_agent || !m_ready || m_busy || m_searching || (m_serviceMode && !m_resultRequest)) return;
    bool allowed = false;
    QString confirmation;
    for (const QVariant &entry : m_results) {
        const QVariantMap item = entry.toMap();
        if (item.value("provider").toString() != provider || item.value("id").toString() != id) continue;
        for (const QVariant &candidate : item.value("actions").toList()) {
            const QVariantMap descriptor = candidate.toMap();
            if (descriptor.value("id").toString() != action) continue;
            allowed = true;
            confirmation = descriptor.value("confirmation").toString();
        }
    }
    if (!allowed) {
        setError(QStringLiteral("That launcher action is no longer available."));
        return;
    }
    if (!confirmation.isEmpty()) {
        // Stage the descriptor's prompt. Nothing is sent until the user
        // explicitly confirms; a later query/navigation/snapshot change or
        // Escape discards this consent request.
        m_pendingConfirmation = {{"provider", provider}, {"id", id}, {"action", action}, {"prompt", confirmation}, {"searchRequest", QVariant::fromValue(m_resultRequest)}};
        emit stateChanged();
        return;
    }
    dispatchActivation(provider, id, action, false);
}

void LauncherService::confirmActivation() {
    requireOwnerThread(this, "confirmActivation");
    if (m_pendingConfirmation.isEmpty()) return;
    const QString provider = m_pendingConfirmation.value("provider").toString();
    const QString id = m_pendingConfirmation.value("id").toString();
    const QString action = m_pendingConfirmation.value("action").toString();
    const QString prompt = m_pendingConfirmation.value("prompt").toString();
    const quint64 searchRequest = m_pendingConfirmation.value("searchRequest").toULongLong();
    m_pendingConfirmation.clear();
    // Revalidate against the current snapshot; the displayed result or its
    // confirmation requirement may have changed while the prompt was staged.
    if (!m_agent || !m_ready || m_busy || m_searching) {
        emit stateChanged();
        return;
    }
    if (searchRequest != m_resultRequest || prompt.isEmpty() || confirmationFor(provider, id, action) != prompt) {
        setError(QStringLiteral("That launcher action is no longer available."));
        return;
    }
    dispatchActivation(provider, id, action, true);
}

void LauncherService::cancelActivation() {
    requireOwnerThread(this, "cancelActivation");
    clearConfirmation();
}

void LauncherService::dispatchActivation(const QString &provider, const QString &id, const QString &action, bool confirmed) {
    ++m_request;
    resetDetails();
    m_busy = true;
    m_searching = false;
    m_lastError.clear();
    emit stateChanged();
    const QJsonObject message{{"op", "activate"}, {"request", static_cast<qint64>(m_request)},
                              {"search_request", static_cast<qint64>(m_resultRequest)},
                              {"provider", provider}, {"id", id}, {"action", action},
                              {"confirmed", confirmed}};
    const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
    if (char *error = maccer_agent_send(m_agent, bytes.constData())) {
        const QString text = QString::fromUtf8(error);
        maccer_agent_string_free(error);
        setError(text);
    }
}

void LauncherService::home() {
    requireOwnerThread(this, "home");
    // The embedded backend has no routes; the picker keeps its query convention.
    if (!m_serviceMode || !m_agent || !m_ready) return;
    ++m_request;
    resetDetails();
    m_pendingConfirmation.clear();
    m_results.clear();
    m_pendingIcons.clear();
    m_lastError.clear();
    m_outputTitle.clear();
    m_outputText.clear();
    m_providerScoped = false;
    m_active = true;
    m_busy = true;
    m_searching = false;
    emit stateChanged();
    const QJsonObject message{{"op", "home"}, {"request", static_cast<qint64>(m_request)}};
    const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
    if (char *error = maccer_agent_send(m_agent, bytes.constData())) {
        const QString text = QString::fromUtf8(error);
        maccer_agent_string_free(error);
        setError(text);
    }
}

void LauncherService::cancel() {
    requireOwnerThread(this, "cancel");
    ++m_request;
    resetDetails();
    m_pendingConfirmation.clear();
    m_active = false;
    if (m_agent && m_ready) {
        const QJsonObject message{{"op", "cancel"}};
        const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
        if (char *error = maccer_agent_send(m_agent, bytes.constData())) {
            maccer_agent_string_free(error);
        }
    }
    m_results.clear();
    m_pendingIcons.clear();
    m_searching = false;
    m_busy = false;
    m_providerScoped = false;
    m_lastError.clear();
    m_outputTitle.clear();
    m_outputText.clear();
    emit stateChanged();
}

void LauncherService::copyOutput() {
    requireOwnerThread(this, "copyOutput");
    if (!m_outputText.isEmpty() && QGuiApplication::clipboard())
        QGuiApplication::clipboard()->setText(m_outputText);
}

void LauncherService::poll() {
    requireOwnerThread(this, "poll");
    if (!m_agent) return;
    for (int i = 0; i < kMaxEventsPerPoll; ++i) {
        char *event = maccer_agent_poll(m_agent);
        if (!event) break;
        const QByteArray json(event);
        maccer_agent_string_free(event);
        applyEvent(json);
    }
}

void LauncherService::applyEvent(const QByteArray &json) {
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(json, &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        setError(QStringLiteral("maccer returned an invalid event."));
        return;
    }
    const QJsonObject event = document.object();
    const QString type = event.value("type").toString();
    if (type == QStringLiteral("themeState")) {
        if (!m_serviceMode || !event.value("state").isObject()) return;
        const QJsonObject state = event.value("state").toObject();
        const QJsonValue revision = state.value("revision");
        if (!revision.isString() || revision.toString().isEmpty() || revision.toString().size() > 128 || !state.value("available").isBool()) return;
        const bool available = state.value("available").toBool();
        const QJsonObject palette = state.value("palette").toObject();
        if (available != !palette.isEmpty() || (available && !validSharedPalette(palette))) return;
        const QJsonValue error = state.value("error");
        if (!error.isUndefined() && !error.isNull() && (!error.isObject() || !error.toObject().value("message").isString() || !error.toObject().value("code").isString())) return;
        QVariantMap next = readOnlyThemeState();
        next.insert("revision", revision.toString());
        next.insert("available", available);
        if (available) {
            next.insert("palette", palette.toVariantMap());
            for (const char *key : {"slug", "name", "variant"}) next.insert(QLatin1String(key), palette.value(QLatin1String(key)).toString());
        }
        next.insert("lastError", error.toObject().value("message").toString().left(512));
        next.insert("lastErrorCode", error.toObject().value("code").toString().left(64));
        if (next != m_themeState) {
            m_themeState = next;
            emit themeStateChanged();
        }
        return;
    }
    if (type == QStringLiteral("ready")) {
        const QString shortcutError = event.value("shortcutError").toString();
        if (m_ready) {
            // Initialization and hotkey registration can publish separate ready
            // events; retain the later, actionable registration failure.
            if (!shortcutError.isEmpty() && shortcutError != m_shortcutError) {
                m_shortcutError = shortcutError;
                emit stateChanged();
            }
            return;
        }
        m_ready = true;
        m_hasDetails = event.value("itemDetails").toBool();
        m_shortcutError = shortcutError;
        emit stateChanged();
        if (m_active) sendSearch(m_request);
        return;
    }
    if (type == QStringLiteral("toggle")) {
        emit toggleRequested();
        return;
    }
    if (type == QStringLiteral("present")) {
        // Presentation is backend-owned and independent of the search request
        // watermark. Only the service control connection emits it; an embedded
        // backend never does, so ignore injected events there.
        if (!m_serviceMode) return;
        emit showRequested();
        return;
    }
    if (type == QStringLiteral("presentationError")) {
        if (!m_serviceMode) return;
        const QString message = event.value("message").toString();
        if (!message.isEmpty() && message != m_shortcutError) {
            m_shortcutError = message;
            emit stateChanged();
        }
        return;
    }

    const QJsonValue requestValue = event.value("request");
    if (!requestValue.isUndefined() && requestValue.toVariant().toULongLong() != m_request) return;

    if (type == QStringLiteral("assetExpired")) {
        if (!m_serviceMode || !m_active || m_busy || m_searching || !m_agent || requestValue.toVariant().toULongLong() != m_resultRequest) return;
        const quint64 oldRequest = m_resultRequest;
        ++m_request;
        resetDetails();
        m_pendingConfirmation.clear();
        m_results.clear();
        m_pendingIcons.clear();
        m_searching = true;
        const QJsonObject message{{"op", "refresh"}, {"request", static_cast<qint64>(m_request)}, {"search_request", static_cast<qint64>(oldRequest)}};
        const QByteArray bytes = QJsonDocument(message).toJson(QJsonDocument::Compact);
        if (char *error = maccer_agent_send(m_agent, bytes.constData())) {
            const QString text = QString::fromUtf8(error);
            maccer_agent_string_free(error);
            setError(text);
        }
        emit stateChanged();
        return;
    }
    if (type == QStringLiteral("details")) {
        if (!m_active || m_busy || m_searching || event.value("detailRequest").toVariant().toULongLong() != m_detailRequest ||
            event.value("provider").toString() != m_detailProvider || event.value("id").toString() != m_detailId || m_detailId.isEmpty()) return;
        QVariantList content;
        const QJsonArray blocks = event.value("content").toArray();
        for (int i = 0; i < blocks.size() && i < 32; ++i) {
            if (!blocks[i].isObject()) continue;
            QVariantMap block = blocks[i].toObject().toVariantMap();
            const QString source = block.value("source").toString();
            if (source.startsWith(QStringLiteral("image://maccer-icons/"))) cacheNativeIcon(source);
            else block.remove("source");
            content.append(block);
        }
        m_previewContent = content;
        m_previewLoading = false;
        emit stateChanged();
        return;
    }
    if (type == QStringLiteral("results")) {
        resetDetails();
        m_pendingConfirmation.clear();
        if (event.contains("route")) m_providerScoped = routeIsProviderScoped(event.value("route"));
        QVariantList next;
        for (const QJsonValue &value : event.value("items").toArray()) {
            if (value.isObject()) next.append(value.toObject().toVariantMap());
        }
        for (QVariant &entry : next) {
            QVariantMap item = entry.toMap();
            const QString key = item.value("provider").toString() + QChar::Null + item.value("id").toString();
            const auto icon = m_pendingIcons.find(key);
            if (item.value("iconSource").toString().isEmpty() && icon != m_pendingIcons.end())
                item.insert("iconSource", icon.value());
            cacheNativeIcon(item.value("iconSource").toString());
            entry = item;
        }
        m_results = next;
        m_resultRequest = requestValue.toVariant().toULongLong();
        QStringList errors;
        const QJsonValue errorsValue = event.value("errors");
        if (errorsValue.isArray()) {
            for (const QJsonValue &error : errorsValue.toArray()) {
                const QString text = eventError(error);
                if (!text.isEmpty()) errors.append(text);
            }
        } else if (!errorsValue.isUndefined()) {
            const QString text = eventError(errorsValue);
            if (!text.isEmpty()) errors.append(text);
        }
        m_lastError = errors.join(QLatin1Char('\n'));
        m_searching = !event.value("complete").toBool(true);
        m_busy = false;
        emit stateChanged();
        return;
    }
    if (type == QStringLiteral("icon")) {
        const QString provider = event.value("provider").toString();
        const QString id = event.value("id").toString();
        const QString source = event.value("source").toString();
        cacheNativeIcon(source);
        if (m_pendingIcons.size() < 256)
            m_pendingIcons.insert(provider + QChar::Null + id, source);
        for (int i = 0; i < m_results.size(); ++i) {
            QVariantMap item = m_results[i].toMap();
            if (item.value("provider").toString() == provider && item.value("id").toString() == id) {
                item.insert("iconSource", source);
                m_results[i] = item;
                emit stateChanged();
                return;
            }
        }
        return;
    }
    if (type == QStringLiteral("error")) {
        setError(event.value("message").toString());
        return;
    }
    if (type == QStringLiteral("outcome")) {
        m_busy = false;
        const QString kind = event.value("kind").toString();
        if (kind == QStringLiteral("close")) {
            if (event.value("focusTransferred").toBool()) emit focusTransferred();
            emit stateChanged();
            emit closeRequested();
        } else if (kind == QStringLiteral("keepOpen")) {
            m_lastError = event.value("text").toString();
            emit stateChanged();
        } else if (kind == QStringLiteral("setQuery")) {
            const QString next = event.value("text").toString();
            if (event.contains("route")) m_providerScoped = routeIsProviderScoped(event.value("route"));
            emit stateChanged();
            emit queryRequested(next);
        } else if (kind == QStringLiteral("refresh")) {
            const QString query = m_query;
            setQuery(query);
        } else if (kind == QStringLiteral("output")) {
            m_outputTitle = event.value("title").toString();
            m_outputText = event.value("text").toString();
            emit stateChanged();
        } else {
            m_lastError = QStringLiteral("maccer returned an unsupported action outcome.");
            emit stateChanged();
        }
    }
}

void registerLauncherService(bool testBackend) {
    qmlRegisterSingletonType<LauncherService>("Pill.MacOS", 1, 0, "Maccer",
        [testBackend](QQmlEngine *engine, QJSEngine *) -> QObject * {
            return new LauncherService(testBackend, engine);
        });
}
