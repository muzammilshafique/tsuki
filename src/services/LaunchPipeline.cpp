#include "LaunchPipeline.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QPointer>
#include <QQueue>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QUuid>
#include <signal.h>
#include <unistd.h>

namespace Tsuki {

namespace {

/// Collect all same-UID descendant PIDs under rootPid via a single /proc stat pass.
QList<qint64> collectDescendantPids(qint64 rootPid) {
    QList<qint64> descendants;
    if (rootPid <= 1) return descendants;

    const qint64 selfPid = static_cast<qint64>(::getpid());
    const uint myUid = static_cast<uint>(::getuid());
    QHash<qint64, QList<qint64>> childrenByParent;

    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString& name : entries) {
        bool ok = false;
        const qint64 pid = name.toLongLong(&ok);
        if (!ok || pid <= 1 || pid == selfPid) continue;

        const QString statPath = QStringLiteral("/proc/%1/stat").arg(pid);
        QFileInfo info(statPath);
        if (!info.exists() || info.ownerId() != myUid) continue;

        QFile f(statPath);
        if (!f.open(QIODevice::ReadOnly)) continue;
        const QByteArray data = f.readAll();
        const int rparen = data.lastIndexOf(')');
        if (rparen < 0) continue;

        const QList<QByteArray> fields = data.mid(rparen + 1).trimmed().split(' ');
        if (fields.size() < 2) continue;
        bool ppidOk = false;
        const qint64 ppid = fields.at(1).toLongLong(&ppidOk);
        if (ppidOk && ppid > 1) {
            childrenByParent[ppid].append(pid);
        }
    }

    QSet<qint64> seen;
    QQueue<qint64> queue;
    seen.insert(rootPid);
    queue.enqueue(rootPid);
    while (!queue.isEmpty()) {
        const qint64 current = queue.dequeue();
        const QList<qint64> children = childrenByParent.value(current);
        for (qint64 child : children) {
            if (!seen.contains(child)) {
                seen.insert(child);
                descendants.append(child);
                queue.enqueue(child);
            }
        }
    }
    return descendants;
}

/// Find same-UID processes carrying TSUKI_SESSION_ID=<sessionToken> (e.g. detached gamescopereaper children).
QList<qint64> collectTaggedSessionPids(const QString& sessionToken) {
    QList<qint64> matched;
    if (sessionToken.isEmpty()) return matched;

    const qint64 selfPid = static_cast<qint64>(::getpid());
    const uint myUid = static_cast<uint>(::getuid());
    const QByteArray targetEntry = QByteArray("TSUKI_SESSION_ID=") + sessionToken.toUtf8();

    const QStringList entries = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString& name : entries) {
        bool ok = false;
        const qint64 pid = name.toLongLong(&ok);
        if (!ok || pid <= 1 || pid == selfPid) continue;

        const QString envPath = QStringLiteral("/proc/%1/environ").arg(pid);
        QFileInfo info(envPath);
        if (!info.exists() || info.ownerId() != myUid) continue;

        QFile f(envPath);
        if (!f.open(QIODevice::ReadOnly)) continue;
        const QList<QByteArray> vars = f.readAll().split('\0');
        if (vars.contains(targetEntry)) {
            matched.append(pid);
        }
    }
    return matched;
}

/// Signal the session process group, descendant tree, and any detached session-tagged processes.
void signalSessionProcesses(qint64 rootPid, const QString& sessionToken, int sig) {
    const QList<qint64> descendants = collectDescendantPids(rootPid);
    const QList<qint64> tagged = collectTaggedSessionPids(sessionToken);
    const qint64 selfPid = static_cast<qint64>(::getpid());

    QSet<qint64> signaled;
    for (int i = descendants.size() - 1; i >= 0; --i) {
        const qint64 p = descendants.at(i);
        if (p > 1 && p != selfPid && !signaled.contains(p)) {
            ::kill(static_cast<pid_t>(p), sig);
            signaled.insert(p);
        }
    }
    for (qint64 p : tagged) {
        if (p > 1 && p != selfPid && !signaled.contains(p)) {
            ::kill(static_cast<pid_t>(p), sig);
            signaled.insert(p);
        }
    }
    if (rootPid > 1 && rootPid != selfPid) {
        ::kill(-static_cast<pid_t>(rootPid), sig);
        if (!signaled.contains(rootPid)) {
            ::kill(static_cast<pid_t>(rootPid), sig);
        }
    }
}

} // namespace

