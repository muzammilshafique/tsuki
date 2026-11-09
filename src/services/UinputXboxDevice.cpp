#include "UinputXboxDevice.h"
#include <linux/uinput.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <cstring>
#include <cerrno>
#include <QFileInfo>
#include <QVarLengthArray>
#include <QDebug>

namespace Tsuki {

namespace {

class DefaultUinputBackend : public IUinputBackend {
public:
    int openDevice(const char* path, int flags) override {
        return ::open(path, flags);
    }
    int ioctlCall(int fd, unsigned long request, void* arg) override {
        return ::ioctl(fd, request, arg);
    }
    ssize_t writeBytes(int fd, const void* buf, size_t count) override {
        return ::write(fd, buf, count);
    }
    int closeDevice(int fd) override {
        return ::close(fd);
    }
    QString probeStatus() override {
        QFileInfo uinputFi(QStringLiteral("/dev/uinput"));
        if (!uinputFi.exists()) {
            uinputFi.setFile(QStringLiteral("/dev/input/uinput"));
        }
        if (uinputFi.exists()) {
            if (uinputFi.isWritable()) {
                return QStringLiteral("Ready (/dev/uinput writable)");
            } else {
                return QStringLiteral("Cannot emulate: /dev/uinput is read-only (permission denied)");
            }
        }
        return QStringLiteral("Cannot emulate: /dev/uinput device node not found");
    }
};

} // namespace

UinputXboxDevice::UinputXboxDevice(std::unique_ptr<IUinputBackend> backend)
    : m_backend(backend ? std::move(backend) : std::make_unique<DefaultUinputBackend>())
    , m_status(m_backend->probeStatus())
{
}

UinputXboxDevice::~UinputXboxDevice() {
    stop();
}

QString UinputXboxDevice::probeSystemStatus() {
    return DefaultUinputBackend().probeStatus();
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
    return 0; // Return 0 (KEY_RESERVED) for unknown or invalid button names
}

bool UinputXboxDevice::isValidButtonName(const QString& name) {
    return linuxKeyCodeForName(name) != 0;
}

QVariantMap UinputXboxDevice::defaultXboxMappings() {
    QVariantMap m;
    m["a"] = QStringLiteral("BTN_SOUTH");
    m["b"] = QStringLiteral("BTN_EAST");
    m["x"] = QStringLiteral("BTN_NORTH");
    m["y"] = QStringLiteral("BTN_WEST");
    m["lb"] = QStringLiteral("BTN_TL");
    m["rb"] = QStringLiteral("BTN_TR");
    m["back"] = QStringLiteral("BTN_SELECT");
    m["start"] = QStringLiteral("BTN_START");
    m["guide"] = QStringLiteral("BTN_MODE");
    m["lstick"] = QStringLiteral("BTN_THUMBL");
    m["rstick"] = QStringLiteral("BTN_THUMBR");
    m["dpad_up"] = QStringLiteral("DPAD_UP");
    m["dpad_down"] = QStringLiteral("DPAD_DOWN");
    m["dpad_left"] = QStringLiteral("DPAD_LEFT");
    m["dpad_right"] = QStringLiteral("DPAD_RIGHT");
    m["left_x"] = QStringLiteral("ABS_X");
    m["left_y"] = QStringLiteral("ABS_Y");
    m["right_x"] = QStringLiteral("ABS_RX");
    m["right_y"] = QStringLiteral("ABS_RY");
    m["lt"] = QStringLiteral("ABS_Z");
    m["rt"] = QStringLiteral("ABS_RZ");
    return m;
}

bool UinputXboxDevice::start(const QString& deviceLabel) {
    stop();

    int fd = m_backend->openDevice("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) {
        fd = m_backend->openDevice("/dev/input/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
    }
    if (fd < 0) {
        m_status = QStringLiteral("Failed to open /dev/uinput: %1").arg(QString::fromLocal8Bit(std::strerror(errno)));
        return false;
    }

    auto failCleanup = [this, fd](const QString& errReason) {
        m_backend->closeDevice(fd);
        m_fd = -1;
        m_status = errReason;
        return false;
    };

    if (m_backend->ioctlCall(fd, UI_SET_EVBIT, reinterpret_cast<void*>(static_cast<uintptr_t>(EV_KEY))) < 0) {
        return failCleanup(QStringLiteral("Failed UI_SET_EVBIT EV_KEY: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
    }
    if (m_backend->ioctlCall(fd, UI_SET_EVBIT, reinterpret_cast<void*>(static_cast<uintptr_t>(EV_ABS))) < 0) {
        return failCleanup(QStringLiteral("Failed UI_SET_EVBIT EV_ABS: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
    }
    if (m_backend->ioctlCall(fd, UI_SET_EVBIT, reinterpret_cast<void*>(static_cast<uintptr_t>(EV_SYN))) < 0) {
        return failCleanup(QStringLiteral("Failed UI_SET_EVBIT EV_SYN: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
    }

    const quint16 buttons[] = {
        BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST,
        BTN_TL, BTN_TR, BTN_SELECT, BTN_START, BTN_MODE,
        BTN_THUMBL, BTN_THUMBR
    };
    for (quint16 b : buttons) {
        if (m_backend->ioctlCall(fd, UI_SET_KEYBIT, reinterpret_cast<void*>(static_cast<uintptr_t>(b))) < 0) {
            return failCleanup(QStringLiteral("Failed UI_SET_KEYBIT %1: %2").arg(b).arg(QString::fromLocal8Bit(std::strerror(errno))));
        }
    }

    auto setupAbs = [this, fd](quint16 code, qint32 minVal, qint32 maxVal, qint32 flat, qint32 fuzz) -> bool {
        if (m_backend->ioctlCall(fd, UI_SET_ABSBIT, reinterpret_cast<void*>(static_cast<uintptr_t>(code))) < 0) {
            return false;
        }
        struct uinput_abs_setup absSetup {};
        absSetup.code = code;
        absSetup.absinfo.minimum = minVal;
        absSetup.absinfo.maximum = maxVal;
        absSetup.absinfo.flat = flat;
        absSetup.absinfo.fuzz = fuzz;
        return m_backend->ioctlCall(fd, UI_ABS_SETUP, &absSetup) >= 0;
    };

    if (!setupAbs(ABS_X, -32768, 32767, 128, 16) ||
        !setupAbs(ABS_Y, -32768, 32767, 128, 16) ||
        !setupAbs(ABS_RX, -32768, 32767, 128, 16) ||
        !setupAbs(ABS_RY, -32768, 32767, 128, 16) ||
        !setupAbs(ABS_Z, 0, 255, 0, 0) ||
        !setupAbs(ABS_RZ, 0, 255, 0, 0) ||
        !setupAbs(ABS_HAT0X, -1, 1, 0, 0) ||
        !setupAbs(ABS_HAT0Y, -1, 1, 0, 0)) {
        return failCleanup(QStringLiteral("Failed UI_ABS_SETUP: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
    }

    struct uinput_setup usetup {};
    usetup.id.bustype = BUS_USB;
    usetup.id.vendor = 0x045e;  // Microsoft
    usetup.id.product = 0x028e; // Xbox 360 Controller
    usetup.id.version = 0x0110;
    std::strncpy(usetup.name, kVirtualDeviceName, UINPUT_MAX_NAME_SIZE - 1);

    if (m_backend->ioctlCall(fd, UI_DEV_SETUP, &usetup) < 0) {
        return failCleanup(QStringLiteral("Failed UI_DEV_SETUP: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
    }
    if (m_backend->ioctlCall(fd, UI_DEV_CREATE, nullptr) < 0) {
        return failCleanup(QStringLiteral("Failed UI_DEV_CREATE: %1").arg(QString::fromLocal8Bit(std::strerror(errno))));
    }

    m_fd = fd;
    m_hasLastState = false;
    m_lastButtons.clear();
    m_lastAxes.clear();
    m_status = QStringLiteral("Virtual Microsoft X-Box 360 pad Active (%1)").arg(deviceLabel);

    // Initial neutral event emission so the pad starts with all controls released and centered
    resetToNeutral({});
    return true;
}

void UinputXboxDevice::stop() {
    if (m_fd >= 0) {
        m_backend->ioctlCall(m_fd, UI_DEV_DESTROY, nullptr);
        m_backend->closeDevice(m_fd);
        m_fd = -1;
        m_hasLastState = false;
        m_lastButtons.clear();
        m_lastAxes.clear();
    }
    m_status = m_backend->probeStatus();
}

bool UinputXboxDevice::writeBatch(const struct input_event* events, size_t count) {
    if (m_fd < 0 || count == 0) return false;

    const char* ptr = reinterpret_cast<const char*>(events);
    size_t remaining = count * sizeof(struct input_event);

    while (remaining > 0) {
        ssize_t written = m_backend->writeBytes(m_fd, ptr, remaining);
        if (written < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                // Non-blocking buffer full; abort this cycle to avoid blocking
                break;
            }
            m_status = QStringLiteral("uinput write error: %1").arg(QString::fromLocal8Bit(std::strerror(errno)));
            return false;
        }
        if (written == 0) {
            break;
        }
        ptr += written;
        remaining -= static_cast<size_t>(written);
    }
    return remaining == 0;
}

void UinputXboxDevice::resetToNeutral(const QVariantMap& buttonMappings) {
    XboxPadState neutral{};
    syncState(neutral, buttonMappings);
}

void UinputXboxDevice::syncState(const XboxPadState& state, const QVariantMap& buttonMappings) {
    if (m_fd < 0) return;

    // Resolve mappings (with backward compatibility fix for legacy swapped X/Y inputs)
    QString xMap = buttonMappings.value(QStringLiteral("x"), QStringLiteral("BTN_NORTH")).toString();
    QString yMap = buttonMappings.value(QStringLiteral("y"), QStringLiteral("BTN_WEST")).toString();
    if (xMap == QStringLiteral("BTN_WEST") && yMap == QStringLiteral("BTN_NORTH")) {
        xMap = QStringLiteral("BTN_NORTH");
        yMap = QStringLiteral("BTN_WEST");
    }

    // Standard Xbox buttons to aggregate
    const quint16 allButtons[] = {
        BTN_SOUTH, BTN_EAST, BTN_NORTH, BTN_WEST,
        BTN_TL, BTN_TR, BTN_SELECT, BTN_START, BTN_MODE,
        BTN_THUMBL, BTN_THUMBR
    };

    // A virtual button is pressed if ANY physical input mapped to it is pressed.
    // This fixes duplicate output mapping releases: releasing one physical button
    // does not release a virtual button that is still held by another mapped input.
    QMap<quint16, bool> virtualButtons;
    for (quint16 b : allButtons) {
        virtualButtons[b] = false;
    }

    auto applyBtnMapping = [&virtualButtons](const QString& targetName, bool physicalPressed) {
        quint16 code = linuxKeyCodeForName(targetName);
        if (code != 0 && physicalPressed) {
            virtualButtons[code] = true;
        }
    };

    applyBtnMapping(buttonMappings.value(QStringLiteral("a"), QStringLiteral("BTN_SOUTH")).toString(), state.a);
    applyBtnMapping(buttonMappings.value(QStringLiteral("b"), QStringLiteral("BTN_EAST")).toString(), state.b);
    applyBtnMapping(xMap, state.x);
    applyBtnMapping(yMap, state.y);
    applyBtnMapping(buttonMappings.value(QStringLiteral("lb"), QStringLiteral("BTN_TL")).toString(), state.lb);
    applyBtnMapping(buttonMappings.value(QStringLiteral("rb"), QStringLiteral("BTN_TR")).toString(), state.rb);
    applyBtnMapping(buttonMappings.value(QStringLiteral("back"), QStringLiteral("BTN_SELECT")).toString(), state.back);
    applyBtnMapping(buttonMappings.value(QStringLiteral("start"), QStringLiteral("BTN_START")).toString(), state.start);
    applyBtnMapping(buttonMappings.value(QStringLiteral("guide"), QStringLiteral("BTN_MODE")).toString(), state.guide);
    applyBtnMapping(buttonMappings.value(QStringLiteral("lstick"), QStringLiteral("BTN_THUMBL")).toString(), state.lstick);
    applyBtnMapping(buttonMappings.value(QStringLiteral("rstick"), QStringLiteral("BTN_THUMBR")).toString(), state.rstick);

    // Compute axes
    qint32 ltVal = qBound(0, static_cast<int>(state.lt) / 128, 255);
    qint32 rtVal = qBound(0, static_cast<int>(state.rt) / 128, 255);
    qint32 hatX = (state.dpadRight ? 1 : 0) - (state.dpadLeft ? 1 : 0);
    qint32 hatY = (state.dpadDown ? 1 : 0) - (state.dpadUp ? 1 : 0);

    // Batch only changed events
    QVarLengthArray<struct input_event, 32> events;
    QMap<quint16, bool> stagedButtons = m_lastButtons;
    QMap<quint16, qint32> stagedAxes = m_lastAxes;

    for (quint16 b : allButtons) {
        bool pressed = virtualButtons.value(b, false);
        if (!m_hasLastState || m_lastButtons.value(b, false) != pressed) {
            struct input_event ev {};
            ev.type = EV_KEY;
            ev.code = b;
            ev.value = pressed ? 1 : 0;
            events.append(ev);
            stagedButtons[b] = pressed;
        }
    }

    auto checkAxis = [this, &events, &stagedAxes](quint16 code, qint32 val) {
        if (!m_hasLastState || m_lastAxes.value(code, 0) != val) {
            struct input_event ev {};
            ev.type = EV_ABS;
            ev.code = code;
            ev.value = val;
            events.append(ev);
            stagedAxes[code] = val;
        }
    };

    checkAxis(ABS_X, state.lx);
    checkAxis(ABS_Y, state.ly);
    checkAxis(ABS_RX, state.rx);
    checkAxis(ABS_RY, state.ry);
    checkAxis(ABS_Z, ltVal);
    checkAxis(ABS_RZ, rtVal);
    checkAxis(ABS_HAT0X, hatX);
    checkAxis(ABS_HAT0Y, hatY);

    if (!events.isEmpty()) {
        struct input_event syn {};
        syn.type = EV_SYN;
        syn.code = SYN_REPORT;
        syn.value = 0;
        events.append(syn);

        if (writeBatch(events.constData(), events.size())) {
            m_lastButtons = stagedButtons;
            m_lastAxes = stagedAxes;
            m_hasLastState = true;
        }
    }
}

} // namespace Tsuki
