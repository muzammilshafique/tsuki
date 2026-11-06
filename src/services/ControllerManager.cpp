#include "ControllerManager.h"
#include <SDL2/SDL.h>
#include <linux/uinput.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <cstring>
#include <QUuid>
#include <QGuiApplication>
#include <QWindow>
#include <QKeyEvent>
#include <QFileInfo>

namespace Tsuki {

ControllerManager::ControllerManager(DatabaseManager* db, AppSettings* settings, QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
{
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    if (SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) == 0) {
        m_sdlInitialized = true;
    }

    auto defProf = m_db->getControllerProfile(m_settings->defaultControllerProfileId());
    if (defProf.has_value()) {
        m_activeProfile = *defProf;
    } else {
        m_activeProfile.id = QStringLiteral("default-xbox");
        m_activeProfile.name = QStringLiteral("Xbox 360 Standard (XInput)");
        m_activeProfile.xboxEmulation = true;
        m_activeProfile.deadzone = 4000;
        m_activeProfile.buttonMappings = ControllerProfileRecord::defaultXboxMappings();
    }

    QFileInfo uinputFi(QStringLiteral("/dev/uinput"));
    if (uinputFi.exists() && uinputFi.isWritable()) {
        m_uinputStatus = QStringLiteral("Ready (/dev/uinput writable)");
    } else if (uinputFi.exists()) {
        m_uinputStatus = QStringLiteral("/dev/uinput present (read-only; using SDL/XInput env injection)");
    } else {
        m_uinputStatus = QStringLiteral("uinput kernel module not loaded (using SDL/XInput env injection)");
    }

    refreshControllers();

    connect(&m_pollTimer, &QTimer::timeout, this, &ControllerManager::pollSdlEvents);
    m_pollTimer.start(16); // ~60Hz poll
}

ControllerManager::~ControllerManager() {
    stopXboxEmulation();
    if (m_primaryPad) {
        SDL_GameControllerClose(m_primaryPad);
        m_primaryPad = nullptr;
    } else if (m_primaryJoy) {
        SDL_JoystickClose(m_primaryJoy);
        m_primaryJoy = nullptr;
    }
    if (m_sdlInitialized) {
        SDL_QuitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER);
    }
}

QString ControllerManager::connectedDeviceName() const {
    if (m_detectedControllers.isEmpty()) return QStringLiteral("No Controller Connected");
    return m_detectedControllers.first().toMap().value(QStringLiteral("name")).toString();
}

QVariantList ControllerManager::profilesVariant() const {
    QVariantList list;
    for (const ControllerProfileRecord& p : m_db->getAllControllerProfiles()) {
        list.append(p.toVariantMap());
    }
    return list;
}

QVariantMap ControllerManager::getProfileMap(const QString& profileId) const {
    auto p = m_db->getControllerProfile(profileId.isEmpty() ? m_settings->defaultControllerProfileId() : profileId);
    return p.has_value() ? p->toVariantMap() : m_activeProfile.toVariantMap();
}

QString ControllerManager::createProfile(const QString& name, bool xboxEmulation, int deadzone) {
    ControllerProfileRecord rec;
    rec.id = QStringLiteral("ctrl-") + QUuid::createUuid().toString(QUuid::Id128).left(8);
    rec.name = name.trimmed().isEmpty() ? QStringLiteral("Custom Profile") : name.trimmed();
    rec.xboxEmulation = xboxEmulation;
    rec.deadzone = qBound(0, deadzone, 20000);
    rec.buttonMappings = ControllerProfileRecord::defaultXboxMappings();
    m_db->saveControllerProfile(rec);
    emit profilesChanged();
    return rec.id;
}

