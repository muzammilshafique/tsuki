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
#include <QtMath>

namespace Tsuki {

struct GamescopeConfig {
    bool inheritGlobal = true;
    QString windowMode = QStringLiteral("fullscreen"); // "fullscreen", "borderless", "windowed"
    int outputWidth = 0;      // 0 = auto / native
    int outputHeight = 0;     // 0 = auto / native
    int internalWidth = 0;    // 0 = match output
    int internalHeight = 0;   // 0 = match output
    QString filter = QStringLiteral("auto"); // "auto", "fsr", "nis", "sgsr", "pixel", "nearest", "linear"
    int fsrSharpness = 2;     // 0 (sharpest) .. 20 (softest)
    QString scaler = QStringLiteral("auto"); // "auto", "fit", "fill", "stretch", "integer"
    int fpsLimit = 0;         // 0 = unlimited
    int unfocusedFpsLimit = 0; // 0 = off
    bool adaptiveSync = false;
    bool hdrEnabled = false;
    bool forceGrabCursor = false;
    double mouseSensitivity = 1.0;
    bool mangoapp = true;
    QString backend = QStringLiteral("auto"); // "auto", "wayland", "sdl", "drm"
    bool exposeWayland = false;
    QString extraArgs;

    bool operator==(const GamescopeConfig& other) const {
        return inheritGlobal == other.inheritGlobal &&
               windowMode == other.windowMode &&
               outputWidth == other.outputWidth &&
               outputHeight == other.outputHeight &&
               internalWidth == other.internalWidth &&
               internalHeight == other.internalHeight &&
               filter == other.filter &&
               fsrSharpness == other.fsrSharpness &&
               scaler == other.scaler &&
               fpsLimit == other.fpsLimit &&
               unfocusedFpsLimit == other.unfocusedFpsLimit &&
               adaptiveSync == other.adaptiveSync &&
               hdrEnabled == other.hdrEnabled &&
               forceGrabCursor == other.forceGrabCursor &&
               qAbs(mouseSensitivity - other.mouseSensitivity) < 0.001 &&
               mangoapp == other.mangoapp &&
               backend == other.backend &&
               exposeWayland == other.exposeWayland &&
               extraArgs == other.extraArgs;
    }

    bool operator!=(const GamescopeConfig& other) const {
        return !(*this == other);
    }

    static QString sanitizeChoice(const QString& value, const QStringList& allowed, const QString& fallback) {
        const QString trimmed = value.trimmed().toLower();
        return allowed.contains(trimmed) ? trimmed : fallback;
    }

    void normalize() {
        windowMode = sanitizeChoice(windowMode,
                                    {QStringLiteral("fullscreen"), QStringLiteral("borderless"), QStringLiteral("windowed")},
                                    QStringLiteral("fullscreen"));
        filter = sanitizeChoice(filter,
                                {QStringLiteral("auto"), QStringLiteral("fsr"), QStringLiteral("nis"),
                                 QStringLiteral("sgsr"), QStringLiteral("pixel"), QStringLiteral("nearest"),
                                 QStringLiteral("linear")},
                                QStringLiteral("auto"));
        scaler = sanitizeChoice(scaler,
                                {QStringLiteral("auto"), QStringLiteral("fit"), QStringLiteral("fill"),
                                 QStringLiteral("stretch"), QStringLiteral("integer")},
                                QStringLiteral("auto"));
        backend = sanitizeChoice(backend,
                                 {QStringLiteral("auto"), QStringLiteral("wayland"), QStringLiteral("sdl"), QStringLiteral("drm")},
                                 QStringLiteral("auto"));
        outputWidth = qMax(0, outputWidth);
        outputHeight = qMax(0, outputHeight);
        internalWidth = qMax(0, internalWidth);
        internalHeight = qMax(0, internalHeight);
        fsrSharpness = qBound(0, fsrSharpness, 20);
        fpsLimit = qMax(0, fpsLimit);
        unfocusedFpsLimit = qMax(0, unfocusedFpsLimit);
        mouseSensitivity = qRound(qBound(0.1, mouseSensitivity, 5.0) * 100.0) / 100.0;
        extraArgs = extraArgs.trimmed();
    }

