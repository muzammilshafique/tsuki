#pragma once

#include <QColor>
#include <QDir>
#include <QObject>
#include <QSettings>
#include <QStandardPaths>

namespace Tsuki {

class DatabaseManager;

class AppSettings : public QObject {
  Q_OBJECT

  // Yoru Theme & Appearance Properties
  Q_PROPERTY(
      int themeMode READ themeMode WRITE setThemeMode NOTIFY themeChanged)
  Q_PROPERTY(bool isEffectiveDark READ isEffectiveDark NOTIFY themeChanged)
  Q_PROPERTY(QString customBgColor READ customBgColor WRITE setCustomBgColor
                 NOTIFY themeChanged)
  Q_PROPERTY(QString customSidebarColor READ customSidebarColor WRITE
                 setCustomSidebarColor NOTIFY themeChanged)
  Q_PROPERTY(bool syncSidebarColor READ syncSidebarColor WRITE
                 setSyncSidebarColor NOTIFY themeChanged)
  Q_PROPERTY(QColor bgColor READ bgColor NOTIFY themeChanged)
  Q_PROPERTY(QColor sidebarColor READ sidebarColor NOTIFY themeChanged)
  Q_PROPERTY(
      QColor sidebarDividerColor READ sidebarDividerColor NOTIFY themeChanged)
  Q_PROPERTY(
      QColor sidebarTextSecColor READ sidebarTextSecColor NOTIFY themeChanged)
  Q_PROPERTY(
      QColor sidebarHoverColor READ sidebarHoverColor NOTIFY themeChanged)
  Q_PROPERTY(QColor accentColor READ accentColor WRITE setAccentColor NOTIFY
                 themeChanged)
  Q_PROPERTY(QColor surfaceColor READ surfaceColor NOTIFY themeChanged)
  Q_PROPERTY(QColor surfaceAltColor READ surfaceAltColor NOTIFY themeChanged)
  Q_PROPERTY(QColor inputColor READ inputColor NOTIFY themeChanged)
  Q_PROPERTY(QColor borderColor READ borderColor NOTIFY themeChanged)
  Q_PROPERTY(QColor textColor READ textColor NOTIFY themeChanged)
  Q_PROPERTY(QColor textSecColor READ textSecColor NOTIFY themeChanged)
  Q_PROPERTY(QColor textTerColor READ textTerColor NOTIFY themeChanged)

  // Tag Colors
  Q_PROPERTY(QColor tagColorSteamProton READ tagColorSteamProton WRITE
                 setTagColorSteamProton NOTIFY themeChanged)
  Q_PROPERTY(QColor tagColorProtonGe READ tagColorProtonGe WRITE
                 setTagColorProtonGe NOTIFY themeChanged)
  Q_PROPERTY(QColor tagColorCachyos READ tagColorCachyos WRITE
                 setTagColorCachyos NOTIFY themeChanged)
  Q_PROPERTY(QColor tagColorLinux READ tagColorLinux WRITE setTagColorLinux
                 NOTIFY themeChanged)

  // Legacy Aliases
  Q_PROPERTY(QColor tagColorSeries READ tagColorSteamProton NOTIFY themeChanged)
  Q_PROPERTY(QColor tagColorMovie READ tagColorProtonGe NOTIFY themeChanged)
  Q_PROPERTY(QColor tagColorAnime READ tagColorCachyos NOTIFY themeChanged)

  // Layout & Card Customization
  Q_PROPERTY(bool sidebarCollapsed READ sidebarCollapsed WRITE
                 setSidebarCollapsed NOTIFY sidebarCollapsedChanged)
  Q_PROPERTY(int defaultFilter READ defaultFilter WRITE setDefaultFilter NOTIFY
                 defaultFilterChanged)
  Q_PROPERTY(int cardRadius READ cardRadius WRITE setCardRadius NOTIFY
                 cardStyleChanged)
  Q_PROPERTY(int thumbScaleTarget READ thumbScaleTarget WRITE
                 setThumbScaleTarget NOTIFY cardStyleChanged)
  Q_PROPERTY(int titleVisibility READ titleVisibility WRITE setTitleVisibility
                 NOTIFY cardStyleChanged)
  Q_PROPERTY(int tagPosition READ tagPosition WRITE setTagPosition NOTIFY
                 cardStyleChanged)
  Q_PROPERTY(
      bool showYear READ showYear WRITE setShowYear NOTIFY cardStyleChanged)
  Q_PROPERTY(int leftClickBehavior READ leftClickBehavior WRITE
                 setLeftClickBehavior NOTIFY behaviorChanged)
  Q_PROPERTY(bool minimizeOnLaunch READ minimizeOnLaunch WRITE
                 setMinimizeOnLaunch NOTIFY behaviorChanged)