bool ControllerManager::saveProfile(const QString& profileId,
                                    const QString& name,
                                    bool xboxEmulation,
                                    int deadzone,
                                    const QVariantMap& mappings)
{
    ControllerProfileRecord rec;
    rec.id = profileId.isEmpty() ? QStringLiteral("default-xbox") : profileId;
    rec.name = name.trimmed().isEmpty() ? QStringLiteral("Xbox Profile") : name.trimmed();
    rec.xboxEmulation = xboxEmulation;
    rec.deadzone = qBound(0, deadzone, 20000);
    rec.buttonMappings = mappings.isEmpty() ? ControllerProfileRecord::defaultXboxMappings() : mappings;
    const bool ok = m_db->saveControllerProfile(rec);
    if (ok) {
        if (m_activeProfile.id == rec.id) {
            m_activeProfile = rec;
        }
        emit profilesChanged();
    }
    return ok;
}

bool ControllerManager::deleteProfile(const QString& profileId) {
    const bool ok = m_db->removeControllerProfile(profileId);
    if (ok) emit profilesChanged();
    return ok;
}

void ControllerManager::refreshControllers() {
    if (!m_sdlInitialized) return;
    SDL_JoystickUpdate();

    if (m_primaryPad) {
        SDL_GameControllerClose(m_primaryPad);
        m_primaryPad = nullptr;
    } else if (m_primaryJoy) {
        SDL_JoystickClose(m_primaryJoy);
        m_primaryJoy = nullptr;
    }
    m_primaryInstanceId = -1;
    m_detectedControllers.clear();

    const int count = SDL_NumJoysticks();
    for (int i = 0; i < count; ++i) {
        const char* rawName = SDL_JoystickNameForIndex(i);
        const QString name = rawName ? QString::fromUtf8(rawName) : QStringLiteral("Gamepad %1").arg(i);
        // Skip our own virtual uinput Xbox 360 device if active
        if (m_uinputFd >= 0 && name == QStringLiteral("Microsoft X-Box 360 pad")) {
            continue;
        }

        SDL_JoystickGUID guid = SDL_JoystickGetDeviceGUID(i);
        char guidBuf[64] = {0};
        SDL_JoystickGetGUIDString(guid, guidBuf, sizeof(guidBuf));

        const bool isGameCtrl = SDL_IsGameController(i) == SDL_TRUE;
        QVariantMap dev;
        dev["index"] = i;
        dev["name"] = name;
        dev["guid"] = QString::fromLatin1(guidBuf);
        dev["isStandardGamepad"] = isGameCtrl;
        dev["vendorId"] = QStringLiteral("0x%1").arg(SDL_JoystickGetDeviceVendor(i), 4, 16, QLatin1Char('0'));
        dev["productId"] = QStringLiteral("0x%1").arg(SDL_JoystickGetDeviceProduct(i), 4, 16, QLatin1Char('0'));
        m_detectedControllers.append(dev);

        if (!m_primaryPad && !m_primaryJoy) {
            if (isGameCtrl) {
                m_primaryPad = SDL_GameControllerOpen(i);
                if (m_primaryPad) {
                    SDL_Joystick* j = SDL_GameControllerGetJoystick(m_primaryPad);
                    if (j) m_primaryInstanceId = SDL_JoystickInstanceID(j);
                }
            } else {
                m_primaryJoy = SDL_JoystickOpen(i);
                if (m_primaryJoy) {
                    m_primaryInstanceId = SDL_JoystickInstanceID(m_primaryJoy);
                }
            }
        }
    }

    emit controllersChanged();
}

