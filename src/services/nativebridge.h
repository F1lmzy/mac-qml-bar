#pragma once
#include <QObject>
#include <memory>

// Main-thread-owned bridge health, not simulated system state.
class NativeBridge final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
public:
    explicit NativeBridge(QObject *parent = nullptr);
    ~NativeBridge() override;
    bool ready() const { return m_ready; }
signals:
    void readyChanged();
private:
    struct Native;
    std::unique_ptr<Native> m_native;
    bool m_ready = false;
};

void registerNativeServices();
