#include "ControllerManager.h"
#include <QDebug>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QUuid>
#include <QWindow>
#include <SDL2/SDL.h>

namespace Tsuki {

ControllerManager::ControllerManager(DatabaseManager *db, AppSettings *settings,
                                     std::unique_ptr<IUinputBackend> backend,
                                     QObject *parent)
    : QObject(parent), m_db(db), m_settings(settings),
      m_virtualXbox(std::move(backend)) {
  SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
  if (SDL_InitSubSystem(SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER) == 0) {
    m_sdlInitialized = true;
  }

  refreshControllers();

  connect(&m_pollTimer, &QTimer::timeout, this,
          &ControllerManager::pollSdlEvents);
  m_pollTimer.start(16); // ~60Hz poll

  connect(&m_repeatTimer, &QTimer::timeout, this, [this]() {
    if (m_activeRepeatKey == 0 || m_virtualXbox.isActive() || m_gameRunning) {
      m_repeatTimer.stop();
      return;
    }
    sendKeyToQuickWindow(m_activeRepeatKey);
    if (m_repeatTimer.interval() != 110) {
      m_repeatTimer.setInterval(110);
    }
  });
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
  if (m_detectedControllers.isEmpty())
    return QStringLiteral("No Controller Connected");
  return m_detectedControllers.first()
      .toMap()
      .value(QStringLiteral("name"))
      .toString();
}

QString ControllerManager::detectControllerTypeFromInfo(const QString &name,
                                                        quint16 vendorId,
                                                        int sdlControllerType) {
  switch (sdlControllerType) {
  case SDL_CONTROLLER_TYPE_PS3:
  case SDL_CONTROLLER_TYPE_PS4:
  case SDL_CONTROLLER_TYPE_PS5:
    return QStringLiteral("playstation");
  case SDL_CONTROLLER_TYPE_XBOX360:
  case SDL_CONTROLLER_TYPE_XBOXONE:
    return QStringLiteral("xbox");
  default:
    break;
  }
  if (vendorId == 0x054c) {
    return QStringLiteral("playstation");
  }
  if (vendorId == 0x045e) {
    return QStringLiteral("xbox");
  }
  const QString lower = name.toLower();
  if (lower.contains(QLatin1String("playstation")) ||
      lower.contains(QLatin1String("dualshock")) ||
      lower.contains(QLatin1String("dualsense")) ||
      lower.contains(QLatin1String("ps3")) ||
      lower.contains(QLatin1String("ps4")) ||
      lower.contains(QLatin1String("ps5")) ||
      lower.contains(QLatin1String("sixaxis")) ||
      lower.contains(QLatin1String("sony"))) {
    return QStringLiteral("playstation");
  }
  return QStringLiteral("xbox");
}

QString ControllerManager::settingsIconSource() const {
  return isPlayStation()
             ? QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/options.svg")
             : QStringLiteral(
                   "qrc:/tsuki_app/icons/gamepad/xbox/xbox-menu.svg");
}

QString ControllerManager::tabLeftIconSource() const {
  return isPlayStation()
             ? QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/l1.svg")
             : QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/lb.svg");
}

QString ControllerManager::tabLeftTriggerIconSource() const {
  return isPlayStation()
             ? QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/l2.svg")
             : QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/lt.svg");
}

QString ControllerManager::tabRightIconSource() const {
  return isPlayStation()
             ? QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/r1.svg")
             : QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/rb.svg");
}

QString ControllerManager::tabRightTriggerIconSource() const {
  return isPlayStation()
             ? QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/r2.svg")
             : QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/rt.svg");
}

void ControllerManager::setControllerTypeOverride(const QString &type) {
  const QString normalized = type.trimmed().toLower();
  if (m_controllerTypeOverride == normalized)
    return;
  m_controllerTypeOverride = normalized;
  emit controllersChanged();
}

void ControllerManager::refreshControllers() {
  if (!m_sdlInitialized)
    return;
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

  QString firstDetectedType = QStringLiteral("xbox");
  bool haveType = false;

  const int count = SDL_NumJoysticks();
  for (int i = 0; i < count; ++i) {
    const char *rawName = SDL_JoystickNameForIndex(i);
    const QString name = rawName ? QString::fromUtf8(rawName)
                                 : QStringLiteral("Gamepad %1").arg(i);
    // Skip our own virtual uinput Xbox 360 device if active
    if (m_virtualXbox.isActive() &&
        name == QLatin1String(UinputXboxDevice::kVirtualDeviceName)) {
      continue;
    }

    SDL_JoystickGUID guid = SDL_JoystickGetDeviceGUID(i);
    char guidBuf[64] = {0};
    SDL_JoystickGetGUIDString(guid, guidBuf, sizeof(guidBuf));

    const quint16 vendor = SDL_JoystickGetDeviceVendor(i);
    const quint16 product = SDL_JoystickGetDeviceProduct(i);
    const bool isGameCtrl = (SDL_IsGameController(i) == SDL_TRUE);
    const int sdlType =
        isGameCtrl ? static_cast<int>(SDL_GameControllerTypeForIndex(i)) : 0;
    const QString ctrlType =
        detectControllerTypeFromInfo(name, vendor, sdlType);

    QVariantMap dev;
    dev["index"] = i;
    dev["name"] = name;
    dev["guid"] = QString::fromLatin1(guidBuf);
    dev["isStandardGamepad"] = isGameCtrl;
    dev["isEmulationSupported"] = isGameCtrl;
    dev["controllerType"] = ctrlType;
    dev["vendorId"] =
        QStringLiteral("0x%1").arg(vendor, 4, 16, QLatin1Char('0'));
    dev["productId"] =
        QStringLiteral("0x%1").arg(product, 4, 16, QLatin1Char('0'));
    m_detectedControllers.append(dev);

    if (!haveType) {
      firstDetectedType = ctrlType;
      haveType = true;
    }

    // Only assign standard gamepads as the primary emulation pad
    if (!m_primaryPad && isGameCtrl) {
      m_primaryPad = SDL_GameControllerOpen(i);
      const int openedType =
          static_cast<int>(SDL_GameControllerGetType(m_primaryPad));
      const quint16 openedVendor = SDL_GameControllerGetVendor(m_primaryPad);
      firstDetectedType = detectControllerTypeFromInfo(
          name, openedVendor ? openedVendor : vendor, openedType);
      haveType = true;
    }
  }

  m_detectedControllerType = firstDetectedType;

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

  m_pollTimer.setInterval(
      8); // 120Hz low-latency polling during active emulation
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
  if (qAbs(static_cast<int>(val)) < deadzone)
    return 0;
  return val;
}

void ControllerManager::sendKeyToQuickWindow(int qtKey) {
  if (qtKey == 0)
    return;
  emit uiKeySimulated(qtKey);
  if (QWindow *win = QGuiApplication::focusWindow()) {
    m_sendingSyntheticKey = true;
    QKeyEvent pressEv(QEvent::KeyPress, qtKey, Qt::NoModifier);
    QKeyEvent relEv(QEvent::KeyRelease, qtKey, Qt::NoModifier);
    QGuiApplication::sendEvent(win, &pressEv);
    QGuiApplication::sendEvent(win, &relEv);
    m_sendingSyntheticKey = false;
  }
}

void ControllerManager::updateNavigationDirection() {
  int desiredKey = 0;
  if (m_dpadUp || m_stickDirY < 0)
    desiredKey = Qt::Key_Up;
  else if (m_dpadDown || m_stickDirY > 0)
    desiredKey = Qt::Key_Down;
  else if (m_dpadLeft || m_stickDirX < 0)
    desiredKey = Qt::Key_Left;
  else if (m_dpadRight || m_stickDirX > 0)
    desiredKey = Qt::Key_Right;

  if (desiredKey == m_activeRepeatKey)
    return;
  m_activeRepeatKey = desiredKey;
  if (desiredKey == 0) {
    m_repeatTimer.stop();
  } else {
    sendKeyToQuickWindow(desiredKey);
    m_repeatTimer.start(350);
  }
}

void ControllerManager::resetNavigationState() {
  m_activeRepeatKey = 0;
  m_dpadUp = m_dpadDown = m_dpadLeft = m_dpadRight = false;
  m_stickDirX = m_stickDirY = 0;
  m_leftTriggerHeld = m_rightTriggerHeld = false;
  m_repeatTimer.stop();
}

void ControllerManager::setGameRunning(bool running) {
  if (m_gameRunning == running)
    return;
  m_gameRunning = running;
  if (m_gameRunning) {
    resetNavigationState();
  }
  emit gameRunningChanged();
}

void ControllerManager::handleButtonPress(int sdlButton) {
  if (m_gameRunning || m_virtualXbox.isActive()) {
    resetNavigationState();
    return;
  }
  emit gamepadInputReceived(controllerType());
  switch (sdlButton) {
  case SDL_CONTROLLER_BUTTON_DPAD_UP:
    m_dpadUp = true;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
    m_dpadDown = true;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
    m_dpadLeft = true;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
    m_dpadRight = true;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_A:
    sendKeyToQuickWindow(Qt::Key_Return);
    break;
  case SDL_CONTROLLER_BUTTON_B:
  case SDL_CONTROLLER_BUTTON_BACK:
    sendKeyToQuickWindow(Qt::Key_Escape);
    break;
  case SDL_CONTROLLER_BUTTON_X:
    sendKeyToQuickWindow(Qt::Key_Menu);
    emit optionsActionRequested();
    break;
  case SDL_CONTROLLER_BUTTON_Y:
    emit searchActionRequested();
    break;
  case SDL_CONTROLLER_BUTTON_START:
    emit settingsActionRequested();
    break;
  case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:
    emit tabLeftRequested();
    break;
  case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
    emit tabRightRequested();
    break;
  default:
    break;
  }
}

void ControllerManager::handleButtonRelease(int sdlButton) {
  if (m_gameRunning || m_virtualXbox.isActive()) {
    resetNavigationState();
    return;
  }
  switch (sdlButton) {
  case SDL_CONTROLLER_BUTTON_DPAD_UP:
    m_dpadUp = false;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
    m_dpadDown = false;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
    m_dpadLeft = false;
    updateNavigationDirection();
    break;
  case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
    m_dpadRight = false;
    updateNavigationDirection();
    break;
  default:
    break;
  }
}

void ControllerManager::handleAxisMotion(int sdlAxis, int value) {
  if (m_gameRunning || m_virtualXbox.isActive()) {
    resetNavigationState();
    return;
  }
  constexpr int kStickEngageThreshold = 16000;
  constexpr int kStickReleaseThreshold = 10000;
  constexpr int kTriggerEngageThreshold = 16000;
  constexpr int kTriggerReleaseThreshold = 8000;

  switch (sdlAxis) {
  case SDL_CONTROLLER_AXIS_LEFTX: {
    int nextX = m_stickDirX;
    if (value > kStickEngageThreshold)
      nextX = 1;
    else if (value < -kStickEngageThreshold)
      nextX = -1;
    else if (qAbs(value) < kStickReleaseThreshold)
      nextX = 0;

    if (nextX != m_stickDirX) {
      m_stickDirX = nextX;
      if (nextX != 0)
        emit gamepadInputReceived(controllerType());
      updateNavigationDirection();
    }
    break;
  }
  case SDL_CONTROLLER_AXIS_LEFTY: {
    int nextY = m_stickDirY;
    if (value > kStickEngageThreshold)
      nextY = 1;
    else if (value < -kStickEngageThreshold)
      nextY = -1;
    else if (qAbs(value) < kStickReleaseThreshold)
      nextY = 0;

    if (nextY != m_stickDirY) {
      m_stickDirY = nextY;
      if (nextY != 0)
        emit gamepadInputReceived(controllerType());
      updateNavigationDirection();
    }
    break;
  }
  case SDL_CONTROLLER_AXIS_TRIGGERLEFT: {
    if (!m_leftTriggerHeld && value > kTriggerEngageThreshold) {
      m_leftTriggerHeld = true;
      emit gamepadInputReceived(controllerType());
      emit tabLeftRequested();
    } else if (m_leftTriggerHeld && value < kTriggerReleaseThreshold) {
      m_leftTriggerHeld = false;
    }
    break;
  }
  case SDL_CONTROLLER_AXIS_TRIGGERRIGHT: {
    if (!m_rightTriggerHeld && value > kTriggerEngageThreshold) {
      m_rightTriggerHeld = true;
      emit gamepadInputReceived(controllerType());
      emit tabRightRequested();
    } else if (m_rightTriggerHeld && value < kTriggerReleaseThreshold) {
      m_rightTriggerHeld = false;
    }
    break;
  }
  default:
    break;
  }
}

void ControllerManager::pollSdlEvents() {
  if (!m_sdlInitialized)
    return;

  SDL_Event ev;
  bool deviceListChanged = false;
  const bool appActive =
      (QGuiApplication::applicationState() == Qt::ApplicationActive) &&
      (QGuiApplication::focusWindow() != nullptr);
  const bool uiNavActive = !m_virtualXbox.isActive() && !m_gameRunning && appActive;
  if (!uiNavActive) {
    resetNavigationState();
  }

  while (SDL_PollEvent(&ev)) {
    if (ev.type == SDL_JOYDEVICEADDED || ev.type == SDL_JOYDEVICEREMOVED) {
      deviceListChanged = true;
    } else if (uiNavActive) {
      if (ev.type == SDL_CONTROLLERBUTTONDOWN) {
        handleButtonPress(ev.cbutton.button);
      } else if (ev.type == SDL_CONTROLLERBUTTONUP) {
        handleButtonRelease(ev.cbutton.button);
      } else if (ev.type == SDL_CONTROLLERAXISMOTION) {
        handleAxisMotion(ev.caxis.axis, ev.caxis.value);
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
  state.a =
      SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_A) != 0;
  state.b =
      SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_B) != 0;
  state.x =
      SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_X) != 0;
  state.y =
      SDL_GameControllerGetButton(m_primaryPad, SDL_CONTROLLER_BUTTON_Y) != 0;
  state.lb = SDL_GameControllerGetButton(
                 m_primaryPad, SDL_CONTROLLER_BUTTON_LEFTSHOULDER) != 0;
  state.rb = SDL_GameControllerGetButton(
                 m_primaryPad, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER) != 0;
  state.back = SDL_GameControllerGetButton(m_primaryPad,
                                           SDL_CONTROLLER_BUTTON_BACK) != 0;
  state.start = SDL_GameControllerGetButton(m_primaryPad,
                                            SDL_CONTROLLER_BUTTON_START) != 0;
  state.guide = SDL_GameControllerGetButton(m_primaryPad,
                                            SDL_CONTROLLER_BUTTON_GUIDE) != 0;
  state.lstick = SDL_GameControllerGetButton(
                     m_primaryPad, SDL_CONTROLLER_BUTTON_LEFTSTICK) != 0;
  state.rstick = SDL_GameControllerGetButton(
                     m_primaryPad, SDL_CONTROLLER_BUTTON_RIGHTSTICK) != 0;
  state.dpadUp = SDL_GameControllerGetButton(
                     m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_UP) != 0;
  state.dpadDown = SDL_GameControllerGetButton(
                       m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_DOWN) != 0;
  state.dpadLeft = SDL_GameControllerGetButton(
                       m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_LEFT) != 0;
  state.dpadRight = SDL_GameControllerGetButton(
                        m_primaryPad, SDL_CONTROLLER_BUTTON_DPAD_RIGHT) != 0;

  state.lx = applyDeadzone(
      SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_LEFTX),
      kStandardDeadzone);
  state.ly = applyDeadzone(
      SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_LEFTY),
      kStandardDeadzone);
  state.rx = applyDeadzone(
      SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_RIGHTX),
      kStandardDeadzone);
  state.ry = applyDeadzone(
      SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_RIGHTY),
      kStandardDeadzone);
  state.lt =
      SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_TRIGGERLEFT);
  state.rt =
      SDL_GameControllerGetAxis(m_primaryPad, SDL_CONTROLLER_AXIS_TRIGGERRIGHT);

  m_virtualXbox.syncState(state);
}

QString ControllerManager::buildSdlGameControllerConfig() const {
  if (m_detectedControllers.isEmpty())
    return QString();
  const QVariantMap first = m_detectedControllers.first().toMap();
  const QString guid = first.value(QStringLiteral("guid")).toString();
  const QString name = first.value(QStringLiteral("name")).toString();
  if (guid.isEmpty())
    return QString();

  return QStringLiteral(
             "%1,%2,platform:Linux,a:b0,b:b1,x:b2,y:b3,back:b6,guide:b8,start:"
             "b7,leftstick:b9,rightstick:b10,leftshoulder:b4,rightshoulder:b5,"
             "dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,"
             "rightx:a3,righty:a4,lefttrigger:a2,righttrigger:a5,")
      .arg(guid, name);
}

} // namespace Tsuki
