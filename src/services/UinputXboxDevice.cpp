#include "UinputXboxDevice.h"
#include <linux/uinput.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <cstring>
#include <QFileInfo>

namespace Tsuki {

UinputXboxDevice::UinputXboxDevice()
    : m_status(probeSystemStatus())
{
}

UinputXboxDevice::~UinputXboxDevice() {
    stop();
}

QString UinputXboxDevice::probeSystemStatus() {
    QFileInfo uinputFi(QStringLiteral("/dev/uinput"));
    if (uinputFi.exists() && uinputFi.isWritable()) {
        return QStringLiteral("Ready (/dev/uinput writable)");
    } else if (uinputFi.exists()) {
        return QStringLiteral("/dev/uinput present (read-only; using SDL/XInput env injection)");
    } else {
        return QStringLiteral("uinput kernel module not loaded (using SDL/XInput env injection)");
    }
}

quint16 UinputXboxDevice::linuxKeyCodeForName(const QString& name) {
    if (name == QStringLiteral("BTN_SOUTH") || name == QStringLiteral("BTN_A")) return BTN_SOUTH;
    if (name == QStringLiteral("BTN_EAST") || name == QStringLiteral("BTN_B")) return BTN_EAST;
    if (name == QStringLiteral("BTN_NORTH") || name == QStringLiteral("BTN_X")) return BTN_NORTH;
    if (name == QStringLiteral("BTN_WEST") || name == QStringLiteral("BTN_Y")) return BTN_WEST;
    if (name == QStringLiteral("BTN_TL")) return BTN_TL;
    if (name == QStringLiteral("BTN_TR")) return BTN_TR;
    if (name == QStringLiteral("BTN_SELECT") || name == QStringLiteral("BTN_BACK")) return BTN_SELECT;
    if (name == QStringLiteral("BTN_START")) return BTN_START;
    if (name == QStringLiteral("BTN_MODE") || name == QStringLiteral("BTN_GUIDE")) return BTN_MODE;
    if (name == QStringLiteral("BTN_THUMBL")) return BTN_THUMBL;
    if (name == QStringLiteral("BTN_THUMBR")) return BTN_THUMBR;
    return BTN_SOUTH;
}

bool UinputXboxDevice::start(const QString& profileName) {
    stop();

    const int fd = ::open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        m_status = QStringLiteral("Active via SDL/XInput Env (uinput open failed)");
        return false;
    }

    ::ioctl(fd, UI_SET_EVBIT, EV_KEY);
    ::ioctl(fd, UI_SET_EVBIT, EV_ABS);
    ::ioctl(fd, UI_SET_EVBIT, EV_SYN);

    const quint16 buttons[] = {
        BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST,
        BTN_TL, BTN_TR, BTN_SELECT, BTN_START, BTN_MODE,
        BTN_THUMBL, BTN_THUMBR
    };
    for (quint16 b : buttons) {
        ::ioctl(fd, UI_SET_KEYBIT, b);
    }

    auto setupAbs = [fd](quint16 code, qint32 minVal, qint32 maxVal, qint32 flat, qint32 fuzz) {
        ::ioctl(fd, UI_SET_ABSBIT, code);
        struct uinput_abs_setup absSetup {};
        absSetup.code = code;
        absSetup.absinfo.minimum = minVal;
        absSetup.absinfo.maximum = maxVal;
        absSetup.absinfo.flat = flat;
        absSetup.absinfo.fuzz = fuzz;
        ::ioctl(fd, UI_ABS_SETUP, &absSetup);
    };

    setupAbs(ABS_X, -32768, 32767, 128, 16);
    setupAbs(ABS_Y, -32768, 32767, 128, 16);
    setupAbs(ABS_RX, -32768, 32767, 128, 16);
    setupAbs(ABS_RY, -32768, 32767, 128, 16);
    setupAbs(ABS_Z, 0, 255, 0, 0);
    setupAbs(ABS_RZ, 0, 255, 0, 0);
    setupAbs(ABS_HAT0X, -1, 1, 0, 0);
    setupAbs(ABS_HAT0Y, -1, 1, 0, 0);