    QJsonObject toJsonObject() const {
        QJsonObject obj;
        obj[QStringLiteral("inheritGlobal")] = inheritGlobal;
        obj[QStringLiteral("windowMode")] = windowMode;
        obj[QStringLiteral("outputWidth")] = outputWidth;
        obj[QStringLiteral("outputHeight")] = outputHeight;
        obj[QStringLiteral("internalWidth")] = internalWidth;
        obj[QStringLiteral("internalHeight")] = internalHeight;
        obj[QStringLiteral("filter")] = filter;
        obj[QStringLiteral("fsrSharpness")] = fsrSharpness;
        obj[QStringLiteral("scaler")] = scaler;
        obj[QStringLiteral("fpsLimit")] = fpsLimit;
        obj[QStringLiteral("unfocusedFpsLimit")] = unfocusedFpsLimit;
        obj[QStringLiteral("adaptiveSync")] = adaptiveSync;
        obj[QStringLiteral("hdrEnabled")] = hdrEnabled;
        obj[QStringLiteral("forceGrabCursor")] = forceGrabCursor;
        obj[QStringLiteral("mouseSensitivity")] = mouseSensitivity;
        obj[QStringLiteral("mangoapp")] = mangoapp;
        obj[QStringLiteral("backend")] = backend;
        obj[QStringLiteral("exposeWayland")] = exposeWayland;
        obj[QStringLiteral("extraArgs")] = extraArgs;
        return obj;
    }

    static GamescopeConfig fromJsonObject(const QJsonObject& obj) {
        GamescopeConfig cfg;
        if (obj.isEmpty()) return cfg;
        cfg.inheritGlobal = obj[QStringLiteral("inheritGlobal")].toBool(true);
        cfg.windowMode = obj[QStringLiteral("windowMode")].toString(QStringLiteral("fullscreen"));
        cfg.outputWidth = obj[QStringLiteral("outputWidth")].toInt(0);
        cfg.outputHeight = obj[QStringLiteral("outputHeight")].toInt(0);
        cfg.internalWidth = obj[QStringLiteral("internalWidth")].toInt(0);
        cfg.internalHeight = obj[QStringLiteral("internalHeight")].toInt(0);
        cfg.filter = obj[QStringLiteral("filter")].toString(QStringLiteral("auto"));
        cfg.fsrSharpness = obj[QStringLiteral("fsrSharpness")].toInt(2);
        cfg.scaler = obj[QStringLiteral("scaler")].toString(QStringLiteral("auto"));
        cfg.fpsLimit = obj[QStringLiteral("fpsLimit")].toInt(0);
        cfg.unfocusedFpsLimit = obj[QStringLiteral("unfocusedFpsLimit")].toInt(0);
        cfg.adaptiveSync = obj[QStringLiteral("adaptiveSync")].toBool(false);
        cfg.hdrEnabled = obj[QStringLiteral("hdrEnabled")].toBool(false);
        cfg.forceGrabCursor = obj[QStringLiteral("forceGrabCursor")].toBool(false);
        cfg.mouseSensitivity = obj[QStringLiteral("mouseSensitivity")].toDouble(1.0);
        cfg.mangoapp = obj[QStringLiteral("mangoapp")].toBool(true);
        cfg.backend = obj[QStringLiteral("backend")].toString(QStringLiteral("auto"));
        cfg.exposeWayland = obj[QStringLiteral("exposeWayland")].toBool(false);
        cfg.extraArgs = obj[QStringLiteral("extraArgs")].toString();
        cfg.normalize();
        return cfg;
    }

