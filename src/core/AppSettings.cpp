#include "AppSettings.h"
#include "DatabaseManager.h"
#include <QGuiApplication>
#include <QStyleHints>

namespace Tsuki {

AppSettings::AppSettings(QObject* parent)
    : QObject(parent)
    , m_settings(QStringLiteral("Tsuki"), QStringLiteral("TsukiLauncher"))
{
    // Ensure all XDG directories exist
    QDir().mkpath(dataDir());
    QDir().mkpath(configDir());
    QDir().mkpath(cacheDir());
    QDir().mkpath(logsDir());
    QDir().mkpath(artworkDir());
    QDir().mkpath(backupsDir());
    QDir().mkpath(toolsDir());

    m_themeMode = m_settings.value(QStringLiteral("appearance/themeMode"), 0).toInt();
    m_accentColor = QColor(m_settings.value(QStringLiteral("appearance/accentColor"), QStringLiteral("#5b9cf6")).toString());
    if (!m_accentColor.isValid()) {
        m_accentColor = QColor(QStringLiteral("#5b9cf6"));
    }
    m_tagColorLinux = QColor(m_settings.value(QStringLiteral("appearance/tagColorLinux"), QStringLiteral("#f59e0b")).toString());
    if (!m_tagColorLinux.isValid()) {
        m_tagColorLinux = QColor(QStringLiteral("#f59e0b"));
    }
    m_tagColorSteamProton = QColor(m_settings.value(QStringLiteral("appearance/tagColorSteamProton"), QStringLiteral("#38bdf8")).toString());
    if (!m_tagColorSteamProton.isValid()) {
        m_tagColorSteamProton = QColor(QStringLiteral("#38bdf8"));
    }
    m_tagColorProtonGe = QColor(m_settings.value(QStringLiteral("appearance/tagColorProtonGe"), QStringLiteral("#a855f7")).toString());
    if (!m_tagColorProtonGe.isValid()) {
        m_tagColorProtonGe = QColor(QStringLiteral("#a855f7"));
    }
    m_tagColorCachyos = QColor(m_settings.value(QStringLiteral("appearance/tagColorCachyos"), QStringLiteral("#2dd4bf")).toString());
    if (!m_tagColorCachyos.isValid()) {
        m_tagColorCachyos = QColor(QStringLiteral("#2dd4bf"));
    }

    if (QGuiApplication::styleHints()) {
        QObject::connect(QGuiApplication::styleHints(), &QStyleHints::colorSchemeChanged, this, [this](Qt::ColorScheme) {
            if (m_themeMode == 2) {
                emit themeChanged();
            }
        });
    }
    m_sidebarCollapsed = m_settings.value(QStringLiteral("appearance/sidebarCollapsed"), false).toBool();
    m_defaultFilter = m_settings.value(QStringLiteral("appearance/defaultFilter"), -1).toInt();
    m_cardRadius = m_settings.value(QStringLiteral("appearance/cardRadius"), 12).toInt();
    m_thumbScaleTarget = m_settings.value(QStringLiteral("appearance/thumbScaleTarget"), 195).toInt();
    m_titleVisibility = m_settings.value(QStringLiteral("appearance/titleVisibility"), 0).toInt();
    m_tagPosition = m_settings.value(QStringLiteral("appearance/tagPosition"), 2).toInt();
    m_showYear = m_settings.value(QStringLiteral("appearance/showYear"), true).toBool();
    m_leftClickBehavior = m_settings.value(QStringLiteral("behavior/leftClickBehavior"), 0).toInt();
    m_minimizeOnLaunch = m_settings.value(QStringLiteral("behavior/minimizeOnLaunch"), false).toBool();

    const QString defaultPrefixes = dataDir() + QStringLiteral("/prefixes");
    const QString defaultRunners = dataDir() + QStringLiteral("/runners");
    QDir().mkpath(defaultPrefixes);
    QDir().mkpath(defaultRunners);

    m_defaultRunnerId = m_settings.value(QStringLiteral("defaults/runnerId"), QString()).toString();
    m_defaultPrefixLocation = m_settings.value(QStringLiteral("defaults/prefixLocation"), defaultPrefixes).toString();
    m_defaultRunnerLocation = m_settings.value(QStringLiteral("defaults/runnerLocation"), defaultRunners).toString();
    QDir().mkpath(m_defaultPrefixLocation);
    QDir().mkpath(m_defaultRunnerLocation);

    m_mangohudDefault = m_settings.value(QStringLiteral("performance/mangohud"), false).toBool();
    m_gamemodeDefault = m_settings.value(QStringLiteral("performance/gamemode"), false).toBool();
    m_dxvkDefault = m_settings.value(QStringLiteral("performance/dxvk"), true).toBool();
    m_vkd3dDefault = m_settings.value(QStringLiteral("performance/vkd3d"), true).toBool();
    m_esyncDefault = m_settings.value(QStringLiteral("performance/esync"), true).toBool();
    m_fsyncDefault = m_settings.value(QStringLiteral("performance/fsync"), true).toBool();
    m_defaultDxvkHud = m_settings.value(QStringLiteral("performance/dxvkHud"), QStringLiteral("none")).toString();

    m_xboxEmulationDefault = m_settings.value(QStringLiteral("controller/xboxEmulation"), false).toBool();

    m_steamGridDbApiKey = m_settings.value(QStringLiteral("integrations/steamGridDbApiKey"), QString()).toString();
    m_logLevel = m_settings.value(QStringLiteral("logging/logLevel"), QStringLiteral("info")).toString();
    m_enableWineDebugLogs = m_settings.value(QStringLiteral("logging/enableWineDebugLogs"), false).toBool();
}

QString AppSettings::dataDir() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    if (base.isEmpty()) base = QDir::homePath() + QStringLiteral("/.local/share");
    return base + QStringLiteral("/tsuki");
}