quint16 ControllerManager::linuxKeyCodeForName(const QString& name) {
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

bool ControllerManager::startXboxEmulation(const QString& profileId) {
    stopXboxEmulation();

    const QString targetId = profileId.isEmpty() ? m_settings->defaultControllerProfileId() : profileId;
    if (auto p = m_db->getControllerProfile(targetId); p.has_value()) {
        m_activeProfile = *p;
    } else {
        m_activeProfile.id = QStringLiteral("default-xbox");
        m_activeProfile.name = QStringLiteral("Xbox 360 Standard (XInput)");
        m_activeProfile.xboxEmulation = true;
        m_activeProfile.deadzone = 4000;
        m_activeProfile.buttonMappings = ControllerProfileRecord::defaultXboxMappings();
    }

    if (!m_activeProfile.xboxEmulation) {
        m_uinputStatus = QStringLiteral("Xbox Emulation disabled by profile");
        emit emulationStateChanged();
        return false;
    }

    const int fd = ::open("/dev/uinput", O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        m_uinputStatus = QStringLiteral("Active via SDL/XInput Env (uinput open failed)");
        emit emulationStateChanged();
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
    std::strncpy(usetup.name, "Microsoft X-Box 360 pad", UINPUT_MAX_NAME_SIZE - 1);

    if (::ioctl(fd, UI_DEV_SETUP, &usetup) < 0 || ::ioctl(fd, UI_DEV_CREATE) < 0) {
        ::close(fd);
        m_uinputStatus = QStringLiteral("Failed to create uinput device");
        emit emulationStateChanged();
        return false;
    }

    m_uinputFd = fd;
    m_uinputStatus = QStringLiteral("Virtual Microsoft X-Box 360 pad Active (%1)").arg(m_activeProfile.name);
    m_pollTimer.setInterval(8); // 120Hz low-latency polling during gameplay
    emit emulationStateChanged();
    return true;
}

void ControllerManager::stopXboxEmulation() {
    if (m_uinputFd >= 0) {
        ::ioctl(m_uinputFd, UI_DEV_DESTROY);
        ::close(m_uinputFd);
        m_uinputFd = -1;
        m_uinputStatus = QStringLiteral("Ready (/dev/uinput writable)");
        m_pollTimer.setInterval(16);
        emit emulationStateChanged();
    }
}

void ControllerManager::emitUinputEvent(quint16 type, quint16 code, qint32 value) {
    if (m_uinputFd < 0) return;
    struct input_event ev {};
    ev.type = type;
    ev.code = code;
    ev.value = value;
    [[maybe_unused]] const ssize_t written = ::write(m_uinputFd, &ev, sizeof(ev));
}

qint16 ControllerManager::applyDeadzone(qint16 val, int deadzone) {
    if (qAbs(static_cast<int>(val)) < deadzone) return 0;
    return val;
}

void ControllerManager::pollSdlEvents() {
    if (!m_sdlInitialized) return;

    SDL_Event ev;
    bool deviceListChanged = false;
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_JOYDEVICEADDED || ev.type == SDL_JOYDEVICEREMOVED) {
            deviceListChanged = true;
        } else if (ev.type == SDL_CONTROLLERBUTTONDOWN && m_uinputFd < 0) {
            // Translate gamepad buttons to Qt key navigation when launcher UI is active
            int qtKey = 0;
            switch (ev.cbutton.button) {
                case SDL_CONTROLLER_BUTTON_DPAD_UP: qtKey = Qt::Key_Up; break;
                case SDL_CONTROLLER_BUTTON_DPAD_DOWN: qtKey = Qt::Key_Down; break;
                case SDL_CONTROLLER_BUTTON_DPAD_LEFT: qtKey = Qt::Key_Left; break;
                case SDL_CONTROLLER_BUTTON_DPAD_RIGHT: qtKey = Qt::Key_Right; break;
                case SDL_CONTROLLER_BUTTON_A: qtKey = Qt::Key_Return; break;
                case SDL_CONTROLLER_BUTTON_B: qtKey = Qt::Key_Escape; break;
                case SDL_CONTROLLER_BUTTON_START: qtKey = Qt::Key_Menu; break;
                case SDL_CONTROLLER_BUTTON_LEFTSHOULDER: qtKey = Qt::Key_PageUp; break;
                case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER: qtKey = Qt::Key_PageDown; break;
                default: break;
            }
            if (qtKey != 0) {
                emit uiKeySimulated(qtKey);
                if (QWindow* win = QGuiApplication::focusWindow()) {
                    QKeyEvent pressEv(QEvent::KeyPress, qtKey, Qt::NoModifier);
                    QKeyEvent relEv(QEvent::KeyRelease, qtKey, Qt::NoModifier);
                    QGuiApplication::sendEvent(win, &pressEv);
                    QGuiApplication::sendEvent(win, &relEv);
                }
            }
        }
    }

    if (deviceListChanged) {
        refreshControllers();
    }

    if (m_primaryPad) {
        syncVirtualXboxPad();
    }
}