    QVariantMap toVariantMap() const {
        QVariantMap map;
        map[QStringLiteral("inheritGlobal")] = inheritGlobal;
        map[QStringLiteral("windowMode")] = windowMode;
        map[QStringLiteral("outputWidth")] = outputWidth;
        map[QStringLiteral("outputHeight")] = outputHeight;
        map[QStringLiteral("internalWidth")] = internalWidth;
        map[QStringLiteral("internalHeight")] = internalHeight;
        map[QStringLiteral("filter")] = filter;
        map[QStringLiteral("fsrSharpness")] = fsrSharpness;
        map[QStringLiteral("scaler")] = scaler;
        map[QStringLiteral("fpsLimit")] = fpsLimit;
        map[QStringLiteral("unfocusedFpsLimit")] = unfocusedFpsLimit;
        map[QStringLiteral("adaptiveSync")] = adaptiveSync;
        map[QStringLiteral("hdrEnabled")] = hdrEnabled;
        map[QStringLiteral("forceGrabCursor")] = forceGrabCursor;
        map[QStringLiteral("mouseSensitivity")] = mouseSensitivity;
        map[QStringLiteral("mangoapp")] = mangoapp;
        map[QStringLiteral("backend")] = backend;
        map[QStringLiteral("exposeWayland")] = exposeWayland;
        map[QStringLiteral("extraArgs")] = extraArgs;
        return map;
    }

    static GamescopeConfig fromVariantMap(const QVariantMap& map) {
        GamescopeConfig cfg;
        if (map.isEmpty()) return cfg;
        if (map.contains(QStringLiteral("inheritGlobal")))
            cfg.inheritGlobal = map.value(QStringLiteral("inheritGlobal")).toBool();
        if (map.contains(QStringLiteral("windowMode")))
            cfg.windowMode = map.value(QStringLiteral("windowMode")).toString();
        if (map.contains(QStringLiteral("outputWidth")))
            cfg.outputWidth = map.value(QStringLiteral("outputWidth")).toInt();
        if (map.contains(QStringLiteral("outputHeight")))
            cfg.outputHeight = map.value(QStringLiteral("outputHeight")).toInt();
        if (map.contains(QStringLiteral("internalWidth")))
            cfg.internalWidth = map.value(QStringLiteral("internalWidth")).toInt();
        if (map.contains(QStringLiteral("internalHeight")))
            cfg.internalHeight = map.value(QStringLiteral("internalHeight")).toInt();
        if (map.contains(QStringLiteral("filter")))
            cfg.filter = map.value(QStringLiteral("filter")).toString();
        if (map.contains(QStringLiteral("fsrSharpness")))
            cfg.fsrSharpness = map.value(QStringLiteral("fsrSharpness")).toInt();
        if (map.contains(QStringLiteral("scaler")))
            cfg.scaler = map.value(QStringLiteral("scaler")).toString();
        if (map.contains(QStringLiteral("fpsLimit")))
            cfg.fpsLimit = map.value(QStringLiteral("fpsLimit")).toInt();
        if (map.contains(QStringLiteral("unfocusedFpsLimit")))
            cfg.unfocusedFpsLimit = map.value(QStringLiteral("unfocusedFpsLimit")).toInt();
        if (map.contains(QStringLiteral("adaptiveSync")))
            cfg.adaptiveSync = map.value(QStringLiteral("adaptiveSync")).toBool();
        if (map.contains(QStringLiteral("hdrEnabled")))
            cfg.hdrEnabled = map.value(QStringLiteral("hdrEnabled")).toBool();
        if (map.contains(QStringLiteral("forceGrabCursor")))
            cfg.forceGrabCursor = map.value(QStringLiteral("forceGrabCursor")).toBool();
        if (map.contains(QStringLiteral("mouseSensitivity")))
            cfg.mouseSensitivity = map.value(QStringLiteral("mouseSensitivity")).toDouble();
        if (map.contains(QStringLiteral("mangoapp")))
            cfg.mangoapp = map.value(QStringLiteral("mangoapp")).toBool();
        if (map.contains(QStringLiteral("backend")))
            cfg.backend = map.value(QStringLiteral("backend")).toString();
        if (map.contains(QStringLiteral("exposeWayland")))
            cfg.exposeWayland = map.value(QStringLiteral("exposeWayland")).toBool();
        if (map.contains(QStringLiteral("extraArgs")))
            cfg.extraArgs = map.value(QStringLiteral("extraArgs")).toString();
        cfg.normalize();
        return cfg;
    }
};

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