QString AppSettings::configDir() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
    if (base.isEmpty()) base = QDir::homePath() + QStringLiteral("/.config");
    return base + QStringLiteral("/tsuki");
}

QString AppSettings::cacheDir() {
    QString base = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    if (base.isEmpty()) base = QDir::homePath() + QStringLiteral("/.cache");
    return base + QStringLiteral("/tsuki");
}

QString AppSettings::logsDir() {
    return dataDir() + QStringLiteral("/logs");
}

QString AppSettings::artworkDir() {
    return dataDir() + QStringLiteral("/artwork");
}

QString AppSettings::backupsDir() {
    return dataDir() + QStringLiteral("/backups");
}

QString AppSettings::toolsDir() {
    return dataDir() + QStringLiteral("/tools");
}

int AppSettings::windowWidth() const {
    return m_settings.value(QStringLiteral("window/width"), 1280).toInt();
}

int AppSettings::windowHeight() const {
    return m_settings.value(QStringLiteral("window/height"), 820).toInt();
}

int AppSettings::windowX() const {
    return m_settings.value(QStringLiteral("window/x"), -1).toInt();
}

int AppSettings::windowY() const {
    return m_settings.value(QStringLiteral("window/y"), -1).toInt();
}

bool AppSettings::windowMaximized() const {
    return m_settings.value(QStringLiteral("window/maximized"), false).toBool();
}

void AppSettings::saveWindowGeometry(int x, int y, int width, int height, bool maximized) {
    m_settings.setValue(QStringLiteral("window/x"), x);
    m_settings.setValue(QStringLiteral("window/y"), y);
    m_settings.setValue(QStringLiteral("window/width"), width);
    m_settings.setValue(QStringLiteral("window/height"), height);
    m_settings.setValue(QStringLiteral("window/maximized"), maximized);
}

void AppSettings::setThemeMode(int mode) {
    if (m_themeMode == mode) return;
    m_themeMode = mode;
    m_settings.setValue(QStringLiteral("appearance/themeMode"), mode);
    emit themeChanged();
}

void AppSettings::setAccentColor(const QColor& c) {
    if (!c.isValid() || m_accentColor == c) return;
    m_accentColor = c;
    m_settings.setValue(QStringLiteral("appearance/accentColor"), c.name());
    emit themeChanged();
}

void AppSettings::setTagColorSteamProton(const QColor& c) {
    if (!c.isValid() || m_tagColorSteamProton == c) return;
    m_tagColorSteamProton = c;
    m_settings.setValue(QStringLiteral("appearance/tagColorSteamProton"), c.name());
    emit themeChanged();
}

void AppSettings::setTagColorProtonGe(const QColor& c) {
    if (!c.isValid() || m_tagColorProtonGe == c) return;
    m_tagColorProtonGe = c;
    m_settings.setValue(QStringLiteral("appearance/tagColorProtonGe"), c.name());
    emit themeChanged();
}

