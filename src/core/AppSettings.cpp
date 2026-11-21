#include "AppSettings.h"
#include "DatabaseManager.h"
#include "Models.h"
#include "SecretStore.h"
#include <QDir>
#include <QFileInfo>
#include <QFont>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStyleHints>
#include <QUrl>
#include <algorithm>
#include <cmath>

namespace Tsuki {

AppSettings::AppSettings(QObject *parent)
    : QObject(parent),
      m_settings(QStringLiteral("Tsuki"), QStringLiteral("TsukiLauncher")) {
  // Ensure all XDG directories exist
  QDir().mkpath(dataDir());
  QDir().mkpath(configDir());
  QDir().mkpath(cacheDir());
  QDir().mkpath(logsDir());
  QDir().mkpath(artworkDir());
  QDir().mkpath(backupsDir());
  QDir().mkpath(toolsDir());

  m_themeMode =
      m_settings.value(QStringLiteral("appearance/themeMode"), 2).toInt();
  m_customBgColor =
      m_settings.value(QStringLiteral("appearance/customBgColor"), QString())
          .toString();
  m_customSidebarColor =
      m_settings
          .value(QStringLiteral("appearance/customSidebarColor"), QString())
          .toString();
  m_syncSidebarColor =
      m_settings.value(QStringLiteral("appearance/syncSidebarColor"), false)
          .toBool();
  m_accentColor = QColor(m_settings
                             .value(QStringLiteral("appearance/accentColor"),
                                    QStringLiteral("#d71920"))
                             .toString());
  if (!m_accentColor.isValid()) {
    m_accentColor = QColor(QStringLiteral("#d71920"));
  }
  m_tagColorLinux =
      QColor(m_settings
                 .value(QStringLiteral("appearance/tagColorLinux"),
                        QStringLiteral("#f59e0b"))
                 .toString());
  if (!m_tagColorLinux.isValid()) {
    m_tagColorLinux = QColor(QStringLiteral("#f59e0b"));
  }
  m_tagColorSteamProton =
      QColor(m_settings
                 .value(QStringLiteral("appearance/tagColorSteamProton"),
                        QStringLiteral("#38bdf8"))
                 .toString());
  if (!m_tagColorSteamProton.isValid()) {
    m_tagColorSteamProton = QColor(QStringLiteral("#38bdf8"));
  }
  m_tagColorProtonGe =
      QColor(m_settings
                 .value(QStringLiteral("appearance/tagColorProtonGe"),
                        QStringLiteral("#a855f7"))
                 .toString());
  if (!m_tagColorProtonGe.isValid()) {
    m_tagColorProtonGe = QColor(QStringLiteral("#a855f7"));
  }
  m_tagColorCachyos =
      QColor(m_settings
                 .value(QStringLiteral("appearance/tagColorCachyos"),
                        QStringLiteral("#2dd4bf"))
                 .toString());
  if (!m_tagColorCachyos.isValid()) {
    m_tagColorCachyos = QColor(QStringLiteral("#2dd4bf"));
  }

  if (QGuiApplication::styleHints()) {
    QObject::connect(QGuiApplication::styleHints(),
                     &QStyleHints::colorSchemeChanged, this,
                     [this](Qt::ColorScheme) {
                       if (m_themeMode == 2) {
                         emit themeChanged();
                       }
                     });
  }
  m_sidebarCollapsed =
      m_settings.value(QStringLiteral("appearance/sidebarCollapsed"), false)
          .toBool();
  m_defaultFilter =
      m_settings.value(QStringLiteral("appearance/defaultFilter"), -1).toInt();
  if (m_defaultFilter == 4) {
    m_defaultFilter = -1;
    m_settings.setValue(QStringLiteral("appearance/defaultFilter"), -1);
  }
  m_cardRadius =
      m_settings.value(QStringLiteral("appearance/cardRadius"), 12).toInt();
  m_thumbScaleTarget =
      m_settings.value(QStringLiteral("appearance/thumbScaleTarget"), 195)
          .toInt();
  m_titleVisibility =
      m_settings.value(QStringLiteral("appearance/titleVisibility"), 0).toInt();
  m_tagPosition =
      m_settings.value(QStringLiteral("appearance/tagPosition"), 2).toInt();
  m_showYear =
      m_settings.value(QStringLiteral("appearance/showYear"), true).toBool();
  m_showGameName =
      m_settings.value(QStringLiteral("appearance/showGameName"), false)
          .toBool();
  m_showEpicBadge =
      m_settings.value(QStringLiteral("appearance/showEpicBadge"), true)
          .toBool();
  m_leftClickBehavior =
      m_settings.value(QStringLiteral("behavior/leftClickBehavior"), 0).toInt();
  m_minimizeOnLaunch =
      m_settings.value(QStringLiteral("behavior/minimizeOnLaunch"), false)
          .toBool();
  m_showNavigationHud =
      m_settings.value(QStringLiteral("behavior/showNavigationHud"), true)
          .toBool();

  const QString defaultPrefixes = dataDir() + QStringLiteral("/prefixes");
  const QString defaultRunners = dataDir() + QStringLiteral("/runners");
  const QString defaultEpicGames = QDir::homePath() + QStringLiteral("/Games/Epic");
  QDir().mkpath(defaultPrefixes);
  QDir().mkpath(defaultRunners);

  m_defaultRunnerId =
      m_settings.value(QStringLiteral("defaults/runnerId"), QString())
          .toString();
  m_defaultPrefixLocation =
      m_settings
          .value(QStringLiteral("defaults/prefixLocation"), defaultPrefixes)
          .toString();
  m_defaultRunnerLocation =
      m_settings
          .value(QStringLiteral("defaults/runnerLocation"), defaultRunners)
          .toString();
  m_defaultEpicInstallLocation =
      m_settings
          .value(QStringLiteral("defaults/epicInstallLocation"), defaultEpicGames)
          .toString();
  QDir().mkpath(m_defaultPrefixLocation);
  QDir().mkpath(m_defaultRunnerLocation);

  m_mangohudDefault =
      m_settings.value(QStringLiteral("performance/mangohud"), false).toBool();
  m_gamemodeDefault =
      m_settings.value(QStringLiteral("performance/gamemode"), false).toBool();
  m_gamescopeDefault =
      m_settings.value(QStringLiteral("performance/gamescope"), false).toBool();
  {
    GamescopeConfig defGs;
    const QString gsJson =
        m_settings
            .value(QStringLiteral("performance/gamescopeConfig"), QString())
            .toString();
    if (!gsJson.isEmpty()) {
      const QJsonDocument doc = QJsonDocument::fromJson(gsJson.toUtf8());
      if (doc.isObject()) {
        defGs = GamescopeConfig::fromJsonObject(doc.object());
      }
    }
    defGs.inheritGlobal = false;
    m_defaultGamescopeConfig = defGs.toVariantMap();
  }
  m_dxvkDefault =
      m_settings.value(QStringLiteral("performance/dxvk"), true).toBool();
  m_vkd3dDefault =
      m_settings.value(QStringLiteral("performance/vkd3d"), true).toBool();
  m_esyncDefault =
      m_settings.value(QStringLiteral("performance/esync"), true).toBool();
  m_fsyncDefault =
      m_settings.value(QStringLiteral("performance/fsync"), true).toBool();
  const bool defaultNtsync = QFileInfo::exists(QStringLiteral("/dev/ntsync"));
  m_ntsyncDefault =
      m_settings.value(QStringLiteral("performance/ntsync"), defaultNtsync).toBool();
  m_umuDefault =
      m_settings.value(QStringLiteral("performance/umu"), true).toBool();
  m_waylandDriverDefault =
      m_settings.value(QStringLiteral("performance/waylandDriver"), false).toBool();
  m_hdrDefault =
      m_settings.value(QStringLiteral("performance/hdr"), false).toBool();
  m_nvapiDefault =
      m_settings.value(QStringLiteral("performance/nvapi"), false).toBool();
  m_fsrDefault =
      m_settings.value(QStringLiteral("performance/fsr"), false).toBool();
  m_defaultFsrStrength = qBound(
      0,
      m_settings.value(QStringLiteral("performance/fsrStrength"), 2).toInt(),
      5);
  m_defaultGpuSelection =
      m_settings.value(QStringLiteral("performance/gpuSelection"), QString())
          .toString();
  m_preferX86_64V3Runners =
      m_settings
          .value(QStringLiteral("runners/preferX86_64V3"),
                 SecretStore::detectCpuX86_64V3())
          .toBool();
  m_allowDeleteSteamRunners =
      m_settings
          .value(QStringLiteral("runners/allowDeleteSteamRunners"), false)
          .toBool();
  m_defaultDxvkHud =
      m_settings
          .value(QStringLiteral("performance/dxvkHud"), QStringLiteral("none"))
          .toString();
  m_downloadSpeedLimitKBps = qMax(
      0,
      m_settings.value(QStringLiteral("downloads/speedLimitKBps"), 0).toInt());
  m_maxConcurrentChunkWorkers = qBound(
      1,
      m_settings.value(QStringLiteral("downloads/maxChunkWorkers"), 6).toInt(),
      16);
  m_maxConcurrentGameDownloads = qBound(
      1,
      m_settings.value(QStringLiteral("downloads/maxConcurrentGames"), 1).toInt(),
      4);
  m_pauseDownloadsOnGameLaunch =
      m_settings
          .value(QStringLiteral("downloads/pauseOnGameLaunch"), true)
          .toBool();
  m_autoUpdateEpicGames =
      m_settings
          .value(QStringLiteral("downloads/autoUpdateEpicGames"), true)
          .toBool();

  m_xboxEmulationDefault =
      m_settings.value(QStringLiteral("controller/xboxEmulation"), false)
          .toBool();

  m_steamGridDbApiKey =
      m_settings
          .value(QStringLiteral("integrations/steamGridDbApiKey"), QString())
          .toString();
  m_autoFetchEpicArtwork =
      m_settings
          .value(QStringLiteral("integrations/autoFetchEpicArtwork"), true)
          .toBool();
  m_logLevel =
      m_settings
          .value(QStringLiteral("logging/logLevel"), QStringLiteral("info"))
          .toString();
  m_enableWineDebugLogs =
      m_settings.value(QStringLiteral("logging/enableWineDebugLogs"), false)
          .toBool();
}

QString AppSettings::dataDir() {
  QString base =
      QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
  if (base.isEmpty())
    base = QDir::homePath() + QStringLiteral("/.local/share");
  return base + QStringLiteral("/tsuki");
}

QString AppSettings::configDir() {
  QString base =
      QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation);
  if (base.isEmpty())
    base = QDir::homePath() + QStringLiteral("/.config");
  return base + QStringLiteral("/tsuki");
}