    QString platform = QStringLiteral("windows"); // "windows" or "linux"
    QString source = QStringLiteral("local");     // "local" or "epic"
    QString epicAppName;
    QString epicNamespace;
    QString epicCatalogItemId;
    QString epicBuildVersion;
    QString epicInstallDir;
    bool epicOfflineMode = false;
    bool epicInPlaceImported = false;
    bool enableEosOverlay = false;
    bool enableEacRuntime = false;
    bool enableBattlEyeRuntime = false;

    bool isNative() const {
        return platform == QStringLiteral("linux");
    }

    bool isEpic() const {
        return source == QStringLiteral("epic") && !epicAppName.isEmpty();
    }

    bool isFavorite = false;
    bool isPinned = false;
    bool isHidden = false;
    QStringList categories;
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
    int ntsyncState = -1;     // -1: Default, 0: Off, 1: On
    int umuState = -1;        // -1: Default, 0: Off, 1: On
    QString umuGameId;
    bool disableProtonfixes = false;
    bool disableMonoGecko = false;
    int waylandDriverState = -1; // -1: Default, 0: Off, 1: On
    int hdrState = -1;        // -1: Default, 0: Off, 1: On
    int nvapiState = -1;      // -1: Default, 0: Off, 1: On
    int fsrState = -1;        // -1: Default, 0: Off, 1: On
    int fsrStrength = 2;      // 0..5
    QString gpuSelection;     // "": Default / Auto, else GPU id/name
    QString dxvkHud;          // "": Default, "none", "fps", "compiler", "devinfo,fps,frametimes", "full"
    bool virtualDesktop = false;
    QString virtualDesktopResolution = QStringLiteral("1920x1080");
    QString preLaunchScript;
    QString postExitScript;
    QString cpuAffinity;
    int processPriority = 0;  // nice level (-20 to 19, 0 = normal)
    int mangohudState = -1;   // -1: Default, 0: Off, 1: On
    int gamemodeState = -1;   // -1: Default, 0: Off, 1: On
    int gamescopeState = -1;  // -1: Default, 0: Off, 1: On
    GamescopeConfig gamescope;
    int xboxEmulationState = 0;  // 0: Off, 1: On

    // Epic prerequisites, selective tags, DLCs, and cloud saves
    QString epicPrereqName;
    QString epicPrereqPath;
    QString epicPrereqArgs;
    QStringList epicPrereqIds;
    bool epicPrereqCompleted = false;
    QStringList epicSelectedInstallTags;
    QStringList epicSelectedDlcs;
    bool epicCloudSavesEnabled = true;
    bool epicAutoSyncCloudSaves = true;
    QString epicCloudSaveFolder;
    QStringList epicCloudIncludeList;
    QStringList epicCloudExcludeList;