    struct uinput_setup usetup {};
    usetup.id.bustype = BUS_USB;
    usetup.id.vendor = 0x045e;  // Microsoft
    usetup.id.product = 0x028e; // Xbox 360 Controller
    usetup.id.version = 0x0110;
    std::strncpy(usetup.name, kVirtualDeviceName, UINPUT_MAX_NAME_SIZE - 1);

    if (::ioctl(fd, UI_DEV_SETUP, &usetup) < 0 || ::ioctl(fd, UI_DEV_CREATE) < 0) {
        ::close(fd);
        m_status = QStringLiteral("Failed to create uinput device");
        return false;
    }

    m_fd = fd;
    m_status = QStringLiteral("Virtual Microsoft X-Box 360 pad Active (%1)").arg(profileName);
    return true;
}

void UinputXboxDevice::stop() {
    if (m_fd >= 0) {
        ::ioctl(m_fd, UI_DEV_DESTROY);
        ::close(m_fd);
        m_fd = -1;
        m_status = QStringLiteral("Ready (/dev/uinput writable)");
    }
}

void UinputXboxDevice::emitEvent(quint16 type, quint16 code, qint32 value) {
    if (m_fd < 0) return;
    struct input_event ev {};
    ev.type = type;
    ev.code = code;
    ev.value = value;
    [[maybe_unused]] const ssize_t written = ::write(m_fd, &ev, sizeof(ev));
}

void UinputXboxDevice::syncState(const XboxPadState& state, const QVariantMap& buttonMappings) {
    if (m_fd < 0) return;

    // Resolve mappings (with backward compatibility fix for legacy swapped X/Y profiles)
    QString xMap = buttonMappings.value(QStringLiteral("x"), QStringLiteral("BTN_NORTH")).toString();
    QString yMap = buttonMappings.value(QStringLiteral("y"), QStringLiteral("BTN_WEST")).toString();
    if (xMap == QStringLiteral("BTN_WEST") && yMap == QStringLiteral("BTN_NORTH")) {
        xMap = QStringLiteral("BTN_NORTH");
        yMap = QStringLiteral("BTN_WEST");
    }

    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("a"), QStringLiteral("BTN_SOUTH")).toString()), state.a ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("b"), QStringLiteral("BTN_EAST")).toString()), state.b ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(xMap), state.x ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(yMap), state.y ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("lb"), QStringLiteral("BTN_TL")).toString()), state.lb ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("rb"), QStringLiteral("BTN_TR")).toString()), state.rb ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("back"), QStringLiteral("BTN_SELECT")).toString()), state.back ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("start"), QStringLiteral("BTN_START")).toString()), state.start ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("guide"), QStringLiteral("BTN_MODE")).toString()), state.guide ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("lstick"), QStringLiteral("BTN_THUMBL")).toString()), state.lstick ? 1 : 0);
    emitEvent(EV_KEY, linuxKeyCodeForName(buttonMappings.value(QStringLiteral("rstick"), QStringLiteral("BTN_THUMBR")).toString()), state.rstick ? 1 : 0);

    emitEvent(EV_ABS, ABS_X, state.lx);
    emitEvent(EV_ABS, ABS_Y, state.ly);
    emitEvent(EV_ABS, ABS_RX, state.rx);
    emitEvent(EV_ABS, ABS_RY, state.ry);
    emitEvent(EV_ABS, ABS_Z, qBound(0, static_cast<int>(state.lt) / 128, 255));
    emitEvent(EV_ABS, ABS_RZ, qBound(0, static_cast<int>(state.rt) / 128, 255));
    emitEvent(EV_ABS, ABS_HAT0X, (state.dpadRight ? 1 : 0) - (state.dpadLeft ? 1 : 0));
    emitEvent(EV_ABS, ABS_HAT0Y, (state.dpadDown ? 1 : 0) - (state.dpadUp ? 1 : 0));
    emitEvent(EV_SYN, SYN_REPORT, 0);
}

} // namespace Tsuki
