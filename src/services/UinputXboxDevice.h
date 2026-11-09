#pragma once

#include <QString>
#include <QVariantMap>
#include <QtGlobal>

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

class UinputXboxDevice {
public:
    static constexpr const char* kVirtualDeviceName = "Microsoft X-Box 360 pad";

    UinputXboxDevice();
    ~UinputXboxDevice();

    Q_DISABLE_COPY_MOVE(UinputXboxDevice)

    bool isActive() const { return m_fd >= 0; }
    QString status() const { return m_status; }
    void setStatus(const QString& status) { m_status = status; }

    bool start(const QString& profileName);
    void stop();
    void syncState(const XboxPadState& state, const QVariantMap& buttonMappings);

    static QString probeSystemStatus();
    static quint16 linuxKeyCodeForName(const QString& name);

private:
    void emitEvent(quint16 type, quint16 code, qint32 value);

    int m_fd = -1;
    QString m_status;
};

} // namespace Tsuki