    QString launchConfigToJson() const {
        QJsonObject obj;
        obj["environmentVariables"] = QJsonObject::fromVariantMap(environmentVariables);
        obj["dllOverrides"] = QJsonObject::fromVariantMap(dllOverrides);
        obj["dxvkState"] = dxvkState;
        obj["vkd3dState"] = vkd3dState;
        obj["esyncState"] = esyncState;
        obj["fsyncState"] = fsyncState;
        obj["ntsyncState"] = ntsyncState;
        obj["umuState"] = umuState;
        obj["umuGameId"] = umuGameId;
        obj["disableProtonfixes"] = disableProtonfixes;
        obj["disableMonoGecko"] = disableMonoGecko;
        obj["waylandDriverState"] = waylandDriverState;
        obj["hdrState"] = hdrState;
        obj["nvapiState"] = nvapiState;
        obj["fsrState"] = fsrState;
        obj["fsrStrength"] = qBound(0, fsrStrength, 5);
        obj["gpuSelection"] = gpuSelection;
        obj["dxvkHud"] = dxvkHud;
        obj["virtualDesktop"] = virtualDesktop;
        obj["virtualDesktopResolution"] = virtualDesktopResolution;
        obj["preLaunchScript"] = preLaunchScript;
        obj["postExitScript"] = postExitScript;
        obj["cpuAffinity"] = cpuAffinity;
        obj["processPriority"] = processPriority;
        obj["mangohudState"] = mangohudState;
        obj["gamemodeState"] = gamemodeState;
        obj["gamescopeState"] = gamescopeState;
        obj["gamescope"] = gamescope.toJsonObject();
        obj["xboxEmulationState"] = xboxEmulationState;
        obj["epicOfflineMode"] = epicOfflineMode;
        obj["epicInPlaceImported"] = epicInPlaceImported;
        obj["enableEosOverlay"] = enableEosOverlay;
        obj["enableEacRuntime"] = enableEacRuntime;
        obj["enableBattlEyeRuntime"] = enableBattlEyeRuntime;
        obj["epicPrereqName"] = epicPrereqName;
        obj["epicPrereqPath"] = epicPrereqPath;
        obj["epicPrereqArgs"] = epicPrereqArgs;
        obj["epicPrereqIds"] = QJsonArray::fromStringList(epicPrereqIds);
        obj["epicPrereqCompleted"] = epicPrereqCompleted;
        obj["epicSelectedInstallTags"] = QJsonArray::fromStringList(epicSelectedInstallTags);
        obj["epicSelectedDlcs"] = QJsonArray::fromStringList(epicSelectedDlcs);
        obj["epicCloudSavesEnabled"] = epicCloudSavesEnabled;
        obj["epicAutoSyncCloudSaves"] = epicAutoSyncCloudSaves;
        obj["epicCloudSaveFolder"] = epicCloudSaveFolder;
        obj["epicCloudIncludeList"] = QJsonArray::fromStringList(epicCloudIncludeList);
        obj["epicCloudExcludeList"] = QJsonArray::fromStringList(epicCloudExcludeList);
        return QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    }

