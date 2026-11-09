#include "ControllerManager.h"
#include <SDL2/SDL.h>
#include <QUuid>
#include <QGuiApplication>
#include <QWindow>
#include <QKeyEvent>
#include <QDebug>

namespace Tsuki {

ControllerManager::ControllerManager(DatabaseManager* db,
                                     AppSettings* settings,
                                     std::unique_ptr<IUinputBackend> backend,
                                     QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_virtualXbox(std::move(backend))
{
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    if (SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) == 0) {
        m_sdlInitialized = true;
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
    }
    if (m_sdlInitialized) {
        SDL_QuitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER);
    }
}

QString ControllerManager::connectedDeviceName() const {
    if (m_detectedControllers.isEmpty()) return QStringLiteral("No Controller Connected");
    return m_detectedControllers.first().toMap().value(QStringLiteral("name")).toString();
}

void ControllerManager::refreshControllers() {
    if (!m_sdlInitialized) return;
    SDL_JoystickUpdate();

    // Reset virtual pad inputs to neutral before closing primary controller
    if (m_primaryPad) {
        if (m_virtualXbox.isActive()) {
            m_virtualXbox.resetToNeutral();
        }
        SDL_GameControllerClose(m_primaryPad);
        m_primaryPad = nullptr;
    }
    m_detectedControllers.clear();

    const int count = SDL_NumJoysticks();
    for (int i = 0; i < count; ++i) {
        const char* rawName = SDL_JoystickNameForIndex(i);
        const QString name = rawName ? QString::fromUtf8(rawName) : QStringLiteral("Gamepad %1").arg(i);
        // Skip our own virtual uinput Xbox 360 device if active
        if (m_virtualXbox.isActive() && name == QLatin1String(UinputXboxDevice::kVirtualDeviceName)) {
            continue;
        }

        SDL_JoystickGUID guid = SDL_JoystickGetDeviceGUID(i);
        char guidBuf[64] = {0};
        SDL_JoystickGetGUIDString(guid, guidBuf, sizeof(guidBuf));

        const bool isGameCtrl = (SDL_IsGameController(i) == SDL_TRUE);
        QVariantMap dev;
        dev["index"] = i;
        dev["name"] = name;
        dev["guid"] = QString::fromLatin1(guidBuf);
        dev["isStandardGamepad"] = isGameCtrl;
        dev["isEmulationSupported"] = isGameCtrl;
        dev["vendorId"] = QStringLiteral("0x%1").arg(SDL_JoystickGetDeviceVendor(i), 4, 16, QLatin1Char('0'));
        dev["productId"] = QStringLiteral("0x%1").arg(SDL_JoystickGetDeviceProduct(i), 4, 16, QLatin1Char('0'));
        m_detectedControllers.append(dev);

        // Only assign standard gamepads as the primary emulation pad
        if (!m_primaryPad && isGameCtrl) {
            m_primaryPad = SDL_GameControllerOpen(i);
        }
    }

    // When no usable gamepad is connected, ensure virtual device stays neutral
    if (!m_primaryPad && m_virtualXbox.isActive()) {
        m_virtualXbox.resetToNeutral();
    }

    emit controllersChanged();
}

bool ControllerManager::startXboxEmulation() {
    stopXboxEmulation();

    if (!m_virtualXbox.start(QStringLiteral("Xbox 360 Standard (XInput)"))) {
        emit emulationStateChanged();
        return false;
    }

    m_pollTimer.setInterval(8); // 120Hz low-latency polling during active emulation
    emit emulationStateChanged();
    return true;
}

void ControllerManager::stopXboxEmulation() {
    if (m_virtualXbox.isActive()) {
        m_virtualXbox.stop();
        m_pollTimer.setInterval(16);
        emit emulationStateChanged();
    }
}

qint16 ControllerManager::applyDeadzone(qint16 val, int deadzone) {
    deadzone = qBound(0, deadzone, 30000);
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
        } else if (ev.type == SDL_CONTROLLERBUTTONDOWN && !m_virtualXbox.isActive()) {
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
    if (!m_primaryPad) {
        if (m_virtualXbox.isActive()) {
            m_virtualXbox.resetToNeutral();
        }
        return;
    }

    XboxPadState state;
    state.a = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_A) != 0;
    state.b = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_B) != 0;
    state.x = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_X) != 0;
    state.y = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_Y) != 0;
    state.lb = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_LEFTSHOULDER) != 0;
    state.rb = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER) != 0;
    state.back = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_BACK) != 0;
    state.start = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_START) != 0;
    state.guide = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_GUIDE) != 0;
    state.lstick = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_LEFTSTICK) != 0;
    state.rstick = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_RIGHTSTICK) != 0;
    state.dpadUp = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_UP) != 0;
    state.dpadDown = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_DOWN) != 0;
    state.dpadLeft = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_LEFT) != 0;
    state.dpadRight = SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_RIGHT) != 0;

    state.lx = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_LEFTX), kStandardDeadzone);
    state.ly = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_LEFTY), kStandardDeadzone);
    state.rx = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_RIGHTX), kStandardDeadzone);
    state.ry = applyDeadzone(SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_RIGHTY), kStandardDeadzone);
    state.lt = SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_TRIGGERLEFT);
    state.rt = SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_TRIGGERRIGHT);

    m_virtualXbox.syncState(state);
}

QString ControllerManager::buildSdlGameControllerConfig() const {
    if (m_detectedControllers.isEmpty()) return QString();
    const QVariantMap first = m_detectedControllers.first().toMap();
    const QString guid = first.value(QStringLiteral("guid")).toString();
    const QString name = first.value(QStringLiteral("name")).toString();
    if (guid.isEmpty()) return QString();

    return QStringLiteral("%1,%2,platform:Linux,a:b0,b:b1,x:b2,y:b3,back:b6,guide:b8,start:b7,leftstick:b9,rightstick:b10,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5,")
        .arg(guid, name);
}

} // namespace Tsuki
