#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "UinputXboxDevice.h"
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <memory>

struct _SDL_GameController;
typedef struct _SDL_GameController SDL_GameController;

namespace Tsuki {

class ControllerManager : public QObject {
    Q_OBJECT

    // Properties compatible with Yoru's uiController.gamepad
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY controllersChanged)
    Q_PROPERTY(QString connectedDeviceName READ connectedDeviceName NOTIFY controllersChanged)
    Q_PROPERTY(QString controllerType READ controllerType NOTIFY controllersChanged)
    Q_PROPERTY(bool isPlayStation READ isPlayStation NOTIFY controllersChanged)
    Q_PROPERTY(bool isXbox READ isXbox NOTIFY controllersChanged)
    Q_PROPERTY(QString actionIconSource READ actionIconSource CONSTANT)
    Q_PROPERTY(QString confirmIconSource READ confirmIconSource CONSTANT)
    Q_PROPERTY(QString backIconSource READ backIconSource CONSTANT)
    Q_PROPERTY(QString cancelIconSource READ cancelIconSource CONSTANT)
    Q_PROPERTY(QString searchIconSource READ searchIconSource CONSTANT)
    Q_PROPERTY(QString optionsIconSource READ optionsIconSource CONSTANT)
    Q_PROPERTY(QString settingsIconSource READ settingsIconSource NOTIFY controllersChanged)
    Q_PROPERTY(QString tabLeftIconSource READ tabLeftIconSource NOTIFY controllersChanged)
    Q_PROPERTY(QString tabLeftTriggerIconSource READ tabLeftTriggerIconSource NOTIFY controllersChanged)
    Q_PROPERTY(QString tabRightIconSource READ tabRightIconSource NOTIFY controllersChanged)
    Q_PROPERTY(QString tabRightTriggerIconSource READ tabRightTriggerIconSource NOTIFY controllersChanged)
    Q_PROPERTY(QString dpadUpIconSource READ dpadUpIconSource CONSTANT)
    Q_PROPERTY(QString dpadDownIconSource READ dpadDownIconSource CONSTANT)
    Q_PROPERTY(QString dpadLeftIconSource READ dpadLeftIconSource CONSTANT)
    Q_PROPERTY(QString dpadRightIconSource READ dpadRightIconSource CONSTANT)
    Q_PROPERTY(QString leftAnalogIconSource READ leftAnalogIconSource CONSTANT)
    Q_PROPERTY(QString rightAnalogIconSource READ rightAnalogIconSource CONSTANT)

    // Tsuki Controller Management Properties
    Q_PROPERTY(QVariantList detectedControllers READ detectedControllers NOTIFY controllersChanged)
    Q_PROPERTY(bool isEmulationActive READ isEmulationActive NOTIFY emulationStateChanged)
    Q_PROPERTY(QString uinputStatus READ uinputStatus NOTIFY emulationStateChanged)
    Q_PROPERTY(bool isGameRunning READ isGameRunning NOTIFY gameRunningChanged)

public:
    explicit ControllerManager(DatabaseManager* db,
                               AppSettings* settings,
                               std::unique_ptr<IUinputBackend> backend = nullptr,
                               QObject* parent = nullptr);
    ~ControllerManager() override;

    bool isConnected() const { return !m_detectedControllers.isEmpty(); }
    QString connectedDeviceName() const;
    QString controllerType() const { return m_controllerTypeOverride.isEmpty() ? m_detectedControllerType : m_controllerTypeOverride; }
    bool isPlayStation() const { return controllerType() == QLatin1String("playstation"); }
    bool isXbox() const { return controllerType() == QLatin1String("xbox"); }

    QString actionIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-down.svg"); }
    QString confirmIconSource() const { return actionIconSource(); }
    QString backIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"); }
    QString cancelIconSource() const { return backIconSource(); }
    QString searchIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"); }
    QString optionsIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-left.svg"); }
    QString settingsIconSource() const;
    QString tabLeftIconSource() const;
    QString tabLeftTriggerIconSource() const;
    QString tabRightIconSource() const;
    QString tabRightTriggerIconSource() const;
    QString dpadUpIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/dpad-up.svg"); }
    QString dpadDownIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/dpad-down.svg"); }
    QString dpadLeftIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/dpad-left.svg"); }
    QString dpadRightIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/dpad-right.svg"); }
    QString leftAnalogIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/left-analog.svg"); }
    QString rightAnalogIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/right-analog.svg"); }

    QVariantList detectedControllers() const { return m_detectedControllers; }
    bool isEmulationActive() const { return m_virtualXbox.isActive(); }
    QString uinputStatus() const { return m_virtualXbox.status(); }
    bool isGameRunning() const { return m_gameRunning; }
    void setGameRunning(bool running);

    // Emulation Lifecycle
    Q_INVOKABLE bool startXboxEmulation();
    Q_INVOKABLE void stopXboxEmulation();
    Q_INVOKABLE void refreshControllers();
    Q_INVOKABLE void setControllerTypeOverride(const QString& type);

    static QString detectControllerTypeFromInfo(const QString& name, quint16 vendorId, int sdlControllerType = 0);
    bool isSendingSyntheticKey() const { return m_sendingSyntheticKey; }

    // Input translation (also callable from unit tests)
    void handleButtonPress(int sdlButton);
    void handleButtonRelease(int sdlButton);
    void handleAxisMotion(int sdlAxis, int value);

    // Generate SDL_GAMECONTROLLERCONFIG string for game launch environment
    QString buildSdlGameControllerConfig() const;

    static quint16 linuxKeyCodeForName(const QString& name) {
        return UinputXboxDevice::linuxKeyCodeForName(name);
    }

    static bool isValidButtonName(const QString& name) {
        return UinputXboxDevice::isValidButtonName(name);
    }

    static QVariantMap defaultXboxMappings() {
        return UinputXboxDevice::defaultXboxMappings();
    }

    UinputXboxDevice* virtualXboxDevice() { return &m_virtualXbox; }

    static constexpr int kStandardDeadzone = 4000;
    static qint16 applyDeadzone(qint16 val, int deadzone = kStandardDeadzone);

signals:
    void controllersChanged();
    void emulationStateChanged();
    void gameRunningChanged();
    void uiKeySimulated(int qtKey);
    void gamepadInputReceived(const QString& controllerType);
    void searchActionRequested();
    void optionsActionRequested();
    void settingsActionRequested();
    void tabLeftRequested();
    void tabRightRequested();

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    QTimer m_pollTimer;
    QTimer m_repeatTimer;
    bool m_sdlInitialized = false;

    QVariantList m_detectedControllers;
    SDL_GameController* m_primaryPad = nullptr;
    QString m_detectedControllerType = QStringLiteral("xbox");
    QString m_controllerTypeOverride;

    // Navigation auto-repeat & analog axis edge detection
    int m_activeRepeatKey = 0;
    bool m_dpadUp = false;
    bool m_dpadDown = false;
    bool m_dpadLeft = false;
    bool m_dpadRight = false;
    int m_stickDirX = 0;
    int m_stickDirY = 0;
    bool m_leftTriggerHeld = false;
    bool m_rightTriggerHeld = false;
    bool m_sendingSyntheticKey = false;
    bool m_gameRunning = false;

    UinputXboxDevice m_virtualXbox;

    void pollSdlEvents();
    void syncVirtualXboxPad();
    void sendKeyToQuickWindow(int qtKey);
    void updateNavigationDirection();
    void resetNavigationState();
};

} // namespace Tsuki