void ControllerManager::syncVirtualXboxPad() {
    if (!m_primaryPad) return;

    const int dz = m_activeProfile.deadzone;
    const QVariantMap& map = m_activeProfile.buttonMappings;

    const bool a = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_A) != 0;
    const bool b = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_B) != 0;
    const bool x = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_X) != 0;
    const bool y = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_Y) != 0;
    const bool lb = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_LEFTSHOULDER) != 0;
    const bool rb = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER) != 0;
    const bool back = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_BACK) != 0;
    const bool start = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_START) != 0;
    const bool guide = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_GUIDE) != 0;
    const bool ls = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_LEFTSTICK) != 0;
    const bool rs = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_RIGHTSTICK) != 0;
    const bool dup = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_UP) != 0;
    const bool ddown = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_DOWN) != 0;
    const bool dleft = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_LEFT) != 0;
    const bool dright = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_RIGHT) != 0;

    const qint16 lx = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_LEFTX), dz);
    const qint16 ly = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_LEFTY), dz);
    const qint16 rx = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_RIGHTX), dz);
    const qint16 ry = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_RIGHTY), dz);
    const qint16 lt = SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_TRIGGERLEFT);
    const qint16 rt = SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_TRIGGERRIGHT);

    m_liveInputState["a"] = a;
    m_liveInputState["b"] = b;
    m_liveInputState["x"] = x;
    m_liveInputState["y"] = y;
    m_liveInputState["lb"] = lb;
    m_liveInputState["rb"] = rb;
    m_liveInputState["back"] = back;
    m_liveInputState["start"] = start;
    m_liveInputState["lx"] = lx;
    m_liveInputState["ly"] = ly;
    m_liveInputState["rx"] = rx;
    m_liveInputState["ry"] = ry;
    m_liveInputState["lt"] = lt;
    m_liveInputState["rt"] = rt;
    emit liveInputChanged();

    if (m_uinputFd >= 0) {
        // Resolve mappings (with backward compatibility fix for legacy swapped X/Y profiles)
        QString xMap = map.value(QStringLiteral("x"), QStringLiteral("BTN_NORTH")).toString();
        QString yMap = map.value(QStringLiteral("y"), QStringLiteral("BTN_WEST")).toString();
        if (xMap == QStringLiteral("BTN_WEST") && yMap == QStringLiteral("BTN_NORTH")) {
            xMap = QStringLiteral("BTN_NORTH");
            yMap = QStringLiteral("BTN_WEST");
        }

        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("a"), QStringLiteral("BTN_SOUTH")).toString()), a ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("b"), QStringLiteral("BTN_EAST")).toString()), b ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(xMap), x ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(yMap), y ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("lb"), QStringLiteral("BTN_TL")).toString()), lb ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("rb"), QStringLiteral("BTN_TR")).toString()), rb ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("back"), QStringLiteral("BTN_SELECT")).toString()), back ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("start"), QStringLiteral("BTN_START")).toString()), start ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("guide"), QStringLiteral("BTN_MODE")).toString()), guide ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("lstick"), QStringLiteral("BTN_THUMBL")).toString()), ls ? 1 : 0);
        emitUinputEvent(EV_KEY, linuxKeyCodeForName(map.value(QStringLiteral("rstick"), QStringLiteral("BTN_THUMBR")).toString()), rs ? 1 : 0);

        emitUinputEvent(EV_ABS, ABS_X, lx);
        emitUinputEvent(EV_ABS, ABS_Y, ly);
        emitUinputEvent(EV_ABS, ABS_RX, rx);
        emitUinputEvent(EV_ABS, ABS_RY, ry);
        emitUinputEvent(EV_ABS, ABS_Z, qBound(0, static_cast<int>(lt) / 128, 255));
        emitUinputEvent(EV_ABS, ABS_RZ, qBound(0, static_cast<int>(rt) / 128, 255));
        emitUinputEvent(EV_ABS, ABS_HAT0X, (dright ? 1 : 0) - (dleft ? 1 : 0));
        emitUinputEvent(EV_ABS, ABS_HAT0Y, (ddown ? 1 : 0) - (dup ? 1 : 0));
        emitUinputEvent(EV_SYN, SYN_REPORT, 0);
    }
}

