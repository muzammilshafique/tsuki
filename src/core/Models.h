#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QUrl>
#include <QFileInfo>

namespace Tsuki {

struct GameRecord {
    QString id;
    QString title;
    QString executablePath;
    QString workingDirectory;
    QString launchArguments;
    QString runnerId;
    QString prefixId;

    QString coverPath;
    QString bannerPath;
    QString logoPath;
    QString iconPath;

    QString steamGridAppId;

    bool isFavorite = false;
    bool isPinned = false;
    qint64 playtimeSeconds = 0;
    qint64 lastPlayedTimestamp = 0;
    qint64 addedTimestamp = 0;

    // Per-game launch & performance settings
    QVariantMap environmentVariables;
    QVariantMap dllOverrides;
    int dxvkState = -1;       // -1: Default, 0: Off, 1: On
    int vkd3dState = -1;      // -1: Default, 0: Off, 1: On
    int esyncState = -1;      // -1: Default, 0: Off, 1: On
    int fsyncState = -1;      // -1: Default, 0: Off, 1: On
    QString dxvkHud;          // "": Default, "none", "fps", "compiler", "devinfo,fps,frametimes", "full"
    bool virtualDesktop = false;
    QString virtualDesktopResolution = QStringLiteral("1920x1080");
    QString preLaunchScript;
    QString postExitScript;
    QString cpuAffinity;
    int processPriority = 0;  // nice level (-20 to 19, 0 = normal)
    int mangohudState = -1;   // -1: Default, 0: Off, 1: On
    int gamemodeState = -1;   // -1: Default, 0: Off, 1: On
    QString controllerProfileId;
    int xboxEmulationState = -1; // -1: Default, 0: Off, 1: On

    QString launchConfigToJson() const {
        QJsonObject obj;
        obj["environmentVariables"] = QJsonObject::fromVariantMap(environmentVariables);
        obj["dllOverrides"] = QJsonObject::fromVariantMap(dllOverrides);
        obj["dxvkState"] = dxvkState;
        obj["vkd3dState"] = vkd3dState;
        obj["esyncState"] = esyncState;
        obj["fsyncState"] = fsyncState;
        obj["dxvkHud"] = dxvkHud;
        obj["virtualDesktop"] = virtualDesktop;
        obj["virtualDesktopResolution"] = virtualDesktopResolution;
        obj["preLaunchScript"] = preLaunchScript;
        obj["postExitScript"] = postExitScript;
        obj["cpuAffinity"] = cpuAffinity;
        obj["processPriority"] = processPriority;
        obj["mangohudState"] = mangohudState;
        obj["gamemodeState"] = gamemodeState;
        obj["controllerProfileId"] = controllerProfileId;
        obj["xboxEmulationState"] = xboxEmulationState;
        return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    }

    void applyLaunchConfigJson(const QString& jsonStr) {
        if (jsonStr.isEmpty()) return;
        QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
        if (!doc.isObject()) return;
        QJsonObject obj = doc.object();
        environmentVariables = obj["environmentVariables"].toObject().toVariantMap();
        dllOverrides = obj["dllOverrides"].toObject().toVariantMap();
        dxvkState = obj["dxvkState"].toInt(-1);
        vkd3dState = obj["vkd3dState"].toInt(-1);
        esyncState = obj["esyncState"].toInt(-1);
        fsyncState = obj["fsyncState"].toInt(-1);
        dxvkHud = obj["dxvkHud"].toString();
        virtualDesktop = obj["virtualDesktop"].toBool(false);
        virtualDesktopResolution = obj["virtualDesktopResolution"].toString(QStringLiteral("1920x1080"));
        preLaunchScript = obj["preLaunchScript"].toString();
        postExitScript = obj["postExitScript"].toString();
        cpuAffinity = obj["cpuAffinity"].toString();
        processPriority = obj["processPriority"].toInt(0);
        mangohudState = obj["mangohudState"].toInt(-1);
        gamemodeState = obj["gamemodeState"].toInt(-1);
        controllerProfileId = obj["controllerProfileId"].toString();
        xboxEmulationState = obj["xboxEmulationState"].toInt(-1);
    }

    static QString toFileUrlOrOriginal(const QString& path) {
        if (path.isEmpty()) return QString();
        if (path.startsWith(QStringLiteral("file://")) ||
            path.startsWith(QStringLiteral("qrc:")) ||
            path.startsWith(QStringLiteral("http://")) ||
            path.startsWith(QStringLiteral("https://")) ||
            path.startsWith(QStringLiteral("data:"))) {
            return path;
        }
        return QUrl::fromLocalFile(path).toString();
    }

    static QString formatPlaytime(qint64 seconds) {
        if (seconds <= 0) return QStringLiteral("Never played");
        if (seconds < 60) return QStringLiteral("< 1 min");
        qint64 mins = seconds / 60;
        if (mins < 60) return QStringLiteral("%1m").arg(mins);
        double hours = static_cast<double>(seconds) / 3600.0;
        return QStringLiteral("%1h").arg(hours, 0, 'f', 1);
    }

    static QString formatLastPlayed(qint64 epochSecs) {
        if (epochSecs <= 0) return QStringLiteral("Never");
        QDateTime dt = QDateTime::fromSecsSinceEpoch(epochSecs);
        return dt.toString(QStringLiteral("MMM d, yyyy"));
    }