void AppSettings::setTagColorCachyos(const QColor& c) {
    if (!c.isValid() || m_tagColorCachyos == c) return;
    m_tagColorCachyos = c;
    m_settings.setValue(QStringLiteral("appearance/tagColorCachyos"), c.name());
    emit themeChanged();
}

void AppSettings::setTagColorLinux(const QColor& c) {
    if (!c.isValid() || m_tagColorLinux == c) return;
    m_tagColorLinux = c;
    m_settings.setValue(QStringLiteral("appearance/tagColorLinux"), c.name());
    emit themeChanged();
}

bool AppSettings::isEffectiveDark() const {
    if (m_themeMode == 0) return true;
    if (m_themeMode == 1) return false;
    // 2: System
    if (QGuiApplication::styleHints()) {
        return QGuiApplication::styleHints()->colorScheme() == Qt::ColorScheme::Dark;
    }
    return true;
}

QColor AppSettings::bgColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#f8fafc"));
    return QColor(QStringLiteral("#0d0d11"));
}

QColor AppSettings::sidebarColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#f1f5f9"));
    return QColor(QStringLiteral("#111116"));
}

QColor AppSettings::sidebarDividerColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#e2e8f0"));
    return QColor(255, 255, 255, 16);
}

QColor AppSettings::sidebarTextSecColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#475569"));
    return QColor(QStringLiteral("#a1a1aa"));
}

QColor AppSettings::sidebarHoverColor() const {
    if (!isEffectiveDark()) return QColor(0, 0, 0, 12);
    return QColor(255, 255, 255, 14);
}

QColor AppSettings::surfaceColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#ffffff"));
    return QColor(QStringLiteral("#16161d"));
}

QColor AppSettings::surfaceAltColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#f1f5f9"));
    return QColor(QStringLiteral("#1f1f29"));
}

QColor AppSettings::inputColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#e2e8f0"));
    return QColor(QStringLiteral("#191922"));
}

QColor AppSettings::borderColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#cbd5e1"));
    return QColor(255, 255, 255, 22);
}

QColor AppSettings::textColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#0f172a"));
    return QColor(QStringLiteral("#f4f4f5"));
}

QColor AppSettings::textSecColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#475569"));
    return QColor(QStringLiteral("#a1a1aa"));
}

QColor AppSettings::textTerColor() const {
    if (!isEffectiveDark()) return QColor(QStringLiteral("#94a3b8"));
    return QColor(QStringLiteral("#71717a"));
}

void AppSettings::setSidebarCollapsed(bool collapsed) {
    if (m_sidebarCollapsed == collapsed) return;
    m_sidebarCollapsed = collapsed;
    m_settings.setValue(QStringLiteral("appearance/sidebarCollapsed"), collapsed);
    emit sidebarCollapsedChanged();
}

void AppSettings::setDefaultFilter(int filter) {
    if (m_defaultFilter == filter) return;
    m_defaultFilter = filter;
    m_settings.setValue(QStringLiteral("appearance/defaultFilter"), filter);
    emit defaultFilterChanged();
}

void AppSettings::setCardRadius(int r) {
    if (m_cardRadius == r) return;
    m_cardRadius = r;
    m_settings.setValue(QStringLiteral("appearance/cardRadius"), r);
    emit cardStyleChanged();
}

void AppSettings::setThumbScaleTarget(int s) {
    s = qBound(140, s, 300);
    if (m_thumbScaleTarget == s) return;
    m_thumbScaleTarget = s;
    m_settings.setValue(QStringLiteral("appearance/thumbScaleTarget"), s);
    emit cardStyleChanged();
}

void AppSettings::setTitleVisibility(int v) {
    if (m_titleVisibility == v) return;
    m_titleVisibility = v;
    m_settings.setValue(QStringLiteral("appearance/titleVisibility"), v);
    emit cardStyleChanged();
}

void AppSettings::setTagPosition(int p) {
    if (m_tagPosition == p) return;
    m_tagPosition = p;
    m_settings.setValue(QStringLiteral("appearance/tagPosition"), p);
    emit cardStyleChanged();
}

void AppSettings::setShowYear(bool s) {
    if (m_showYear == s) return;
    m_showYear = s;
    m_settings.setValue(QStringLiteral("appearance/showYear"), s);
    emit cardStyleChanged();
}

void AppSettings::setLeftClickBehavior(int b) {
    if (m_leftClickBehavior == b) return;
    m_leftClickBehavior = b;
    m_settings.setValue(QStringLiteral("behavior/leftClickBehavior"), b);
    emit behaviorChanged();
}

