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
    Q_PROPERTY(QString actionIconSource READ actionIconSource CONSTANT)
    Q_PROPERTY(QString backIconSource READ backIconSource CONSTANT)
    Q_PROPERTY(QString searchIconSource READ searchIconSource CONSTANT)
    Q_PROPERTY(QString optionsIconSource READ optionsIconSource CONSTANT)

    // Tsuki Controller Management Properties
    Q_PROPERTY(QVariantList detectedControllers READ detectedControllers NOTIFY controllersChanged)
    Q_PROPERTY(bool isEmulationActive READ isEmulationActive NOTIFY emulationStateChanged)
    Q_PROPERTY(QString uinputStatus READ uinputStatus NOTIFY emulationStateChanged)

public:
    explicit ControllerManager(DatabaseManager* db,
                               AppSettings* settings,
                               std::unique_ptr<IUinputBackend> backend = nullptr,
                               QObject* parent = nullptr);
    ~ControllerManager() override;

    bool isConnected() const { return !m_detectedControllers.isEmpty(); }
    QString connectedDeviceName() const;
    QString actionIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-down.svg"); }
    QString backIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"); }
    QString searchIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"); }
    QString optionsIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-left.svg"); }

    QVariantList detectedControllers() const { return m_detectedControllers; }
    bool isEmulationActive() const { return m_virtualXbox.isActive(); }
    QString uinputStatus() const { return m_virtualXbox.status(); }

    // Emulation Lifecycle
    Q_INVOKABLE bool startXboxEmulation();
    Q_INVOKABLE void stopXboxEmulation();
    Q_INVOKABLE void refreshControllers();

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
    void uiKeySimulated(int qtKey);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    QTimer m_pollTimer;
    bool m_sdlInitialized = false;

    QVariantList m_detectedControllers;
    SDL_GameController* m_primaryPad = nullptr;

    UinputXboxDevice m_virtualXbox;

    void pollSdlEvents();
    void syncVirtualXboxPad();
};

} // namespace Tsuki