QString AppSettings::cacheDir() {
  QString base =
      QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
  if (base.isEmpty())
    base = QDir::homePath() + QStringLiteral("/.cache");
  return base + QStringLiteral("/tsuki");
}

QString AppSettings::logsDir() { return dataDir() + QStringLiteral("/logs"); }

QString AppSettings::artworkDir() {
  return dataDir() + QStringLiteral("/artwork");
}

QString AppSettings::backupsDir() {
  return dataDir() + QStringLiteral("/backups");
}

QString AppSettings::toolsDir() { return dataDir() + QStringLiteral("/tools"); }

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

void AppSettings::saveWindowGeometry(int x, int y, int width, int height,
                                     bool maximized) {
  m_settings.setValue(QStringLiteral("window/x"), x);
  m_settings.setValue(QStringLiteral("window/y"), y);
  m_settings.setValue(QStringLiteral("window/width"), width);
  m_settings.setValue(QStringLiteral("window/height"), height);
  m_settings.setValue(QStringLiteral("window/maximized"), maximized);
}

void AppSettings::setThemeMode(int mode) {
  if (m_themeMode == mode)
    return;
  m_themeMode = mode;
  m_settings.setValue(QStringLiteral("appearance/themeMode"), mode);
  if (mode == 3) {
    m_customBgColor.clear();
    m_settings.remove(QStringLiteral("appearance/customBgColor"));
  }
  emit themeChanged();
}