    void applyLaunchConfigJson(const QString& jsonStr) {
        if (jsonStr.isEmpty()) return;
        QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
        if (!doc.isObject()) return;
        QJsonObject obj = doc.object();
        auto readStringList = [&obj](const char* key) {
            QStringList out;
            const QJsonArray arr = obj[QLatin1String(key)].toArray();
            for (const QJsonValue& v : arr) {
                const QString s = v.toString().trimmed();
                if (!s.isEmpty()) out.append(s);
            }
            return out;
        };
        environmentVariables = obj["environmentVariables"].toObject().toVariantMap();
        dllOverrides = obj["dllOverrides"].toObject().toVariantMap();
        dxvkState = obj["dxvkState"].toInt(-1);
        vkd3dState = obj["vkd3dState"].toInt(-1);
        esyncState = obj["esyncState"].toInt(-1);
        fsyncState = obj["fsyncState"].toInt(-1);
        ntsyncState = obj["ntsyncState"].toInt(-1);
        umuState = obj["umuState"].toInt(-1);
        umuGameId = obj["umuGameId"].toString();
        disableProtonfixes = obj["disableProtonfixes"].toBool(false);
        disableMonoGecko = obj["disableMonoGecko"].toBool(false);
        waylandDriverState = obj["waylandDriverState"].toInt(-1);
        hdrState = obj["hdrState"].toInt(-1);
        nvapiState = obj["nvapiState"].toInt(-1);
        fsrState = obj["fsrState"].toInt(-1);
        fsrStrength = qBound(0, obj["fsrStrength"].toInt(2), 5);
        gpuSelection = obj["gpuSelection"].toString();
        dxvkHud = obj["dxvkHud"].toString();
        virtualDesktop = obj["virtualDesktop"].toBool(false);
        virtualDesktopResolution = obj["virtualDesktopResolution"].toString(QStringLiteral("1920x1080"));
        preLaunchScript = obj["preLaunchScript"].toString();
        postExitScript = obj["postExitScript"].toString();
        cpuAffinity = obj["cpuAffinity"].toString();
        processPriority = obj["processPriority"].toInt(0);
        mangohudState = obj["mangohudState"].toInt(-1);
        gamemodeState = obj["gamemodeState"].toInt(-1);
        gamescopeState = obj["gamescopeState"].toInt(-1);
        if (obj.contains(QStringLiteral("gamescope")) && obj[QStringLiteral("gamescope")].isObject()) {
            gamescope = GamescopeConfig::fromJsonObject(obj[QStringLiteral("gamescope")].toObject());
        } else {
            gamescope = GamescopeConfig{};
        }
        xboxEmulationState = obj["xboxEmulationState"].toInt(0);
        epicOfflineMode = obj["epicOfflineMode"].toBool(false);
        epicInPlaceImported = obj["epicInPlaceImported"].toBool(false);
        enableEosOverlay = obj["enableEosOverlay"].toBool(false);
        enableEacRuntime = obj["enableEacRuntime"].toBool(false);
        enableBattlEyeRuntime = obj["enableBattlEyeRuntime"].toBool(false);
        epicPrereqName = obj["epicPrereqName"].toString();
        epicPrereqPath = obj["epicPrereqPath"].toString();
        epicPrereqArgs = obj["epicPrereqArgs"].toString();
        epicPrereqIds = readStringList("epicPrereqIds");
        epicPrereqCompleted = obj["epicPrereqCompleted"].toBool(false);
        epicSelectedInstallTags = readStringList("epicSelectedInstallTags");
        epicSelectedDlcs = readStringList("epicSelectedDlcs");
        epicCloudSavesEnabled = obj["epicCloudSavesEnabled"].toBool(true);
        epicAutoSyncCloudSaves = obj["epicAutoSyncCloudSaves"].toBool(true);
        epicCloudSaveFolder = obj["epicCloudSaveFolder"].toString();
        epicCloudIncludeList = readStringList("epicCloudIncludeList");
        epicCloudExcludeList = readStringList("epicCloudExcludeList");
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

    QVariantMap toVariantMap(bool isRunning = false,
                             const QString& resolvedRunnerTag = QStringLiteral("WINE"),
                             bool hasUpdate = false) const {
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
        map["isHidden"] = isHidden;
        map["categories"] = categories;
        map["category"] = categories.isEmpty() ? QString() : categories.first();
        map["playtimeSeconds"] = playtimeSeconds;
        map["playtimeFormatted"] = formatPlaytime(playtimeSeconds);
        map["lastPlayedTimestamp"] = lastPlayedTimestamp;
        map["lastPlayedFormatted"] = formatLastPlayed(lastPlayedTimestamp);
        map["addedTimestamp"] = addedTimestamp;
        map["platform"] = platform;
        map["isNative"] = isNative();
        map["source"] = source.isEmpty() ? QStringLiteral("local") : source;
        map["isEpic"] = isEpic();
        map["epicAppName"] = epicAppName;
        map["epicNamespace"] = epicNamespace;
        map["epicCatalogItemId"] = epicCatalogItemId;
        map["epicBuildVersion"] = epicBuildVersion;
        map["epicInstallDir"] = epicInstallDir;
        map["epicOfflineMode"] = epicOfflineMode;
        map["epicInPlaceImported"] = epicInPlaceImported;
        map["enableEosOverlay"] = enableEosOverlay;
        map["enableEacRuntime"] = enableEacRuntime;
        map["enableBattlEyeRuntime"] = enableBattlEyeRuntime;
        map["hasUpdate"] = hasUpdate;
        map["isRunning"] = isRunning;

        const QString effectiveRunnerTag = isNative() ? QStringLiteral("LINUX") : resolvedRunnerTag;
        map["runnerTag"] = effectiveRunnerTag;

        // Type integer for tag coloring (0: Proton/GE, 1: Wine, 2: Custom/Staging, 3: Linux)
        int tagType = 1;
        if (isNative()) {
            tagType = 3;
        } else if (effectiveRunnerTag.contains(QStringLiteral("PROTON"), Qt::CaseInsensitive) ||
                   effectiveRunnerTag.contains(QStringLiteral("CACHYOS"), Qt::CaseInsensitive) ||
                   effectiveRunnerTag.contains(QStringLiteral("SAREK"), Qt::CaseInsensitive)) {
            tagType = 0;
        } else if (effectiveRunnerTag.contains(QStringLiteral("STAGING"), Qt::CaseInsensitive) ||
                   effectiveRunnerTag.contains(QStringLiteral("CUSTOM"), Qt::CaseInsensitive)) {
            tagType = 2;
        }
        map["type"] = tagType;

        map["environmentVariables"] = environmentVariables;
        map["dllOverrides"] = dllOverrides;
        map["dxvkState"] = dxvkState;
        map["vkd3dState"] = vkd3dState;
        map["esyncState"] = esyncState;
        map["fsyncState"] = fsyncState;
        map["ntsyncState"] = ntsyncState;
        map["umuState"] = umuState;
        map["umuGameId"] = umuGameId;
        map["disableProtonfixes"] = disableProtonfixes;
        map["disableMonoGecko"] = disableMonoGecko;
        map["waylandDriverState"] = waylandDriverState;
        map["hdrState"] = hdrState;
        map["nvapiState"] = nvapiState;
        map["fsrState"] = fsrState;
        map["fsrStrength"] = fsrStrength;
        map["gpuSelection"] = gpuSelection;
        map["dxvkHud"] = dxvkHud;
        map["virtualDesktop"] = virtualDesktop;
        map["virtualDesktopResolution"] = virtualDesktopResolution;
        map["preLaunchScript"] = preLaunchScript;
        map["postExitScript"] = postExitScript;
        map["cpuAffinity"] = cpuAffinity;
        map["processPriority"] = processPriority;
        map["mangohudState"] = mangohudState;
        map["gamemodeState"] = gamemodeState;
        map["gamescopeState"] = gamescopeState;
        map["gamescope"] = gamescope.toVariantMap();
        map["xboxEmulationState"] = xboxEmulationState;
        map["epicPrereqName"] = epicPrereqName;
        map["epicPrereqPath"] = epicPrereqPath;
        map["epicPrereqArgs"] = epicPrereqArgs;
        map["epicPrereqIds"] = epicPrereqIds;
        map["epicPrereqCompleted"] = epicPrereqCompleted;
        map["epicSelectedInstallTags"] = epicSelectedInstallTags;
        map["epicSelectedDlcs"] = epicSelectedDlcs;
        map["epicCloudSavesEnabled"] = epicCloudSavesEnabled;
        map["epicAutoSyncCloudSaves"] = epicAutoSyncCloudSaves;
        map["epicCloudSaveFolder"] = epicCloudSaveFolder;
        map["epicCloudIncludeList"] = epicCloudIncludeList;
        map["epicCloudExcludeList"] = epicCloudExcludeList;
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
    QStringList installedPrereqIds;
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
        m["installedPrereqIds"] = installedPrereqIds;
        m["createdAt"] = createdAt;
        m["existsOnDisk"] = QFileInfo::exists(path);
        return m;
    }
};

struct RunnerRecord {
    QString id;
    QString name;
    QString type; // "wine", "wine-staging", "proton", "proton-ge", "proton-cachyos", "proton-sarek", "proton-em", "custom"
    QString version;
    QString path;
    QString binaryPath;
    bool isSystem = false;
    QVariantMap settings;