QString ControllerManager::buildSdlGameControllerConfig(const QString& profileId) const {
    if (m_detectedControllers.isEmpty()) return QString();
    const QVariantMap first = m_detectedControllers.first().toMap();
    const QString guid = first.value(QStringLiteral("guid")).toString();
    const QString name = first.value(QStringLiteral("name")).toString();
    if (guid.isEmpty()) return QString();

    auto profOpt = m_db->getControllerProfile(profileId.isEmpty() ? m_settings->defaultControllerProfileId() : profileId);
    const QVariantMap map = profOpt.has_value() ? profOpt->buttonMappings : ControllerProfileRecord::defaultXboxMappings();

    auto btnCode = [&map](const QString& key, const QString& defBtn) -> QString {
        QString target = map.value(key, defBtn).toString();
        // Backward compatibility fix for legacy swapped X/Y profiles
        if (key == QStringLiteral("x") && target == QStringLiteral("BTN_WEST") &&
            map.value(QStringLiteral("y")).toString() == QStringLiteral("BTN_NORTH")) {
            target = QStringLiteral("BTN_NORTH");
        } else if (key == QStringLiteral("y") && target == QStringLiteral("BTN_NORTH") &&
                   map.value(QStringLiteral("x")).toString() == QStringLiteral("BTN_WEST")) {
            target = QStringLiteral("BTN_WEST");
        }

        if (target == QStringLiteral("BTN_SOUTH") || target == QStringLiteral("BTN_A")) return QStringLiteral("b0");
        if (target == QStringLiteral("BTN_EAST") || target == QStringLiteral("BTN_B")) return QStringLiteral("b1");
        if (target == QStringLiteral("BTN_NORTH") || target == QStringLiteral("BTN_X")) return QStringLiteral("b2");
        if (target == QStringLiteral("BTN_WEST") || target == QStringLiteral("BTN_Y")) return QStringLiteral("b3");
        if (target == QStringLiteral("BTN_TL")) return QStringLiteral("b4");
        if (target == QStringLiteral("BTN_TR")) return QStringLiteral("b5");
        if (target == QStringLiteral("BTN_SELECT") || target == QStringLiteral("BTN_BACK")) return QStringLiteral("b6");
        if (target == QStringLiteral("BTN_START")) return QStringLiteral("b7");
        if (target == QStringLiteral("BTN_MODE") || target == QStringLiteral("BTN_GUIDE")) return QStringLiteral("b8");
        if (target == QStringLiteral("BTN_THUMBL")) return QStringLiteral("b9");
        if (target == QStringLiteral("BTN_THUMBR")) return QStringLiteral("b10");
        return QStringLiteral("b0");
    };

    return QStringLiteral("%1,%2,platform:Linux,a:%3,b:%4,x:%5,y:%6,back:%7,guide:%8,start:%9,leftstick:%10,rightstick:%11,leftshoulder:%12,rightshoulder:%13,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5,")
        .arg(guid,
             name,
             btnCode(QStringLiteral("a"), QStringLiteral("BTN_SOUTH")),
             btnCode(QStringLiteral("b"), QStringLiteral("BTN_EAST")),
             btnCode(QStringLiteral("x"), QStringLiteral("BTN_NORTH")),
             btnCode(QStringLiteral("y"), QStringLiteral("BTN_WEST")),
             btnCode(QStringLiteral("back"), QStringLiteral("BTN_SELECT")),
             btnCode(QStringLiteral("guide"), QStringLiteral("BTN_MODE")),
             btnCode(QStringLiteral("start"), QStringLiteral("BTN_START")),
             btnCode(QStringLiteral("lstick"), QStringLiteral("BTN_THUMBL")),
             btnCode(QStringLiteral("rstick"), QStringLiteral("BTN_THUMBR")),
             btnCode(QStringLiteral("lb"), QStringLiteral("BTN_TL")),
             btnCode(QStringLiteral("rb"), QStringLiteral("BTN_TR")));
}

} // namespace Tsuki