void AppSettings::setCustomBgColor(const QString &hex) {
  if (hex.trimmed().isEmpty()) {
    resetBgColor();
    return;
  }
  if (m_customBgColor == hex)
    return;
  m_customBgColor = hex;
  m_settings.setValue(QStringLiteral("appearance/customBgColor"), hex);
  emit themeChanged();
}

void AppSettings::resetBgColor() {
  if (m_customBgColor.isEmpty())
    return;
  m_customBgColor.clear();
  m_settings.remove(QStringLiteral("appearance/customBgColor"));
  emit themeChanged();
}

void AppSettings::setCustomSidebarColor(const QString &hex) {
  if (hex.trimmed().isEmpty()) {
    resetSidebarColor();
    return;
  }
  if (m_customSidebarColor == hex && !m_syncSidebarColor)
    return;
  m_customSidebarColor = hex;
  m_syncSidebarColor = false;
  m_settings.setValue(QStringLiteral("appearance/customSidebarColor"), hex);
  m_settings.setValue(QStringLiteral("appearance/syncSidebarColor"), false);
  emit themeChanged();
}

void AppSettings::resetSidebarColor() {
  if (m_customSidebarColor.isEmpty())
    return;
  m_customSidebarColor.clear();
  m_settings.remove(QStringLiteral("appearance/customSidebarColor"));
  emit themeChanged();
}

void AppSettings::setSyncSidebarColor(bool sync) {
  if (m_syncSidebarColor == sync)
    return;
  m_syncSidebarColor = sync;
  m_settings.setValue(QStringLiteral("appearance/syncSidebarColor"), sync);
  emit themeChanged();
}

void AppSettings::setAccentColor(const QColor &c) {
  if (!c.isValid() || m_accentColor == c)
    return;
  m_accentColor = c;
  m_settings.setValue(QStringLiteral("appearance/accentColor"), c.name());
  emit themeChanged();
}

void AppSettings::setTagColorSteamProton(const QColor &c) {
  if (!c.isValid() || m_tagColorSteamProton == c)
    return;
  m_tagColorSteamProton = c;
  m_settings.setValue(QStringLiteral("appearance/tagColorSteamProton"),
                      c.name());
  emit themeChanged();
}

void AppSettings::setTagColorProtonGe(const QColor &c) {
  if (!c.isValid() || m_tagColorProtonGe == c)
    return;
  m_tagColorProtonGe = c;
  m_settings.setValue(QStringLiteral("appearance/tagColorProtonGe"), c.name());
  emit themeChanged();
}

void AppSettings::setTagColorCachyos(const QColor &c) {
  if (!c.isValid() || m_tagColorCachyos == c)
    return;
  m_tagColorCachyos = c;
  m_settings.setValue(QStringLiteral("appearance/tagColorCachyos"), c.name());
  emit themeChanged();
}

void AppSettings::setTagColorLinux(const QColor &c) {
  if (!c.isValid() || m_tagColorLinux == c)
    return;
  m_tagColorLinux = c;
  m_settings.setValue(QStringLiteral("appearance/tagColorLinux"), c.name());
  emit themeChanged();
}

bool AppSettings::isEffectiveDark() const {
  if (m_themeMode == 0 || m_themeMode == 3)
    return true;
  if (m_themeMode == 1)
    return false;
  // 2: System
  if (QGuiApplication::styleHints()) {
    const Qt::ColorScheme scheme = QGuiApplication::styleHints()->colorScheme();
    if (scheme != Qt::ColorScheme::Unknown) {
      return scheme == Qt::ColorScheme::Dark;
    }
  }
  return true;
}

QColor AppSettings::bgColor() const {
  if (!m_customBgColor.isEmpty() && QColor::isValidColorName(m_customBgColor)) {
    return QColor(m_customBgColor);
  }
  if (m_themeMode == 3)
    return QColor(QStringLiteral("#000000"));
  if (!isEffectiveDark())
    return QColor(QStringLiteral("#f8fafc"));
  return QColor(QStringLiteral("#0d0d11"));
}

QColor AppSettings::sidebarColor() const {
  if (m_syncSidebarColor) {
    return bgColor();
  }
  if (!m_customSidebarColor.isEmpty() &&
      QColor::isValidColorName(m_customSidebarColor)) {
    return QColor(m_customSidebarColor);
  }
  if (m_themeMode == 3)
    return QColor(QStringLiteral("#000000"));
  if (!isEffectiveDark())
    return QColor(QStringLiteral("#f1f5f9"));
  return QColor(QStringLiteral("#111116"));
}

