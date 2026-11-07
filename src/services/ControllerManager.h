#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include <QObject>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

struct _SDL_GameController;
typedef struct _SDL_GameController SDL_GameController;
struct _SDL_Joystick;
typedef struct _SDL_Joystick SDL_Joystick;

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
    Q_PROPERTY(QVariantList profiles READ profilesVariant NOTIFY profilesChanged)
    Q_PROPERTY(bool isEmulationActive READ isEmulationActive NOTIFY emulationStateChanged)
    Q_PROPERTY(QString activeProfileId READ activeProfileId NOTIFY emulationStateChanged)
    Q_PROPERTY(QString uinputStatus READ uinputStatus NOTIFY emulationStateChanged)
    Q_PROPERTY(QVariantMap liveInputState READ liveInputState NOTIFY liveInputChanged)

public:
    explicit ControllerManager(DatabaseManager* db, AppSettings* settings, QObject* parent = nullptr);
    ~ControllerManager() override;

    bool isConnected() const { return !m_detectedControllers.isEmpty(); }
    QString connectedDeviceName() const;
    QString actionIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-down.svg"); }
    QString backIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"); }
    QString searchIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"); }
    QString optionsIconSource() const { return QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-left.svg"); }

    QVariantList detectedControllers() const { return m_detectedControllers; }
    QVariantList profilesVariant() const;
    bool isEmulationActive() const { return m_uinputFd >= 0; }
    QString activeProfileId() const { return m_activeProfile.id; }
    QString uinputStatus() const { return m_uinputStatus; }
    QVariantMap liveInputState() const { return m_liveInputState; }

    // Profile CRUD
    Q_INVOKABLE QString createProfile(const QString& name, bool xboxEmulation = true, int deadzone = 4000);
    Q_INVOKABLE bool saveProfile(const QString& profileId, const QString& name, bool xboxEmulation, int deadzone, const QVariantMap& mappings);
    Q_INVOKABLE bool deleteProfile(const QString& profileId);
    Q_INVOKABLE QVariantMap getProfileMap(const QString& profileId) const;

    // Emulation Lifecycle (Automatic on game launch/exit + manual toggle for testing)
    Q_INVOKABLE bool startXboxEmulation(const QString& profileId = QString());
    Q_INVOKABLE void stopXboxEmulation();
    Q_INVOKABLE void refreshControllers();

    // Generate SDL_GAMECONTROLLERCONFIG string for game launch environment
    QString buildSdlGameControllerConfig(const QString& profileId = QString()) const;

    static quint16 linuxKeyCodeForName(const QString& name);

signals:
    void controllersChanged();
    void profilesChanged();
    void emulationStateChanged();
    void liveInputChanged();
    void uiKeySimulated(int qtKey);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    QTimer m_pollTimer;
    bool m_sdlInitialized = false;

    QVariantList m_detectedControllers;
    SDL_GameController* m_primaryPad = nullptr;
    SDL_Joystick* m_primaryJoy = nullptr;
    int m_primaryInstanceId = -1;

    int m_uinputFd = -1;
    QString m_uinputStatus = QStringLiteral("Idle");
    ControllerProfileRecord m_activeProfile;
    QVariantMap m_liveInputState;

    void pollSdlEvents();
    void emitUinputEvent(quint16 type, quint16 code, qint32 value);
    void syncVirtualXboxPad();
    static qint16 applyDeadzone(qint16 val, int deadzone);
};

} // namespace Tsuki