    bool isProton() const {
        return type == QStringLiteral("proton") ||
               type == QStringLiteral("proton-ge") ||
               type == QStringLiteral("proton-cachyos") ||
               type == QStringLiteral("proton-sarek") ||
               type == QStringLiteral("proton-em") ||
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

struct EpicLibraryItem {
    QString appName;
    QString namespaceId;
    QString catalogItemId;
    QString title;
    QString developer;
    QString description;
    QString coverUrl;
    QString bannerUrl;
    QString logoUrl;
    QString coverPath;
    QString bannerPath;
    QString logoPath;
    qint64 downloadSize = 0;
    qint64 installSize = 0;
    QString buildVersion;
    QString cloudSaveFolder;
    QStringList cloudIncludeList;
    QStringList cloudExcludeList;
    bool isHidden = false;
    qint64 lastSynced = 0;

    static QString formatSize(qint64 bytes) {
        if (bytes <= 0) return QString();
        double b = static_cast<double>(bytes);
        if (b < 1024.0) return QStringLiteral("%1 B").arg(bytes);
        b /= 1024.0;
        if (b < 1024.0) return QStringLiteral("%1 KB").arg(b, 0, 'f', 1);
        b /= 1024.0;
        if (b < 1024.0) return QStringLiteral("%1 MB").arg(b, 0, 'f', 1);
        b /= 1024.0;
        return QStringLiteral("%1 GB").arg(b, 0, 'f', 2);
    }

    QVariantMap toVariantMap(bool isInstalled = false,
                             const QString& installedGameId = QString(),
                             bool hasUpdate = false) const {
        QVariantMap m;
        m["appName"] = appName;
        m["epicAppName"] = appName;
        m["namespaceId"] = namespaceId;
        m["catalogItemId"] = catalogItemId;
        m["title"] = title;
        m["developer"] = developer;
        m["description"] = description;
        m["coverUrl"] = coverUrl;
        m["bannerUrl"] = bannerUrl;
        m["logoUrl"] = logoUrl;
        m["coverPath"] = GameRecord::toFileUrlOrOriginal(!coverPath.isEmpty() ? coverPath : coverUrl);
        m["rawCoverPath"] = coverPath;
        m["bannerPath"] = GameRecord::toFileUrlOrOriginal(!bannerPath.isEmpty() ? bannerPath : bannerUrl);
        m["rawBannerPath"] = bannerPath;
        m["logoPath"] = GameRecord::toFileUrlOrOriginal(!logoPath.isEmpty() ? logoPath : logoUrl);
        m["rawLogoPath"] = logoPath;
        m["downloadSize"] = downloadSize;
        m["installSize"] = installSize;
        m["downloadSizeFormatted"] = formatSize(downloadSize);
        m["installSizeFormatted"] = formatSize(installSize);
        m["buildVersion"] = buildVersion;
        m["cloudSaveFolder"] = cloudSaveFolder;
        m["cloudIncludeList"] = cloudIncludeList;
        m["cloudExcludeList"] = cloudExcludeList;
        m["isHidden"] = isHidden;
        m["lastSynced"] = lastSynced;
        m["isInstalled"] = isInstalled;
        m["installedGameId"] = installedGameId;
        m["hasUpdate"] = hasUpdate;
        m["isEpic"] = true;
        return m;
    }
};

struct EpicDlcItem {
    QString appName;
    QString parentAppName;
    QString namespaceId;
    QString catalogItemId;
    QString title;
    QString description;
    qint64 installSize = 0;
    bool isInstalled = false;

    QVariantMap toVariantMap() const {
        QVariantMap m;
        m["appName"] = appName;
        m["parentAppName"] = parentAppName;
        m["namespaceId"] = namespaceId;
        m["catalogItemId"] = catalogItemId;
        m["title"] = title;
        m["description"] = description;
        m["installSize"] = installSize;
        m["installSizeFormatted"] = EpicLibraryItem::formatSize(installSize);
        m["isInstalled"] = isInstalled;
        return m;
    }
};

struct QueuedDownloadRecord {
    QString id;
    QString kind;       // "epic_install", "epic_update", "epic_verify", "runner", etc.
    QString title;
    QString appName;
    QString payloadJson;
    QString status = QStringLiteral("queued"); // "queued", "active", "paused"
    int sortOrder = 0;
    qint64 createdAt = 0;
};

} // namespace Tsuki

