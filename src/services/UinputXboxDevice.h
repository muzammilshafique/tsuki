#pragma once

#include <QString>
#include <QVariantMap>
#include <QMap>
#include <QtGlobal>
#include <memory>

struct input_event;

namespace Tsuki {

struct XboxPadState {
    bool a = false;
    bool b = false;
    bool x = false;
    bool y = false;
    bool lb = false;
    bool rb = false;
    bool back = false;
    bool start = false;
    bool guide = false;
    bool lstick = false;
    bool rstick = false;
    bool dpadUp = false;
    bool dpadDown = false;
    bool dpadLeft = false;
    bool dpadRight = false;

    qint16 lx = 0;
    qint16 ly = 0;
    qint16 rx = 0;
    qint16 ry = 0;
    qint16 lt = 0;
    qint16 rt = 0;
};

class IUinputBackend {
public:
    virtual ~IUinputBackend() = default;
    virtual int openDevice(const char* path, int flags) = 0;
    virtual int ioctlCall(int fd, unsigned long request, void* arg) = 0;
    virtual ssize_t writeBytes(int fd, const void* buf, size_t count) = 0;
    virtual int closeDevice(int fd) = 0;
    virtual QString probeStatus() = 0;
};

class UinputXboxDevice {
public:
    static constexpr const char* kVirtualDeviceName = "Microsoft X-Box 360 pad";

    explicit UinputXboxDevice(std::unique_ptr<IUinputBackend> backend = nullptr);
    ~UinputXboxDevice();

    Q_DISABLE_COPY_MOVE(UinputXboxDevice)

    bool isActive() const { return m_fd >= 0; }
    QString status() const { return m_status; }
    void setStatus(const QString& status) { m_status = status; }

    bool start(const QString& deviceLabel = QStringLiteral("Xbox 360 Standard (XInput)"));
    void stop();
    void syncState(const XboxPadState& state, const QVariantMap& buttonMappings = {});
    void resetToNeutral(const QVariantMap& buttonMappings = {});

    static QString probeSystemStatus();
    static quint16 linuxKeyCodeForName(const QString& name);
    static bool isValidButtonName(const QString& name);
    static QVariantMap defaultXboxMappings();

    IUinputBackend* backend() const { return m_backend.get(); }

private:
    bool writeBatch(const struct input_event* events, size_t count);

    std::unique_ptr<IUinputBackend> m_backend;
    int m_fd = -1;
    QString m_status;

    bool m_hasLastState = false;
    QMap<quint16, bool> m_lastButtons;
    QMap<quint16, qint32> m_lastAxes;
};

} // namespace Tsuki