  // Global Game Launcher Defaults
  Q_PROPERTY(QString defaultRunnerId READ defaultRunnerId WRITE
                 setDefaultRunnerId NOTIFY runnerDefaultsChanged)
  Q_PROPERTY(QString defaultPrefixLocation READ defaultPrefixLocation WRITE
                 setDefaultPrefixLocation NOTIFY pathDefaultsChanged)
  Q_PROPERTY(QString defaultRunnerLocation READ defaultRunnerLocation WRITE
                 setDefaultRunnerLocation NOTIFY pathDefaultsChanged)
  Q_PROPERTY(bool mangohudDefault READ mangohudDefault WRITE setMangohudDefault
                 NOTIFY performanceDefaultsChanged)
  Q_PROPERTY(bool gamemodeDefault READ gamemodeDefault WRITE setGamemodeDefault
                 NOTIFY performanceDefaultsChanged)
  Q_PROPERTY(bool dxvkDefault READ dxvkDefault WRITE setDxvkDefault NOTIFY
                 performanceDefaultsChanged)
  Q_PROPERTY(bool vkd3dDefault READ vkd3dDefault WRITE setVkd3dDefault NOTIFY
                 performanceDefaultsChanged)
  Q_PROPERTY(bool esyncDefault READ esyncDefault WRITE setEsyncDefault NOTIFY
                 performanceDefaultsChanged)
  Q_PROPERTY(bool fsyncDefault READ fsyncDefault WRITE setFsyncDefault NOTIFY
                 performanceDefaultsChanged)
  Q_PROPERTY(QString defaultDxvkHud READ defaultDxvkHud WRITE setDefaultDxvkHud
                 NOTIFY performanceDefaultsChanged)
  Q_PROPERTY(bool xboxEmulationDefault READ xboxEmulationDefault WRITE
                 setXboxEmulationDefault NOTIFY controllerDefaultsChanged)
  Q_PROPERTY(QString steamGridDbApiKey READ steamGridDbApiKey WRITE
                 setSteamGridDbApiKey NOTIFY apiSettingsChanged)
  Q_PROPERTY(QString logLevel READ logLevel WRITE setLogLevel NOTIFY
                 loggingSettingsChanged)
  Q_PROPERTY(bool enableWineDebugLogs READ enableWineDebugLogs WRITE
                 setEnableWineDebugLogs NOTIFY loggingSettingsChanged)

public:
  explicit AppSettings(QObject *parent = nullptr);

  // XDG Directories
  static QString dataDir();
  static QString configDir();
  static QString cacheDir();
  static QString logsDir();
  static QString artworkDir();
  static QString backupsDir();
  static QString toolsDir();

  // Window Geometry
  Q_INVOKABLE int windowWidth() const;
  Q_INVOKABLE int windowHeight() const;
  Q_INVOKABLE int windowX() const;
  Q_INVOKABLE int windowY() const;
  Q_INVOKABLE bool windowMaximized() const;
  Q_INVOKABLE void saveWindowGeometry(int x, int y, int width, int height,
                                      bool maximized);

  // Theme Getters/Setters
  int themeMode() const { return m_themeMode; }
  Q_INVOKABLE void setThemeMode(int mode);
  bool isEffectiveDark() const;

  QString customBgColor() const { return m_customBgColor; }
  Q_INVOKABLE void setCustomBgColor(const QString &hex);
  QString customSidebarColor() const { return m_customSidebarColor; }
  Q_INVOKABLE void setCustomSidebarColor(const QString &hex);
  bool syncSidebarColor() const { return m_syncSidebarColor; }
  Q_INVOKABLE void setSyncSidebarColor(bool sync);

  Q_INVOKABLE void setBgColor(const QString &hex) { setCustomBgColor(hex); }
  Q_INVOKABLE void setSidebarColor(const QString &hex) {
    setCustomSidebarColor(hex);
  }
  Q_INVOKABLE void resetBgColor();
  Q_INVOKABLE void resetSidebarColor();

  QColor bgColor() const;
  QColor sidebarColor() const;
  QColor sidebarDividerColor() const;
  QColor sidebarTextSecColor() const;
  QColor sidebarHoverColor() const;
  QColor accentColor() const { return m_accentColor; }
  Q_INVOKABLE void setAccentColor(const QColor &c);
  QColor surfaceColor() const;
  QColor surfaceAltColor() const;
  QColor inputColor() const;
  QColor borderColor() const;
  QColor textColor() const;
  QColor textSecColor() const;
  QColor textTerColor() const;

  QColor tagColorSteamProton() const { return m_tagColorSteamProton; }
  void setTagColorSteamProton(const QColor &c);
  QColor tagColorProtonGe() const { return m_tagColorProtonGe; }
  void setTagColorProtonGe(const QColor &c);
  QColor tagColorCachyos() const { return m_tagColorCachyos; }
  void setTagColorCachyos(const QColor &c);
  QColor tagColorLinux() const { return m_tagColorLinux; }
  void setTagColorLinux(const QColor &c);

  QColor tagColorSeries() const { return m_tagColorSteamProton; }
  QColor tagColorMovie() const { return m_tagColorProtonGe; }
  QColor tagColorAnime() const { return m_tagColorCachyos; }