LaunchPipeline::LaunchPipeline(DatabaseManager* db,
                               AppSettings* settings,
                               RunnerManager* runnerMgr,
                               PrefixManager* prefixMgr,
                               ControllerManager* controllerMgr,
                               DiagnosticsManager* diagMgr,
                               QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_runnerMgr(runnerMgr)
    , m_prefixMgr(prefixMgr)
    , m_controllerMgr(controllerMgr)
    , m_diagMgr(diagMgr)
{
}

LaunchPipeline::~LaunchPipeline() {
    stopAllGames();
}

static QStringList buildHostPrefixWrappers(const GameRecord& game, bool useGamemode) {
    QStringList fullCmd;
    if (!game.cpuAffinity.trimmed().isEmpty()) {
        const QString tasksetBin = QStandardPaths::findExecutable(QStringLiteral("taskset"));
        if (!tasksetBin.isEmpty()) {
            fullCmd << tasksetBin << QStringLiteral("-c") << game.cpuAffinity.trimmed();
        }
    }
    if (game.processPriority != 0) {
        const QString niceBin = QStandardPaths::findExecutable(QStringLiteral("nice"));
        if (!niceBin.isEmpty()) {
            fullCmd << niceBin << QStringLiteral("-n") << QString::number(qBound(-20, game.processPriority, 19));
        }
    }
    if (useGamemode) {
        const QString gmBin = QStandardPaths::findExecutable(QStringLiteral("gamemoderun"));
        if (!gmBin.isEmpty()) {
            fullCmd << gmBin;
        }
    }
    return fullCmd;
}

static QStringList buildExecutionWrappers(const GameRecord& game,
                                          bool useGamemode,
                                          bool useMangohud,
                                          bool useGamescope,
                                          const GamescopeConfig& gsCfg)
{
    QStringList fullCmd = buildHostPrefixWrappers(game, useGamemode);

    if (useGamescope) {
        const QString gsBin = QStandardPaths::findExecutable(QStringLiteral("gamescope"));
        if (!gsBin.isEmpty()) {
            fullCmd << gsBin;
            fullCmd.append(LaunchPipeline::buildGamescopeArguments(gsCfg, useMangohud));
            fullCmd << QStringLiteral("--");
        }
        if (useMangohud && !gsCfg.mangoapp) {
            const QString mhBin = QStandardPaths::findExecutable(QStringLiteral("mangohud"));
            if (!mhBin.isEmpty()) {
                fullCmd << mhBin;
            }
        }
    } else if (useMangohud) {
        const QString mhBin = QStandardPaths::findExecutable(QStringLiteral("mangohud"));
        if (!mhBin.isEmpty()) {
            fullCmd << mhBin;
        }
    }

    return fullCmd;
}

bool LaunchPipeline::isGamescopeEnabled(const GameRecord& game) const {
    return (game.gamescopeState == -1) ? m_settings->gamescopeDefault() : (game.gamescopeState == 1);
}

GamescopeConfig LaunchPipeline::resolveEffectiveGamescopeConfig(const GameRecord& game) const {
    if (game.gamescope.inheritGlobal) {
        GamescopeConfig cfg = GamescopeConfig::fromVariantMap(m_settings->defaultGamescopeConfig());
        cfg.inheritGlobal = true;
        return cfg;
    }
    GamescopeConfig cfg = game.gamescope;
    cfg.normalize();
    return cfg;
}

QStringList LaunchPipeline::buildGamescopeArguments(const GamescopeConfig& rawCfg, bool useMangohud) {
    GamescopeConfig cfg = rawCfg;
    cfg.normalize();

    QStringList args;
    if (cfg.windowMode == QStringLiteral("fullscreen")) {
        args << QStringLiteral("-f");
    } else if (cfg.windowMode == QStringLiteral("borderless")) {
        args << QStringLiteral("-b");
    }

    if (cfg.outputWidth > 0 && cfg.outputHeight > 0) {
        args << QStringLiteral("-W") << QString::number(cfg.outputWidth)
             << QStringLiteral("-H") << QString::number(cfg.outputHeight);
    }
    if (cfg.internalWidth > 0 && cfg.internalHeight > 0) {
        args << QStringLiteral("-w") << QString::number(cfg.internalWidth)
             << QStringLiteral("-h") << QString::number(cfg.internalHeight);
    }

    if (cfg.filter != QStringLiteral("auto")) {
        args << QStringLiteral("-F") << cfg.filter;
        if (cfg.filter == QStringLiteral("fsr") ||
            cfg.filter == QStringLiteral("nis") ||
            cfg.filter == QStringLiteral("sgsr")) {
            args << QStringLiteral("--fsr-sharpness") << QString::number(cfg.fsrSharpness);
        }
    }

    if (cfg.scaler != QStringLiteral("auto")) {
        args << QStringLiteral("-S") << cfg.scaler;
    }

    if (cfg.fpsLimit > 0) {
        args << QStringLiteral("-r") << QString::number(cfg.fpsLimit);
    }
    if (cfg.unfocusedFpsLimit > 0) {
        args << QStringLiteral("-o") << QString::number(cfg.unfocusedFpsLimit);
    }
    if (cfg.adaptiveSync) {
        args << QStringLiteral("--adaptive-sync");
    }
    if (cfg.hdrEnabled) {
        args << QStringLiteral("--hdr-enabled");
    }
    if (cfg.forceGrabCursor) {
        args << QStringLiteral("--force-grab-cursor");
    }
    if (qAbs(cfg.mouseSensitivity - 1.0) >= 0.05) {
        args << QStringLiteral("-s") << QString::number(cfg.mouseSensitivity, 'g', 3);
    }
    if (useMangohud && cfg.mangoapp) {
        args << QStringLiteral("--mangoapp");
    }
    if (cfg.backend != QStringLiteral("auto")) {
        args << QStringLiteral("--backend") << cfg.backend;
    }
    if (cfg.exposeWayland) {
        args << QStringLiteral("--expose-wayland");
    }
    if (!cfg.extraArgs.isEmpty()) {
        const QStringList extraTokens = QProcess::splitCommand(cfg.extraArgs);
        for (const QString& tok : extraTokens) {
            // Avoid premature `--` terminator before Tsuki appends `-- <game>`
            if (!tok.isEmpty() && tok != QStringLiteral("--")) {
                args << tok;
            }
        }
    }
    return args;
}

QString LaunchPipeline::formatGamescopePreview(const QVariantMap& cfgMap,
                                                bool useMangohud,
                                                const QString& targetCommand) const
{
    const GamescopeConfig cfg = GamescopeConfig::fromVariantMap(cfgMap);
    QStringList parts;
    parts << QStringLiteral("gamescope");
    parts.append(buildGamescopeArguments(cfg, useMangohud));
    parts << QStringLiteral("--");
    parts << (targetCommand.trimmed().isEmpty() ? QStringLiteral("<game>") : targetCommand.trimmed());
    return parts.join(QLatin1Char(' '));
}

LaunchPlan LaunchPipeline::buildLaunchPlan(const GameRecord& game,
                                           const RunnerRecord& runner,
                                           const PrefixRecord& prefix) const
{
    LaunchPlan plan;
    plan.prefixPath = prefix.path;
    plan.runnerName = runner.name;
    plan.workingDirectory = game.workingDirectory.trimmed().isEmpty()
                                ? QFileInfo(game.executablePath).absolutePath()
                                : game.workingDirectory.trimmed();

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WINEPREFIX"), prefix.path);
    env.insert(QStringLiteral("WINEARCH"), prefix.arch.isEmpty() ? QStringLiteral("win64") : prefix.arch);
    env.insert(QStringLiteral("WINEDEBUG"), m_settings->enableWineDebugLogs() ? QStringLiteral("+err,+warn") : QStringLiteral("-all"));

    // Resolve tri-state toggles (-1: global default, 0: off, 1: on)
    const bool useDxvk = (game.dxvkState == -1) ? m_settings->dxvkDefault() : (game.dxvkState == 1);
    const bool useVkd3d = (game.vkd3dState == -1) ? m_settings->vkd3dDefault() : (game.vkd3dState == 1);
    const bool useEsync = (game.esyncState == -1) ? m_settings->esyncDefault() : (game.esyncState == 1);
    const bool useFsync = (game.fsyncState == -1) ? m_settings->fsyncDefault() : (game.fsyncState == 1);
    const bool useMangohud = (game.mangohudState == -1) ? m_settings->mangohudDefault() : (game.mangohudState == 1);
    const bool useGamemode = (game.gamemodeState == -1) ? m_settings->gamemodeDefault() : (game.gamemodeState == 1);
    const bool useGamescope = isGamescopeEnabled(game);
    const GamescopeConfig gsCfg = resolveEffectiveGamescopeConfig(game);
    const bool useMangoapp = useGamescope && useMangohud && gsCfg.mangoapp;
    plan.useXboxEmulation = (game.xboxEmulationState == 1);
    plan.usesGamescope = useGamescope;

    // Esync & Fsync
    env.insert(QStringLiteral("WINEESYNC"), useEsync ? QStringLiteral("1") : QStringLiteral("0"));
    env.insert(QStringLiteral("WINEFSYNC"), useFsync ? QStringLiteral("1") : QStringLiteral("0"));
    env.insert(QStringLiteral("PROTON_NO_ESYNC"), useEsync ? QStringLiteral("0") : QStringLiteral("1"));
    env.insert(QStringLiteral("PROTON_NO_FSYNC"), useFsync ? QStringLiteral("0") : QStringLiteral("1"));
    if (!useDxvk) {
        env.insert(QStringLiteral("PROTON_USE_WINED3D"), QStringLiteral("1"));
    }

    // DXVK HUD
    const QString hud = game.dxvkHud.isEmpty() ? m_settings->defaultDxvkHud() : game.dxvkHud;
    if (!hud.isEmpty() && hud != QStringLiteral("none")) {
        env.insert(QStringLiteral("DXVK_HUD"), hud);
    }

    // DLL Overrides (Prefix + Per-Game + DXVK/VKD3D)
    QVariantMap mergedOverrides = prefix.dllOverrides;
    if (useDxvk) {
        mergedOverrides[QStringLiteral("d3d9")] = QStringLiteral("n,b");
        mergedOverrides[QStringLiteral("d3d10core")] = QStringLiteral("n,b");
        mergedOverrides[QStringLiteral("d3d11")] = QStringLiteral("n,b");
        mergedOverrides[QStringLiteral("dxgi")] = QStringLiteral("n,b");
    } else {
        mergedOverrides[QStringLiteral("d3d9")] = QStringLiteral("b");
        mergedOverrides[QStringLiteral("d3d10core")] = QStringLiteral("b");
        mergedOverrides[QStringLiteral("d3d11")] = QStringLiteral("b");
        mergedOverrides[QStringLiteral("dxgi")] = QStringLiteral("b");
    }
    if (useVkd3d) {
        mergedOverrides[QStringLiteral("d3d12")] = QStringLiteral("n,b");
        mergedOverrides[QStringLiteral("d3d12core")] = QStringLiteral("n,b");
    }
    for (auto it = game.dllOverrides.constBegin(); it != game.dllOverrides.constEnd(); ++it) {
        mergedOverrides.insert(it.key(), it.value());
    }
    QStringList overrideParts;
    overrideParts << QStringLiteral("mscoree,mshtml=");
    for (auto it = mergedOverrides.constBegin(); it != mergedOverrides.constEnd(); ++it) {
        overrideParts << QStringLiteral("%1=%2").arg(it.key(), it.value().toString());
    }
    env.insert(QStringLiteral("WINEDLLOVERRIDES"), overrideParts.join(QLatin1Char(';')));

    // Standalone Proton environment variables (no Steam client required)
    if (runner.isProton()) {
        env.insert(QStringLiteral("STEAM_COMPAT_DATA_PATH"), prefix.path);
        QString steamClientPath = QDir::homePath() + QStringLiteral("/.local/share/Steam");
        if (!QDir(steamClientPath).exists()) {
            steamClientPath = QDir::homePath() + QStringLiteral("/.steam/steam");
        }
        if (!QDir(steamClientPath).exists()) {
            steamClientPath = AppSettings::dataDir();
        }
        env.insert(QStringLiteral("STEAM_COMPAT_CLIENT_INSTALL_PATH"), steamClientPath);
        env.insert(QStringLiteral("SteamAppId"), QStringLiteral("0"));
        env.insert(QStringLiteral("SteamGameId"), QStringLiteral("0"));
        env.insert(QStringLiteral("ULWGL_ID"), QStringLiteral("tsuki-") + game.id);
    }

    // Controller SDL config injection
    if (plan.useXboxEmulation) {
        const QString sdlCfg = m_controllerMgr->buildSdlGameControllerConfig();
        if (!sdlCfg.isEmpty()) {
            env.insert(QStringLiteral("SDL_GAMECONTROLLERCONFIG"), sdlCfg);
        }
        env.insert(QStringLiteral("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"), QStringLiteral("1"));
    }

    // Runner-specific environment settings
    for (auto it = runner.settings.constBegin(); it != runner.settings.constEnd(); ++it) {
        if (!it.key().isEmpty()) {
            env.insert(it.key(), it.value().toString());
        }
    }

    if (useGamescope && gsCfg.hdrEnabled) {
        env.insert(QStringLiteral("DXVK_HDR"), QStringLiteral("1"));
    }

    // Per-game custom environment variables
    for (auto it = game.environmentVariables.constBegin(); it != game.environmentVariables.constEnd(); ++it) {
        if (!it.key().isEmpty()) {
            env.insert(it.key(), it.value().toString());
        }
    }

    if (useMangohud && !useMangoapp) {
        env.insert(QStringLiteral("MANGOHUD"), QStringLiteral("1"));
    }

    // Build wrapper chain: [taskset] -> [nice] -> [gamemoderun] -> [gamescope flags --] -> [mangohud?] -> [wine/proton] -> [virtual desktop?] -> [exe] [args]
    QStringList fullCmd = buildExecutionWrappers(game, useGamemode, useMangohud, useGamescope, gsCfg);

    if (runner.isProton()) {
        fullCmd << runner.binaryPath << QStringLiteral("waitforexitandrun");
        if (game.virtualDesktop && !useGamescope) {
            const QString res = game.virtualDesktopResolution.isEmpty() ? QStringLiteral("1920x1080") : game.virtualDesktopResolution;
            fullCmd << QStringLiteral("explorer") << QStringLiteral("/desktop=Tsuki,%1").arg(res);
        }
        fullCmd << game.executablePath;
    } else {
        fullCmd << runner.binaryPath;
        if (game.virtualDesktop && !useGamescope) {
            const QString res = game.virtualDesktopResolution.isEmpty() ? QStringLiteral("1920x1080") : game.virtualDesktopResolution;
            fullCmd << QStringLiteral("explorer") << QStringLiteral("/desktop=Tsuki,%1").arg(res);
        }
        fullCmd << game.executablePath;
    }

    if (!game.launchArguments.trimmed().isEmpty()) {
        fullCmd.append(QProcess::splitCommand(game.launchArguments.trimmed()));
    }

    plan.program = fullCmd.takeFirst();
    plan.arguments = fullCmd;
    plan.environment = env;
    return plan;
}

LaunchPlan LaunchPipeline::buildNativeLaunchPlan(const GameRecord& game) const {
    LaunchPlan plan;
    plan.prefixPath.clear();
    plan.runnerName = QStringLiteral("Native Linux");
    plan.workingDirectory = game.workingDirectory.trimmed().isEmpty()
                                ? QFileInfo(game.executablePath).absolutePath()
                                : game.workingDirectory.trimmed();

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();

    const bool useMangohud = (game.mangohudState == -1) ? m_settings->mangohudDefault() : (game.mangohudState == 1);
    const bool useGamemode = (game.gamemodeState == -1) ? m_settings->gamemodeDefault() : (game.gamemodeState == 1);
    const bool useGamescope = isGamescopeEnabled(game);
    const GamescopeConfig gsCfg = resolveEffectiveGamescopeConfig(game);
    const bool useMangoapp = useGamescope && useMangohud && gsCfg.mangoapp;
    plan.useXboxEmulation = (game.xboxEmulationState == 1);
    plan.usesGamescope = useGamescope;

    if (plan.useXboxEmulation) {
        const QString sdlCfg = m_controllerMgr->buildSdlGameControllerConfig();
        if (!sdlCfg.isEmpty()) {
            env.insert(QStringLiteral("SDL_GAMECONTROLLERCONFIG"), sdlCfg);
        }
        env.insert(QStringLiteral("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"), QStringLiteral("1"));
    }

    if (useMangohud && !useMangoapp) {
        env.insert(QStringLiteral("MANGOHUD"), QStringLiteral("1"));
    }

    // Per-game custom environment variables
    for (auto it = game.environmentVariables.constBegin(); it != game.environmentVariables.constEnd(); ++it) {
        if (!it.key().isEmpty()) {
            env.insert(it.key(), it.value().toString());
        }
    }

    QStringList fullCmd = buildExecutionWrappers(game, useGamemode, useMangohud, useGamescope, gsCfg);

    QFileInfo exeFi(game.executablePath);
    if (exeFi.suffix().compare(QStringLiteral("sh"), Qt::CaseInsensitive) == 0 && !exeFi.isExecutable()) {
        fullCmd << QStringLiteral("/bin/sh") << game.executablePath;
    } else {
        fullCmd << game.executablePath;
    }

    if (!game.launchArguments.trimmed().isEmpty()) {
        fullCmd.append(QProcess::splitCommand(game.launchArguments.trimmed()));
    }

    plan.program = fullCmd.takeFirst();
    plan.arguments = fullCmd;
    plan.environment = env;
    return plan;
}

void LaunchPipeline::executeScript(const QString& scriptPathOrCmd,
                                   const QString& workingDir,
                                   const QProcessEnvironment& env,
                                   const QString& gameId)
{
    const QString trimmed = scriptPathOrCmd.trimmed();
    if (trimmed.isEmpty()) return;

    m_diagMgr->appendGameLog(gameId, QStringLiteral("[Tsuki] Executing script: %1\n").arg(trimmed));
    QProcess proc;
    proc.setWorkingDirectory(workingDir);
    proc.setProcessEnvironment(env);
    proc.start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), trimmed});
    proc.waitForFinished(10000);
    const QString out = QString::fromUtf8(proc.readAllStandardOutput() + proc.readAllStandardError());
    if (!out.isEmpty()) {
        m_diagMgr->appendGameLog(gameId, out + QLatin1Char('\n'));
    }
}