    QVariantMap toVariantMap(bool isRunning = false, const QString& resolvedRunnerTag = QStringLiteral("WINE")) const {
        QVariantMap map;
        map["id"] = id;
        map["gameId"] = id;
        map["tmdbId"] = id; // Compatibility alias for Yoru-style QML bindings
        map["title"] = title;
        map["executablePath"] = executablePath;
        map["workingDirectory"] = workingDirectory;
        map["launchArguments"] = launchArguments;
        map["runnerId"] = runnerId;
        map["prefixId"] = prefixId;
        map["coverPath"] = toFileUrlOrOriginal(coverPath);
        map["rawCoverPath"] = coverPath;
        map["bannerPath"] = toFileUrlOrOriginal(bannerPath);
        map["rawBannerPath"] = bannerPath;
        map["logoPath"] = toFileUrlOrOriginal(logoPath);
        map["rawLogoPath"] = logoPath;
        map["iconPath"] = toFileUrlOrOriginal(iconPath);
        map["rawIconPath"] = iconPath;
        map["year"] = formatPlaytime(playtimeSeconds);
        map["steamGridAppId"] = steamGridAppId;
        map["isFavorite"] = isFavorite;
        map["isPinned"] = isPinned;
        map["playtimeSeconds"] = playtimeSeconds;
        map["playtimeFormatted"] = formatPlaytime(playtimeSeconds);
        map["lastPlayedTimestamp"] = lastPlayedTimestamp;
        map["lastPlayedFormatted"] = formatLastPlayed(lastPlayedTimestamp);
        map["addedTimestamp"] = addedTimestamp;
        map["isRunning"] = isRunning;
        map["runnerTag"] = resolvedRunnerTag;

        // Type integer for tag coloring (0: Proton/GE, 1: Wine, 2: Custom/Staging)
        int tagType = 1;
        if (resolvedRunnerTag.contains(QStringLiteral("PROTON"), Qt::CaseInsensitive)) tagType = 0;
        else if (resolvedRunnerTag.contains(QStringLiteral("STAGING"), Qt::CaseInsensitive) ||
                 resolvedRunnerTag.contains(QStringLiteral("CUSTOM"), Qt::CaseInsensitive)) tagType = 2;
        map["type"] = tagType;

        map["environmentVariables"] = environmentVariables;
        map["dllOverrides"] = dllOverrides;
        map["dxvkState"] = dxvkState;
        map["vkd3dState"] = vkd3dState;
        map["esyncState"] = esyncState;
        map["fsyncState"] = fsyncState;
        map["dxvkHud"] = dxvkHud;
        map["virtualDesktop"] = virtualDesktop;
        map["virtualDesktopResolution"] = virtualDesktopResolution;
        map["preLaunchScript"] = preLaunchScript;
        map["postExitScript"] = postExitScript;
        map["cpuAffinity"] = cpuAffinity;
        map["processPriority"] = processPriority;
        map["mangohudState"] = mangohudState;
        map["gamemodeState"] = gamemodeState;
        map["controllerProfileId"] = controllerProfileId;
        map["xboxEmulationState"] = xboxEmulationState;
        return map;
    }
};

struct PrefixRecord {
    QString id;
    QString name;
    QString path;
    QString arch = QStringLiteral("win64");          // "win64" or "win32"
    QString windowsVersion = QStringLiteral("win10"); // "win11", "win10", "win7"
    QString runnerId;
    bool dxvkInstalled = false;
    bool vkd3dInstalled = false;
    QVariantMap dllOverrides;
    QStringList installedWinetricks;
    qint64 createdAt = 0;

    QVariantMap toVariantMap() const {
        QVariantMap m;
        m["id"] = id;
        m["name"] = name;
        m["path"] = path;
        m["arch"] = arch;
        m["windowsVersion"] = windowsVersion;
        m["runnerId"] = runnerId;
        m["dxvkInstalled"] = dxvkInstalled;
        m["vkd3dInstalled"] = vkd3dInstalled;
        m["dllOverrides"] = dllOverrides;
        m["installedWinetricks"] = installedWinetricks;
        m["createdAt"] = createdAt;
        m["existsOnDisk"] = QFileInfo::exists(path);
        return m;
    }
};

struct RunnerRecord {
    QString id;
    QString name;
    QString type; // "wine", "wine-staging", "proton", "proton-ge", "custom"
    QString version;
    QString path;
    QString binaryPath;
    bool isSystem = false;
    QVariantMap settings;

    bool isProton() const {
        return type == QStringLiteral("proton") ||
               type == QStringLiteral("proton-ge") ||
               binaryPath.endsWith(QStringLiteral("/proton"));
    }

    QVariantMap toVariantMap() const {
        QVariantMap m;
        m["id"] = id;
        m["name"] = name;
        m["type"] = type;
        m["version"] = version;
        m["path"] = path;
        m["binaryPath"] = binaryPath;
        m["isSystem"] = isSystem;
        m["isProton"] = isProton();
        m["settings"] = settings;
        m["existsOnDisk"] = QFileInfo::exists(binaryPath);
        return m;
    }
};

struct ControllerProfileRecord {
    QString id;
    QString name;
    bool xboxEmulation = true;
    int deadzone = 4000;
    QVariantMap buttonMappings;

    static QVariantMap defaultXboxMappings() {
        QVariantMap m;
        m["a"] = QStringLiteral("BTN_SOUTH");
        m["b"] = QStringLiteral("BTN_EAST");
        m["x"] = QStringLiteral("BTN_WEST");
        m["y"] = QStringLiteral("BTN_NORTH");
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

    QVariantMap toVariantMap() const {
        QVariantMap m;
        m["id"] = id;
        m["name"] = name;
        m["xboxEmulation"] = xboxEmulation;
        m["deadzone"] = deadzone;
        m["buttonMappings"] = buttonMappings.isEmpty() ? defaultXboxMappings() : buttonMappings;
        return m;
    }
};

} // namespace Tsuki