  // Layout & Card
  bool sidebarCollapsed() const { return m_sidebarCollapsed; }
  void setSidebarCollapsed(bool collapsed);
  int defaultFilter() const { return m_defaultFilter; }
  void setDefaultFilter(int filter);
  int cardRadius() const { return m_cardRadius; }
  void setCardRadius(int r);
  int thumbScaleTarget() const { return m_thumbScaleTarget; }
  void setThumbScaleTarget(int s);
  int titleVisibility() const { return m_titleVisibility; }
  void setTitleVisibility(int v);
  int tagPosition() const { return m_tagPosition; }
  void setTagPosition(int p);
  bool showYear() const { return m_showYear; }
  void setShowYear(bool s);
  int leftClickBehavior() const {
    return m_leftClickBehavior;
  } // 0: Launch Game, 1: Open Game Details
  void setLeftClickBehavior(int b);
  bool minimizeOnLaunch() const { return m_minimizeOnLaunch; }
  void setMinimizeOnLaunch(bool m);

  // Launcher Defaults
  QString defaultRunnerId() const { return m_defaultRunnerId; }
  void setDefaultRunnerId(const QString &id);
  QString defaultPrefixLocation() const { return m_defaultPrefixLocation; }
  void setDefaultPrefixLocation(const QString &path);
  QString defaultRunnerLocation() const { return m_defaultRunnerLocation; }
  void setDefaultRunnerLocation(const QString &path);

  bool mangohudDefault() const { return m_mangohudDefault; }
  void setMangohudDefault(bool v);
  bool gamemodeDefault() const { return m_gamemodeDefault; }
  void setGamemodeDefault(bool v);
  bool dxvkDefault() const { return m_dxvkDefault; }
  void setDxvkDefault(bool v);
  bool vkd3dDefault() const { return m_vkd3dDefault; }
  void setVkd3dDefault(bool v);
  bool esyncDefault() const { return m_esyncDefault; }
  void setEsyncDefault(bool v);
  bool fsyncDefault() const { return m_fsyncDefault; }
  void setFsyncDefault(bool v);
  QString defaultDxvkHud() const { return m_defaultDxvkHud; }
  void setDefaultDxvkHud(const QString &hud);

  bool xboxEmulationDefault() const { return m_xboxEmulationDefault; }
  void setXboxEmulationDefault(bool v);
  void setDatabaseManager(DatabaseManager *db) { m_db = db; }

  QString steamGridDbApiKey() const { return m_steamGridDbApiKey; }
  void setSteamGridDbApiKey(const QString &key);

  QString logLevel() const { return m_logLevel; }
  void setLogLevel(const QString &level);
  bool enableWineDebugLogs() const { return m_enableWineDebugLogs; }
  void setEnableWineDebugLogs(bool v);

signals:
  void themeChanged();
  void sidebarCollapsedChanged();
  void defaultFilterChanged();
  void cardStyleChanged();
  void behaviorChanged();
  void runnerDefaultsChanged();
  void pathDefaultsChanged();
  void performanceDefaultsChanged();
  void controllerDefaultsChanged();
  void apiSettingsChanged();
  void loggingSettingsChanged();

private:
  QSettings m_settings;
  int m_themeMode = 0; // 0: Dark, 1: Light, 2: System, 3: AMOLED
  QString m_customBgColor;
  QString m_customSidebarColor;
  bool m_syncSidebarColor = false;
  QColor m_accentColor;
  QColor m_tagColorSteamProton;
  QColor m_tagColorProtonGe;
  QColor m_tagColorCachyos;
  QColor m_tagColorLinux;
  bool m_sidebarCollapsed = false;
  int m_defaultFilter = -1;
  int m_cardRadius = 12;
  int m_thumbScaleTarget = 195;
  int m_titleVisibility = 0; // 0: Below Card, 1: Hover Overlay, 2: Hidden
  int m_tagPosition = 2; // 0: Below Title, 1: Above Title, 2: Badge on Poster
  bool m_showYear = true;
  int m_leftClickBehavior =
      0; // 0: Launch game directly (per spec), 1: Open details
  bool m_minimizeOnLaunch = false;

  QString m_defaultRunnerId;
  QString m_defaultPrefixLocation;
  QString m_defaultRunnerLocation;

  bool m_mangohudDefault = false;
  bool m_gamemodeDefault = false;
  bool m_dxvkDefault = true;
  bool m_vkd3dDefault = true;
  bool m_esyncDefault = true;
  bool m_fsyncDefault = true;
  QString m_defaultDxvkHud = QStringLiteral("none");

  bool m_xboxEmulationDefault = false;

  QString m_steamGridDbApiKey;
  QString m_logLevel = QStringLiteral("info");
  bool m_enableWineDebugLogs = false;
  DatabaseManager *m_db = nullptr;
};

} // namespace Tsuki