QColor AppSettings::sidebarDividerColor() const {
  if (m_syncSidebarColor ||
      (!m_customSidebarColor.isEmpty() &&
       QColor::isValidColorName(m_customSidebarColor)) ||
      m_themeMode == 3) {
    QColor sb = sidebarColor();
    if (sb.lightnessF() < 0.5) {
      return QColor(qMin(255, sb.red() + 18), qMin(255, sb.green() + 18),
                    qMin(255, sb.blue() + 22));
    } else {
      return QColor(qMax(0, sb.red() - 22), qMax(0, sb.green() - 22),
                    qMax(0, sb.blue() - 22));
    }
  }
  if (!isEffectiveDark())
    return QColor(QStringLiteral("#e2e8f0"));
  return QColor(255, 255, 255, 16);
}

QColor AppSettings::sidebarTextSecColor() const {
  return sidebarColor().lightnessF() < 0.5 ? QColor(QStringLiteral("#a1a1aa"))
                                           : QColor(QStringLiteral("#5f6368"));
}

QColor AppSettings::sidebarHoverColor() const {
  if (m_syncSidebarColor ||
      (!m_customSidebarColor.isEmpty() &&
       QColor::isValidColorName(m_customSidebarColor)) ||
      m_themeMode == 3) {
    QColor sb = sidebarColor();
    if (sb.lightnessF() < 0.5) {
      return QColor(qMin(255, sb.red() + 20), qMin(255, sb.green() + 20),
                    qMin(255, sb.blue() + 24));
    } else {
      return QColor(qMax(0, sb.red() - 18), qMax(0, sb.green() - 18),
                    qMax(0, sb.blue() - 18));
    }
  }
  if (!isEffectiveDark())
    return QColor(0, 0, 0, 12);
  return QColor(255, 255, 255, 14);
}

namespace {

double srgbChannelLuminance(int channel255) {
  const double c = static_cast<double>(channel255) / 255.0;
  return (c <= 0.03928) ? (c / 12.92) : std::pow((c + 0.055) / 1.055, 2.4);
}

double relativeLuminance(const QColor &color) {
  return 0.2126 * srgbChannelLuminance(color.red()) +
         0.7152 * srgbChannelLuminance(color.green()) +
         0.0722 * srgbChannelLuminance(color.blue());
}

} // namespace

void AppSettings::registerApplicationFonts() {
  static bool fontsRegistered = false;
  if (!fontsRegistered) {
    fontsRegistered = true;
    struct FontSpec {
      const char *systemPaths[4];
      const char *bundledPath;
      const char *aliasTarget;
    };
    const FontSpec specs[] = {
        {{"/usr/share/fonts/TTF/Rubik-Regular.ttf",
          "/usr/share/fonts/google-rubik/Rubik-Regular.ttf",
          "/usr/share/fonts/rubik/Rubik-Regular.ttf",
          "/usr/share/fonts/truetype/rubik/Rubik-Regular.ttf"},
         ":/tsuki_app/fonts/Rubik-Regular.ttf",
         nullptr},
        {{"/usr/share/fonts/TTF/Rubik-Medium.ttf",
          "/usr/share/fonts/google-rubik/Rubik-Medium.ttf",
          "/usr/share/fonts/rubik/Rubik-Medium.ttf",
          "/usr/share/fonts/truetype/rubik/Rubik-Medium.ttf"},
         ":/tsuki_app/fonts/Rubik-Medium.ttf",
         nullptr},
        {{"/usr/share/fonts/TTF/Rubik-SemiBold.ttf",
          "/usr/share/fonts/google-rubik/Rubik-SemiBold.ttf",
          "/usr/share/fonts/rubik/Rubik-SemiBold.ttf",
          "/usr/share/fonts/truetype/rubik/Rubik-SemiBold.ttf"},
         ":/tsuki_app/fonts/Rubik-SemiBold.ttf",
         nullptr},
        {{"/usr/share/fonts/TTF/Rubik-Bold.ttf",
          "/usr/share/fonts/google-rubik/Rubik-Bold.ttf",
          "/usr/share/fonts/rubik/Rubik-Bold.ttf",
          "/usr/share/fonts/truetype/rubik/Rubik-Bold.ttf"},
         ":/tsuki_app/fonts/Rubik-Bold.ttf",
         nullptr},
        {{"/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf",
          "/usr/share/fonts/nerd-fonts/JetBrainsMonoNerdFont-Regular.ttf",
          "/usr/local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf", nullptr},
         nullptr,
         "JetBrains Mono NF"},
    };

    for (const auto &spec : specs) {
      int fontId = -1;
      for (const char *sysPath : spec.systemPaths) {
        if (sysPath == nullptr) {
          continue;
        }
        const QString candidate = QString::fromLatin1(sysPath);
        if (QFileInfo::exists(candidate)) {
          fontId = QFontDatabase::addApplicationFont(candidate);
          if (fontId >= 0) {
            break;
          }
        }
      }
      if (fontId < 0 && spec.bundledPath != nullptr) {
        fontId = QFontDatabase::addApplicationFont(
            QString::fromLatin1(spec.bundledPath));
      }
      if (fontId >= 0 && spec.aliasTarget != nullptr) {
        const QStringList families =
            QFontDatabase::applicationFontFamilies(fontId);
        if (!families.isEmpty()) {
          const QString target = QString::fromLatin1(spec.aliasTarget);
          if (!families.contains(target)) {
            QFont::insertSubstitution(target, families.first());
          }
        }
      }
    }

    // Ensure "JetBrains Mono NF" resolves even if Fontconfig supplies the font
    // from another directory or on non-Arch systems without the package.
    const QString targetFamily = QStringLiteral("JetBrains Mono NF");
    const QStringList allFamilies = QFontDatabase::families();
    if (!allFamilies.contains(targetFamily) &&
        QFont::substitutes(targetFamily).isEmpty()) {
      QString substitute;
      for (const QString &candidate :
           {QStringLiteral("JetBrainsMono Nerd Font"),
            QStringLiteral("JetBrainsMono NF"),
            QStringLiteral("JetBrains Mono")}) {
        if (allFamilies.contains(candidate)) {
          substitute = candidate;
          break;
        }
      }
      if (substitute.isEmpty()) {
        substitute =
            QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
        if (substitute.isEmpty()) {
          substitute = QStringLiteral("monospace");
        }
      }
      QFont::insertSubstitution(targetFamily, substitute);
    }
  }

  if (QGuiApplication::instance() != nullptr) {
    QFont defaultFont = QGuiApplication::font();
    defaultFont.setFamily(QStringLiteral("Rubik"));
    QGuiApplication::setFont(defaultFont);
  }
}