bool LaunchPipeline::launchGame(const QString& gameId) {
    if (m_running.contains(gameId)) {
        return true; // Already running
    }

    auto gameOpt = m_db->getGame(gameId);
    if (!gameOpt.has_value()) {
        emit gameLaunchFailed(gameId, QStringLiteral("Game entry not found in database."));
        return false;
    }
    const GameRecord game = *gameOpt;

    if (game.executablePath.isEmpty() || !QFileInfo::exists(game.executablePath)) {
        const QString msg = QStringLiteral("Executable not found: %1").arg(game.executablePath);
        m_diagMgr->startNewGameLog(gameId, QStringLiteral("=== Launch Failed ===\n") + msg);
        emit gameLaunchFailed(gameId, msg);
        return false;
    }

    if (isGamescopeEnabled(game) && QStandardPaths::findExecutable(QStringLiteral("gamescope")).isEmpty()) {
        const QString msg = QStringLiteral("Gamescope is enabled for this game, but 'gamescope' was not found in PATH. Install gamescope or disable Gamescope for this game.");
        m_diagMgr->startNewGameLog(gameId, QStringLiteral("=== Launch Failed ===\n") + msg);
        emit gameLaunchFailed(gameId, msg);
        return false;
    }

    const bool isNative = game.isNative();
    if (isNative) {
        QFile::Permissions perms = QFile::permissions(game.executablePath);
        if (!(perms & QFile::ExeUser)) {
            QFile::setPermissions(game.executablePath, perms | QFile::ExeUser | QFile::ExeGroup | QFile::ExeOther);
        }
    }
    LaunchPlan plan;
    std::optional<RunnerRecord> runnerOpt;
    PrefixRecord prefix;

    if (isNative) {
        plan = buildNativeLaunchPlan(game);
    } else {
        runnerOpt = m_runnerMgr->resolveRunner(game.runnerId);
        if (!runnerOpt.has_value()) {
            const QString msg = QStringLiteral("No Wine or Proton runner available. Please install or detect a runner in Runners.");
            m_diagMgr->startNewGameLog(gameId, QStringLiteral("=== Launch Failed ===\n") + msg);
            emit gameLaunchFailed(gameId, msg);
            return false;
        }

        if (!game.prefixId.isEmpty()) {
            if (auto pOpt = m_db->getPrefix(game.prefixId); pOpt.has_value()) {
                prefix = *pOpt;
            }
        }
        if (prefix.id.isEmpty()) {
            if (auto defOpt = m_db->getPrefix(QStringLiteral("default-prefix")); defOpt.has_value()) {
                prefix = *defOpt;
            } else {
                prefix.id = QStringLiteral("default-prefix");
                prefix.name = QStringLiteral("Default");
                prefix.path = m_settings->defaultPrefixLocation() + QStringLiteral("/Default");
                prefix.arch = QStringLiteral("win64");
            }
        }

        PrefixManager::ensureProtonSymlink(prefix.path);

        // Ensure DXVK / VKD3D DLLs are linked into Wine prefixes when requested
        const bool useDxvk = (game.dxvkState == -1) ? m_settings->dxvkDefault() : (game.dxvkState == 1);
        const bool useVkd3d = (game.vkd3dState == -1) ? m_settings->vkd3dDefault() : (game.vkd3dState == 1);
        if (!runnerOpt->isProton()) {
            if (useDxvk && !prefix.dxvkInstalled) {
                m_prefixMgr->installDxvk(prefix.id, true);
            }
            if (useVkd3d && !prefix.vkd3dInstalled) {
                m_prefixMgr->installVkd3d(prefix.id, true);
            }
        }

        plan = buildLaunchPlan(game, *runnerOpt, prefix);
    }

    QString header;
    if (isNative) {
        header = QStringLiteral(
            "=== Tsuki Game Launch Log ===\n"
            "Timestamp : %1\n"
            "Game      : %2 (%3)\n"
            "Platform  : Native Linux\n"
            "Executable: %4\n"
            "Command   : %5 %6\n"
            "=============================\n")
            .arg(QDateTime::currentDateTime().toString(Qt::ISODate),
                 game.title,
                 game.id,
                 game.executablePath,
                 plan.program,
                 plan.arguments.join(QLatin1Char(' ')));
    } else {
        header = QStringLiteral(
            "=== Tsuki Game Launch Log ===\n"
            "Timestamp : %1\n"
            "Game      : %2 (%3)\n"
            "Executable: %4\n"
            "Runner    : %5 (%6)\n"
            "Prefix    : %7 (%8)\n"
            "Command   : %9 %10\n"
            "=============================\n")
            .arg(QDateTime::currentDateTime().toString(Qt::ISODate),
                 game.title,
                 game.id,
                 game.executablePath,
                 runnerOpt->name,
                 runnerOpt->binaryPath,
                 prefix.name,
                 prefix.path,
                 plan.program,
                 plan.arguments.join(QLatin1Char(' ')));
    }

    m_diagMgr->startNewGameLog(gameId, header);

    // Start or share Xbox controller emulation
    if (plan.useXboxEmulation) {
        if (!m_controllerMgr->isEmulationActive()) {
            if (!m_controllerMgr->startXboxEmulation()) {
                m_diagMgr->appendGameLog(gameId, QStringLiteral("[Tsuki] Warning: Failed to start Xbox emulation: %1\n").arg(m_controllerMgr->uinputStatus()));
            }
        }
    }

    // Run Pre-Launch Script if configured
    if (!game.preLaunchScript.trimmed().isEmpty()) {
        executeScript(game.preLaunchScript, plan.workingDirectory, plan.environment, gameId);
    }

    const QString sessionToken = QUuid::createUuid().toString(QUuid::WithoutBraces);
    plan.environment.insert(QStringLiteral("TSUKI_SESSION_ID"), sessionToken);

    auto* proc = new QProcess(this);
    proc->setWorkingDirectory(plan.workingDirectory);
    proc->setProcessEnvironment(plan.environment);
    proc->setChildProcessModifier([]() {
        ::setsid();
    });

    auto* session = new RunningSession();
    session->gameId = gameId;
    session->title = game.title;
    session->prefixPath = prefix.path;
    session->runnerId = runnerOpt.has_value() ? runnerOpt->id : QString();
    session->postExitScript = game.postExitScript;
    session->sessionToken = sessionToken;
    session->startTimeEpoch = QDateTime::currentSecsSinceEpoch();
    session->process = proc;
    session->isNative = isNative;
    session->usesXboxEmulation = plan.useXboxEmulation;
    session->usesGamescope = plan.usesGamescope;
    session->workingDirectory = plan.workingDirectory;
    session->environment = plan.environment;

    m_running.insert(gameId, session);
    if (m_controllerMgr) {
        m_controllerMgr->setGameRunning(true);
    }
    emit runningGamesChanged();
    emit gameStarted(gameId, game.title);

    connect(proc, &QProcess::started, this, [this, proc, gameId]() {
        if (RunningSession* s = m_running.value(gameId, nullptr)) {
            if (proc->processId() > 0) {
                s->rootPid = proc->processId();
            }
        }
    });
    connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc, gameId]() {
        m_diagMgr->appendGameLog(gameId, QString::fromUtf8(proc->readAllStandardOutput()));
    });
    connect(proc, &QProcess::readyReadStandardError, this, [this, proc, gameId]() {
        m_diagMgr->appendGameLog(gameId, QString::fromUtf8(proc->readAllStandardError()));
    });

    connect(proc, &QProcess::errorOccurred, this, [this, gameId, proc](QProcess::ProcessError err) {
        m_diagMgr->appendGameLog(gameId, QStringLiteral("\n[Tsuki] Process error occurred (code %1): %2\n")
            .arg(static_cast<int>(err)).arg(proc->errorString()));
        if (err == QProcess::FailedToStart) {
            handleSessionTermination(gameId, -1, true, proc->errorString());
        }
    });

    connect(proc, &QProcess::finished, this, [this, gameId](int exitCode, QProcess::ExitStatus) {
        handleSessionTermination(gameId, exitCode, false, QString());
    });

    proc->start(plan.program, plan.arguments);
    if (proc->processId() > 0) {
        session->rootPid = proc->processId();
    }
    return true;
}