void AppSettings::setMinimizeOnLaunch(bool m) {
    if (m_minimizeOnLaunch == m) return;
    m_minimizeOnLaunch = m;
    m_settings.setValue(QStringLiteral("behavior/minimizeOnLaunch"), m);
    emit behaviorChanged();
}

void AppSettings::setDefaultRunnerId(const QString& id) {
    if (m_defaultRunnerId == id) return;
    m_defaultRunnerId = id;
    m_settings.setValue(QStringLiteral("defaults/runnerId"), id);
    emit runnerDefaultsChanged();
}

void AppSettings::setDefaultPrefixLocation(const QString& path) {
    if (m_defaultPrefixLocation == path || path.isEmpty()) return;
    m_defaultPrefixLocation = path;
    QDir().mkpath(path);
    m_settings.setValue(QStringLiteral("defaults/prefixLocation"), path);
    emit pathDefaultsChanged();
}

void AppSettings::setDefaultRunnerLocation(const QString& path) {
    if (m_defaultRunnerLocation == path || path.isEmpty()) return;
    m_defaultRunnerLocation = path;
    QDir().mkpath(path);
    m_settings.setValue(QStringLiteral("defaults/runnerLocation"), path);
    emit pathDefaultsChanged();
}

void AppSettings::setMangohudDefault(bool v) {
    if (m_mangohudDefault == v) return;
    m_mangohudDefault = v;
    m_settings.setValue(QStringLiteral("performance/mangohud"), v);
    emit performanceDefaultsChanged();
}

void AppSettings::setGamemodeDefault(bool v) {
    if (m_gamemodeDefault == v) return;
    m_gamemodeDefault = v;
    m_settings.setValue(QStringLiteral("performance/gamemode"), v);
    emit performanceDefaultsChanged();
}

void AppSettings::setDxvkDefault(bool v) {
    if (m_dxvkDefault == v) return;
    m_dxvkDefault = v;
    m_settings.setValue(QStringLiteral("performance/dxvk"), v);
    emit performanceDefaultsChanged();
}

void AppSettings::setVkd3dDefault(bool v) {
    if (m_vkd3dDefault == v) return;
    m_vkd3dDefault = v;
    m_settings.setValue(QStringLiteral("performance/vkd3d"), v);
    emit performanceDefaultsChanged();
}

void AppSettings::setEsyncDefault(bool v) {
    if (m_esyncDefault == v) return;
    m_esyncDefault = v;
    m_settings.setValue(QStringLiteral("performance/esync"), v);
    emit performanceDefaultsChanged();
}

void AppSettings::setFsyncDefault(bool v) {
    if (m_fsyncDefault == v) return;
    m_fsyncDefault = v;
    m_settings.setValue(QStringLiteral("performance/fsync"), v);
    emit performanceDefaultsChanged();
}

void AppSettings::setDefaultDxvkHud(const QString& hud) {
    if (m_defaultDxvkHud == hud) return;
    m_defaultDxvkHud = hud;
    m_settings.setValue(QStringLiteral("performance/dxvkHud"), hud);
    emit performanceDefaultsChanged();
}

void AppSettings::setXboxEmulationDefault(bool v) {
    if (m_xboxEmulationDefault == v) return;
    m_xboxEmulationDefault = v;
    m_settings.setValue(QStringLiteral("controller/xboxEmulation"), v);
    if (m_db) {
        m_db->setAllGamesXboxEmulationState(v);
    }
    emit controllerDefaultsChanged();
}

void AppSettings::setSteamGridDbApiKey(const QString& key) {
    if (m_steamGridDbApiKey == key) return;
    m_steamGridDbApiKey = key.trimmed();
    m_settings.setValue(QStringLiteral("integrations/steamGridDbApiKey"), m_steamGridDbApiKey);
    emit apiSettingsChanged();
}

void AppSettings::setLogLevel(const QString& level) {
    if (m_logLevel == level) return;
    m_logLevel = level;
    m_settings.setValue(QStringLiteral("logging/logLevel"), level);
    emit loggingSettingsChanged();
}

void AppSettings::setEnableWineDebugLogs(bool v) {
    if (m_enableWineDebugLogs == v) return;
    m_enableWineDebugLogs = v;
    m_settings.setValue(QStringLiteral("logging/enableWineDebugLogs"), v);
    emit loggingSettingsChanged();
}

} // namespace Tsuki