QColor AppSettings::tonalSurfaceColor(int tier) const {
  const int idx = qBound(0, tier, 4);
  const QColor bg = bgColor();
  const bool dark = isEffectiveDark();

  // Compute subtle tonal unit tint vector from accent color
  const int ar = m_accentColor.red();
  const int ag = m_accentColor.green();
  const int ab = m_accentColor.blue();
  const int amax = std::max({ar, ag, ab});
  const int amin = std::min({ar, ag, ab});
  const int aspan = amax - amin;
  float ah = 0.0f, asat = 0.0f, al = 0.0f;
  m_accentColor.getHslF(&ah, &asat, &al);
  const float satScale =
      (aspan == 0 || asat < 0.05f) ? 0.0f : qBound(0.45f, asat / 0.65f, 1.0f);
  const double uR =
      (aspan > 0) ? (static_cast<double>(ar - amin) / aspan) * satScale : 0.0;
  const double uG =
      (aspan > 0) ? (static_cast<double>(ag - amin) / aspan) * satScale : 0.0;
  const double uB =
      (aspan > 0) ? (static_cast<double>(ab - amin) / aspan) * satScale : 0.0;

  if (!m_customBgColor.isEmpty() && bg.isValid()) {
    if (idx == 0) {
      return bg;
    }
    float h = 0.0f, s = 0.0f, l = 0.0f;
    bg.getHslF(&h, &s, &l);
    if (h < 0.0f) {
      h = (ah >= 0.0f) ? ah : 0.0f;
      s = 0.0f;
    }
    static constexpr float darkSteps[5] = {0.0f, 0.035f, 0.068f, 0.105f,
                                           0.145f};
    static constexpr float lightSteps[5] = {0.0f, -0.035f, -0.065f, -0.095f,
                                            -0.125f};
    const float targetL = dark ? qMin(0.40f, l + darkSteps[idx])
                               : qMax(0.75f, l + lightSteps[idx]);
    return QColor::fromHslF(h, s, targetL);
  }

  if (dark && (m_themeMode == 3 || bg == QColor(QStringLiteral("#000000")))) {
    if (idx == 0) {
      return QColor(0, 0, 0);
    }
    static constexpr int amoledBase[5] = {0, 10, 17, 25, 34};
    static constexpr int amoledChroma[5] = {0, 2, 4, 6, 8};
    return QColor(
        qBound(0, qRound(amoledBase[idx] + amoledChroma[idx] * uR), 255),
        qBound(0, qRound(amoledBase[idx] + amoledChroma[idx] * uG), 255),
        qBound(0, qRound(amoledBase[idx] + amoledChroma[idx] * uB), 255));
  }

  if (dark) {
    static constexpr int darkBase[5] = {12, 20, 26, 35, 44};
    static constexpr int darkChroma[5] = {2, 4, 6, 8, 10};
    return QColor(qBound(0, qRound(darkBase[idx] + darkChroma[idx] * uR), 255),
                  qBound(0, qRound(darkBase[idx] + darkChroma[idx] * uG), 255),
                  qBound(0, qRound(darkBase[idx] + darkChroma[idx] * uB), 255));
  }

  static constexpr int lightBase[5] = {255, 242, 236, 229, 222};
  static constexpr int lightChroma[5] = {0, 5, 5, 6, 6};
  return QColor(qBound(0, qRound(lightBase[idx] + lightChroma[idx] * uR), 255),
                qBound(0, qRound(lightBase[idx] + lightChroma[idx] * uG), 255),
                qBound(0, qRound(lightBase[idx] + lightChroma[idx] * uB), 255));
}

QColor AppSettings::surfaceContainerLowest() const {
  return tonalSurfaceColor(0);
}

QColor AppSettings::surfaceContainerLow() const { return tonalSurfaceColor(1); }

QColor AppSettings::surfaceContainer() const { return tonalSurfaceColor(2); }

QColor AppSettings::surfaceContainerHigh() const {
  return tonalSurfaceColor(3);
}

QColor AppSettings::surfaceContainerHighest() const {
  return tonalSurfaceColor(4);
}