void LaunchPipeline::handleSessionTermination(const QString& gameId, int exitCode, bool isFailedToStart, const QString& errorString) {
    if (!m_running.contains(gameId)) return;
    RunningSession* sess = m_running.take(gameId);

    const bool shouldSweepOrphans = (sess->usesGamescope || sess->stopRequested) && !isFailedToStart;
    const qint64 rootPid = sess->rootPid;
    const QString sessionToken = sess->sessionToken;

    const qint64 now = QDateTime::currentSecsSinceEpoch();
    const qint64 elapsed = qMax<qint64>(1, now - sess->startTimeEpoch);

    if (isFailedToStart) {
        m_diagMgr->appendGameLog(gameId, QStringLiteral("\n=== Process failed to start: %1 ===\n").arg(errorString));
        emit gameLaunchFailed(gameId, errorString.isEmpty() ? QStringLiteral("Failed to start process.") : errorString);
    } else {
        m_db->updatePlaytime(gameId, elapsed, now);

        if (!sess->postExitScript.trimmed().isEmpty()) {
            executeScript(sess->postExitScript, sess->workingDirectory, sess->environment, gameId);
        }

        m_diagMgr->appendGameLog(gameId,
            QStringLiteral("\n=== Process exited with code %1 (Session: %2s) ===\n").arg(exitCode).arg(elapsed));

        if (exitCode != 0) {
            m_diagMgr->analyzeGameLogForErrors(gameId, exitCode);
        }
        emit gameStopped(gameId, exitCode, elapsed);
    }

    if (sess->process) {
        sess->process->deleteLater();
    }
    delete sess;

    if (shouldSweepOrphans && !sessionToken.isEmpty() && !collectTaggedSessionPids(sessionToken).isEmpty()) {
        signalSessionProcesses(rootPid, sessionToken, SIGTERM);
        QTimer::singleShot(800, this, [rootPid, sessionToken]() {
            if (!collectTaggedSessionPids(sessionToken).isEmpty()) {
                signalSessionProcesses(rootPid, sessionToken, SIGKILL);
            }
        });
    }

    updateEmulationLifecycle();
    emit runningGamesChanged();
}