QColor AppSettings::secondaryContainer() const {
  float h = 0.0f, s = 0.0f, l = 0.0f;
  m_accentColor.getHslF(&h, &s, &l);
  const bool achromatic = (h < 0.0f || s < 0.05f);
  if (isEffectiveDark()) {
    const float targetL = (m_themeMode == 3) ? 0.17f : 0.22f;
    return achromatic
               ? QColor::fromHslF(0.0f, 0.0f, targetL)
               : QColor::fromHslF(h, qBound(0.18f, s * 0.45f, 0.40f), targetL);
  }
  return achromatic
             ? QColor::fromHslF(0.0f, 0.0f, 0.90f)
             : QColor::fromHslF(h, qBound(0.32f, s * 0.65f, 0.72f), 0.91f);
}

QColor AppSettings::onSecondaryContainer() const {
  float h = 0.0f, s = 0.0f, l = 0.0f;
  m_accentColor.getHslF(&h, &s, &l);
  const bool achromatic = (h < 0.0f || s < 0.05f);
  if (isEffectiveDark()) {
    return achromatic
               ? QColor(QStringLiteral("#f1f1f4"))
               : QColor::fromHslF(h, qBound(0.25f, s * 0.70f, 0.85f), 0.90f);
  }
  return achromatic
             ? QColor(QStringLiteral("#1c1c21"))
             : QColor::fromHslF(h, qBound(0.30f, s * 0.75f, 0.80f), 0.18f);
}

QColor AppSettings::onPrimary() const {
  if (relativeLuminance(m_accentColor) > 0.35) {
    float h = 0.0f, s = 0.0f, l = 0.0f;
    m_accentColor.getHslF(&h, &s, &l);
    if (h < 0.0f || s < 0.05f) {
      return QColor(QStringLiteral("#111114"));
    }
    return QColor::fromHslF(h, qMin(s, 0.45f), 0.10f);
  }
  return QColor(QStringLiteral("#ffffff"));
}

QColor AppSettings::surfaceColor() const { return surfaceContainerLow(); }

QColor AppSettings::surfaceAltColor() const { return surfaceContainer(); }

QColor AppSettings::inputColor() const { return surfaceContainerHigh(); }

QColor AppSettings::borderColor() const {
  if (!isEffectiveDark()) {
    if (m_customBgColor.isEmpty())
      return QColor(QStringLiteral("#cbd5e1"));
    QColor bg = bgColor();
    float h = 0.0f, s = 0.0f, l = 0.0f;
    bg.getHslF(&h, &s, &l);
    if (h < 0.0f) {
      h = 0.0f;
      s = 0.0f;
    }
    return QColor::fromHslF(h, s * 0.7f, qMax(0.0f, l - 0.15f));
  }

  if (m_themeMode == 3 || bgColor() == QColor(QStringLiteral("#000000"))) {
    return QColor(255, 255, 255, 26);
  }

  if (m_customBgColor.isEmpty()) {
    return QColor(255, 255, 255, 22);
  }

  return QColor(255, 255, 255, 24);
}

QColor AppSettings::textColor() const {
  if (!isEffectiveDark())
    return QColor(QStringLiteral("#0f172a"));
  return QColor(QStringLiteral("#f4f4f5"));
}

QColor AppSettings::textSecColor() const {
  if (!isEffectiveDark())
    return QColor(QStringLiteral("#475569"));
  return QColor(QStringLiteral("#a1a1aa"));
}

QColor AppSettings::textTerColor() const {
  if (!isEffectiveDark())
    return QColor(QStringLiteral("#94a3b8"));
  return QColor(QStringLiteral("#71717a"));
}

void AppSettings::setSidebarCollapsed(bool collapsed) {
  if (m_sidebarCollapsed == collapsed)
    return;
  m_sidebarCollapsed = collapsed;
  m_settings.setValue(QStringLiteral("appearance/sidebarCollapsed"), collapsed);
  emit sidebarCollapsedChanged();
}

void AppSettings::setDefaultFilter(int filter) {
  if (m_defaultFilter == filter)
    return;
  m_defaultFilter = filter;
  m_settings.setValue(QStringLiteral("appearance/defaultFilter"), filter);
  emit defaultFilterChanged();
}

void AppSettings::setCardRadius(int r) {
  if (m_cardRadius == r)
    return;
  m_cardRadius = r;
  m_settings.setValue(QStringLiteral("appearance/cardRadius"), r);
  emit cardStyleChanged();
}

void AppSettings::setThumbScaleTarget(int s) {
  s = qBound(140, s, 300);
  if (m_thumbScaleTarget == s)
    return;
  m_thumbScaleTarget = s;
  m_settings.setValue(QStringLiteral("appearance/thumbScaleTarget"), s);
  emit cardStyleChanged();
}

void AppSettings::setTitleVisibility(int v) {
  if (m_titleVisibility == v)
    return;
  m_titleVisibility = v;
  m_settings.setValue(QStringLiteral("appearance/titleVisibility"), v);
  emit cardStyleChanged();
}

void AppSettings::setTagPosition(int p) {
  if (m_tagPosition == p)
    return;
  m_tagPosition = p;
  m_settings.setValue(QStringLiteral("appearance/tagPosition"), p);
  emit cardStyleChanged();
}

void AppSettings::setShowYear(bool s) {
  if (m_showYear == s)
    return;
  m_showYear = s;
  m_settings.setValue(QStringLiteral("appearance/showYear"), s);
  emit cardStyleChanged();
}

void AppSettings::setShowGameName(bool s) {
  if (m_showGameName == s)
    return;
  m_showGameName = s;
  m_settings.setValue(QStringLiteral("appearance/showGameName"), s);
  emit cardStyleChanged();
}

void AppSettings::setShowEpicBadge(bool s) {
  if (m_showEpicBadge == s)
    return;
  m_showEpicBadge = s;
  m_settings.setValue(QStringLiteral("appearance/showEpicBadge"), s);
  emit cardStyleChanged();
}

void AppSettings::setLeftClickBehavior(int b) {
  if (m_leftClickBehavior == b)
    return;
  m_leftClickBehavior = b;
  m_settings.setValue(QStringLiteral("behavior/leftClickBehavior"), b);
  emit behaviorChanged();
}

void AppSettings::setMinimizeOnLaunch(bool m) {
  if (m_minimizeOnLaunch == m)
    return;
  m_minimizeOnLaunch = m;
  m_settings.setValue(QStringLiteral("behavior/minimizeOnLaunch"), m);
  emit behaviorChanged();
}

void AppSettings::setShowNavigationHud(bool s) {
  if (m_showNavigationHud == s)
    return;
  m_showNavigationHud = s;
  m_settings.setValue(QStringLiteral("behavior/showNavigationHud"), s);
  emit behaviorChanged();
}

void AppSettings::setDefaultRunnerId(const QString &id) {
  if (m_defaultRunnerId == id)
    return;
  m_defaultRunnerId = id;
  m_settings.setValue(QStringLiteral("defaults/runnerId"), id);
  emit runnerDefaultsChanged();
}

void AppSettings::setDefaultPrefixLocation(const QString &path) {
  if (m_defaultPrefixLocation == path || path.isEmpty())
    return;
  m_defaultPrefixLocation = path;
  QDir().mkpath(path);
  m_settings.setValue(QStringLiteral("defaults/prefixLocation"), path);
  emit pathDefaultsChanged();
}

void AppSettings::setDefaultRunnerLocation(const QString &path) {
  if (m_defaultRunnerLocation == path || path.isEmpty())
    return;
  m_defaultRunnerLocation = path;
  QDir().mkpath(path);
  m_settings.setValue(QStringLiteral("defaults/runnerLocation"), path);
  emit pathDefaultsChanged();
}

void AppSettings::setDefaultEpicInstallLocation(const QString &path) {
  QString clean = path.trimmed();
  if (clean.startsWith(QStringLiteral("file://"))) {
    clean = QUrl(clean).toLocalFile();
  }
  if (m_defaultEpicInstallLocation == clean || clean.isEmpty())
    return;
  m_defaultEpicInstallLocation = clean;
  m_settings.setValue(QStringLiteral("defaults/epicInstallLocation"), clean);
  emit pathDefaultsChanged();
}