void LaunchPipeline::updateEmulationLifecycle() {
    if (m_controllerMgr) {
        m_controllerMgr->setGameRunning(!m_running.isEmpty());
    }
    bool anyNeedsEmulation = false;
    for (const RunningSession* s : m_running) {
        if (s->usesXboxEmulation) {
            anyNeedsEmulation = true;
            break;
        }
    }
    if (!anyNeedsEmulation && m_controllerMgr->isEmulationActive()) {
        m_controllerMgr->stopXboxEmulation();
    }
}

void LaunchPipeline::terminateGameSession(const QString& gameId, bool waitForExit) {
    RunningSession* sess = m_running.value(gameId, nullptr);
    if (!sess) return;

    sess->stopRequested = true;
    const QPointer<QProcess> proc = sess->process;
    const qint64 rootPid = (proc && proc->processId() > 0) ? proc->processId() : sess->rootPid;
    const QString sessionToken = sess->sessionToken;
    const bool isNative = sess->isNative;
    const QString runnerId = sess->runnerId;
    const QString prefixPath = sess->prefixPath;

    m_diagMgr->appendGameLog(gameId, QStringLiteral("\n[Tsuki] Terminating game processes…\n"));

    // 1. Run wineserver -k for Wine/Proton prefixes (async during runtime so UI never freezes)
    if (!isNative) {
        if (auto runnerOpt = m_runnerMgr->resolveRunner(runnerId); runnerOpt.has_value()) {
            const QString wineserverBin = m_runnerMgr->findWineserverBinaryForRunner(*runnerOpt);
            if (!wineserverBin.isEmpty()) {
                QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
                env.insert(QStringLiteral("WINEPREFIX"), prefixPath);
                if (waitForExit) {
                    QProcess killWs;
                    killWs.setProcessEnvironment(env);
                    killWs.start(wineserverBin, {QStringLiteral("-k")});
                    killWs.waitForFinished(1200);
                } else {
                    auto* killWs = new QProcess(this);
                    killWs->setProcessEnvironment(env);
                    connect(killWs, &QProcess::finished, killWs, &QObject::deleteLater);
                    connect(killWs, &QProcess::errorOccurred, killWs, &QObject::deleteLater);
                    QTimer::singleShot(2500, killWs, [killWs]() {
                        if (killWs->state() != QProcess::NotRunning) {
                            killWs->kill();
                        }
                    });
                    killWs->start(wineserverBin, {QStringLiteral("-k")});
                }
            }
        }
    }

    // 2. Signal the entire session tree (process group + /proc descendants + detached session-tagged processes)
    signalSessionProcesses(rootPid, sessionToken, SIGTERM);
    if (proc && proc->state() != QProcess::NotRunning) {
        proc->terminate();
    }

    if (waitForExit) {
        if (proc && proc->state() != QProcess::NotRunning && !proc->waitForFinished(500)) {
            signalSessionProcesses(rootPid, sessionToken, SIGKILL);
            proc->kill();
            proc->waitForFinished(500);
        } else if (!collectTaggedSessionPids(sessionToken).isEmpty()) {
            signalSessionProcesses(rootPid, sessionToken, SIGKILL);
        }
    } else {
        QTimer::singleShot(1200, this, [proc, rootPid, sessionToken]() {
            const bool procAlive = (proc && proc->state() != QProcess::NotRunning);
            if (procAlive || !collectTaggedSessionPids(sessionToken).isEmpty()) {
                signalSessionProcesses(rootPid, sessionToken, SIGKILL);
                if (procAlive) {
                    proc->kill();
                }
            }
        });
    }
}

void LaunchPipeline::stopGame(const QString& gameId) {
    terminateGameSession(gameId, false);
}

void LaunchPipeline::stopAllGames() {
    const QStringList ids = m_running.keys();
    for (const QString& id : ids) {
        terminateGameSession(id, true);
    }
}

} // namespace Tsuki