void AppSettings::setMangohudDefault(bool v) {
  if (m_mangohudDefault == v)
    return;
  m_mangohudDefault = v;
  m_settings.setValue(QStringLiteral("performance/mangohud"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setGamemodeDefault(bool v) {
  if (m_gamemodeDefault == v)
    return;
  m_gamemodeDefault = v;
  m_settings.setValue(QStringLiteral("performance/gamemode"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setGamescopeDefault(bool v) {
  if (m_gamescopeDefault == v)
    return;
  m_gamescopeDefault = v;
  m_settings.setValue(QStringLiteral("performance/gamescope"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setDefaultGamescopeConfig(const QVariantMap &cfgMap) {
  GamescopeConfig cfg = GamescopeConfig::fromVariantMap(cfgMap);
  cfg.inheritGlobal = false;
  const QVariantMap normalized = cfg.toVariantMap();
  if (m_defaultGamescopeConfig == normalized)
    return;
  m_defaultGamescopeConfig = normalized;
  m_settings.setValue(
      QStringLiteral("performance/gamescopeConfig"),
      QString::fromUtf8(
          QJsonDocument(cfg.toJsonObject()).toJson(QJsonDocument::Compact)));
  emit performanceDefaultsChanged();
}

void AppSettings::resetDefaultGamescopeConfig() {
  GamescopeConfig cfg;
  cfg.inheritGlobal = false;
  setDefaultGamescopeConfig(cfg.toVariantMap());
}

void AppSettings::setDxvkDefault(bool v) {
  if (m_dxvkDefault == v)
    return;
  m_dxvkDefault = v;
  m_settings.setValue(QStringLiteral("performance/dxvk"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setVkd3dDefault(bool v) {
  if (m_vkd3dDefault == v)
    return;
  m_vkd3dDefault = v;
  m_settings.setValue(QStringLiteral("performance/vkd3d"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setEsyncDefault(bool v) {
  if (m_esyncDefault == v)
    return;
  m_esyncDefault = v;
  m_settings.setValue(QStringLiteral("performance/esync"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setFsyncDefault(bool v) {
  if (m_fsyncDefault == v)
    return;
  m_fsyncDefault = v;
  m_settings.setValue(QStringLiteral("performance/fsync"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setNtsyncDefault(bool v) {
  if (m_ntsyncDefault == v)
    return;
  m_ntsyncDefault = v;
  m_settings.setValue(QStringLiteral("performance/ntsync"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setUmuDefault(bool v) {
  if (m_umuDefault == v)
    return;
  m_umuDefault = v;
  m_settings.setValue(QStringLiteral("performance/umu"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setWaylandDriverDefault(bool v) {
  if (m_waylandDriverDefault == v)
    return;
  m_waylandDriverDefault = v;
  m_settings.setValue(QStringLiteral("performance/waylandDriver"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setHdrDefault(bool v) {
  if (m_hdrDefault == v)
    return;
  m_hdrDefault = v;
  m_settings.setValue(QStringLiteral("performance/hdr"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setNvapiDefault(bool v) {
  if (m_nvapiDefault == v)
    return;
  m_nvapiDefault = v;
  m_settings.setValue(QStringLiteral("performance/nvapi"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setFsrDefault(bool v) {
  if (m_fsrDefault == v)
    return;
  m_fsrDefault = v;
  m_settings.setValue(QStringLiteral("performance/fsr"), v);
  emit performanceDefaultsChanged();
}

void AppSettings::setDefaultFsrStrength(int s) {
  s = qBound(0, s, 5);
  if (m_defaultFsrStrength == s)
    return;
  m_defaultFsrStrength = s;
  m_settings.setValue(QStringLiteral("performance/fsrStrength"), s);
  emit performanceDefaultsChanged();
}

void AppSettings::setDefaultGpuSelection(const QString &gpu) {
  const QString trimmed = gpu.trimmed();
  if (m_defaultGpuSelection == trimmed)
    return;
  m_defaultGpuSelection = trimmed;
  m_settings.setValue(QStringLiteral("performance/gpuSelection"), trimmed);
  emit performanceDefaultsChanged();
}

void AppSettings::setPreferX86_64V3Runners(bool v) {
  if (m_preferX86_64V3Runners == v)
    return;
  m_preferX86_64V3Runners = v;
  m_settings.setValue(QStringLiteral("runners/preferX86_64V3"), v);
  emit runnerDefaultsChanged();
}

void AppSettings::setAllowDeleteSteamRunners(bool v) {
  if (m_allowDeleteSteamRunners == v)
    return;
  m_allowDeleteSteamRunners = v;
  m_settings.setValue(QStringLiteral("runners/allowDeleteSteamRunners"), v);
  emit runnerDefaultsChanged();
}

void AppSettings::setDownloadSpeedLimitKBps(int kbps) {
  kbps = qMax(0, kbps);
  if (m_downloadSpeedLimitKBps == kbps)
    return;
  m_downloadSpeedLimitKBps = kbps;
  m_settings.setValue(QStringLiteral("downloads/speedLimitKBps"), kbps);
  emit downloadSettingsChanged();
}

void AppSettings::setMaxConcurrentChunkWorkers(int workers) {
  workers = qBound(1, workers, 16);
  if (m_maxConcurrentChunkWorkers == workers)
    return;
  m_maxConcurrentChunkWorkers = workers;
  m_settings.setValue(QStringLiteral("downloads/maxChunkWorkers"), workers);
  emit downloadSettingsChanged();
}

void AppSettings::setMaxConcurrentGameDownloads(int maxGames) {
  maxGames = qBound(1, maxGames, 4);
  if (m_maxConcurrentGameDownloads == maxGames)
    return;
  m_maxConcurrentGameDownloads = maxGames;
  m_settings.setValue(QStringLiteral("downloads/maxConcurrentGames"), maxGames);
  emit downloadSettingsChanged();
}

void AppSettings::setPauseDownloadsOnGameLaunch(bool pause) {
  if (m_pauseDownloadsOnGameLaunch == pause)
    return;
  m_pauseDownloadsOnGameLaunch = pause;
  m_settings.setValue(QStringLiteral("downloads/pauseOnGameLaunch"), pause);
  emit downloadSettingsChanged();
}

void AppSettings::setAutoUpdateEpicGames(bool enable) {
  if (m_autoUpdateEpicGames == enable)
    return;
  m_autoUpdateEpicGames = enable;
  m_settings.setValue(QStringLiteral("downloads/autoUpdateEpicGames"), enable);
  emit downloadSettingsChanged();
}

void AppSettings::setDefaultDxvkHud(const QString &hud) {
  if (m_defaultDxvkHud == hud)
    return;
  m_defaultDxvkHud = hud;
  m_settings.setValue(QStringLiteral("performance/dxvkHud"), hud);
  emit performanceDefaultsChanged();
}

void AppSettings::setXboxEmulationDefault(bool v) {
  if (m_xboxEmulationDefault == v)
    return;
  m_xboxEmulationDefault = v;
  m_settings.setValue(QStringLiteral("controller/xboxEmulation"), v);
  if (m_db) {
    m_db->setAllGamesXboxEmulationState(v);
  }
  emit controllerDefaultsChanged();
}

void AppSettings::setSteamGridDbApiKey(const QString &key) {
  if (m_steamGridDbApiKey == key)
    return;
  m_steamGridDbApiKey = key.trimmed();
  m_settings.setValue(QStringLiteral("integrations/steamGridDbApiKey"),
                      m_steamGridDbApiKey);
  emit apiSettingsChanged();
}

void AppSettings::setAutoFetchEpicArtwork(bool v) {
  if (m_autoFetchEpicArtwork == v)
    return;
  m_autoFetchEpicArtwork = v;
  m_settings.setValue(QStringLiteral("integrations/autoFetchEpicArtwork"), v);
  emit apiSettingsChanged();
}

void AppSettings::setLogLevel(const QString &level) {
  if (m_logLevel == level)
    return;
  m_logLevel = level;
  m_settings.setValue(QStringLiteral("logging/logLevel"), level);
  emit loggingSettingsChanged();
}

void AppSettings::setEnableWineDebugLogs(bool v) {
  if (m_enableWineDebugLogs == v)
    return;
  m_enableWineDebugLogs = v;
  m_settings.setValue(QStringLiteral("logging/enableWineDebugLogs"), v);
  emit loggingSettingsChanged();
}

} // namespace Tsuki
