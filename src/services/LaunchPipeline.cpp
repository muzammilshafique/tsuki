#include "LaunchPipeline.h"
#include <QFileInfo>
#include <QDir>
#include <QDateTime>
#include <QStandardPaths>
#include <signal.h>

namespace Tsuki {

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

static QStringList buildPerformanceWrappers(const GameRecord& game, bool useGamemode, bool useMangohud) {
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
    if (useMangohud) {
        const QString mhBin = QStandardPaths::findExecutable(QStringLiteral("mangohud"));
        if (!mhBin.isEmpty()) {
            fullCmd << mhBin;
        }
    }
    return fullCmd;
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
    plan.useXboxEmulation = (game.xboxEmulationState == 1);

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

    // Per-game custom environment variables
    for (auto it = game.environmentVariables.constBegin(); it != game.environmentVariables.constEnd(); ++it) {
        if (!it.key().isEmpty()) {
            env.insert(it.key(), it.value().toString());
        }
    }

    if (useMangohud) {
        env.insert(QStringLiteral("MANGOHUD"), QStringLiteral("1"));
    }

    // Build wrapper chain: [taskset] -> [nice] -> [gamemoderun] -> [mangohud] -> [wine/proton] -> [virtual desktop] -> [exe] [args]
    QStringList fullCmd = buildPerformanceWrappers(game, useGamemode, useMangohud);

    if (runner.isProton()) {
        fullCmd << runner.binaryPath << QStringLiteral("waitforexitandrun");
        if (game.virtualDesktop) {
            const QString res = game.virtualDesktopResolution.isEmpty() ? QStringLiteral("1920x1080") : game.virtualDesktopResolution;
            fullCmd << QStringLiteral("explorer") << QStringLiteral("/desktop=Tsuki,%1").arg(res);
        }
        fullCmd << game.executablePath;
    } else {
        fullCmd << runner.binaryPath;
        if (game.virtualDesktop) {
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
    plan.useXboxEmulation = (game.xboxEmulationState == 1);

    if (plan.useXboxEmulation) {
        const QString sdlCfg = m_controllerMgr->buildSdlGameControllerConfig();
        if (!sdlCfg.isEmpty()) {
            env.insert(QStringLiteral("SDL_GAMECONTROLLERCONFIG"), sdlCfg);
        }
        env.insert(QStringLiteral("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"), QStringLiteral("1"));
    }

    if (useMangohud) {
        env.insert(QStringLiteral("MANGOHUD"), QStringLiteral("1"));
    }

    // Per-game custom environment variables
    for (auto it = game.environmentVariables.constBegin(); it != game.environmentVariables.constEnd(); ++it) {
        if (!it.key().isEmpty()) {
            env.insert(it.key(), it.value().toString());
        }
    }

    QStringList fullCmd = buildPerformanceWrappers(game, useGamemode, useMangohud);

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

    auto* proc = new QProcess(this);
    proc->setWorkingDirectory(plan.workingDirectory);
    proc->setProcessEnvironment(plan.environment);
    if (isNative) {
        proc->setChildProcessModifier([]() {
            ::setsid();
        });
    }

    auto* session = new RunningSession();
    session->gameId = gameId;
    session->title = game.title;
    session->prefixPath = prefix.path;
    session->runnerId = runnerOpt.has_value() ? runnerOpt->id : QString();
    session->postExitScript = game.postExitScript;
    session->startTimeEpoch = QDateTime::currentSecsSinceEpoch();
    session->process = proc;
    session->isNative = isNative;
    session->usesXboxEmulation = plan.useXboxEmulation;
    session->workingDirectory = plan.workingDirectory;
    session->environment = plan.environment;

    m_running.insert(gameId, session);
    emit runningGamesChanged();
    emit gameStarted(gameId, game.title);

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
    return true;
}

void LaunchPipeline::handleSessionTermination(const QString& gameId, int exitCode, bool isFailedToStart, const QString& errorString) {
    if (!m_running.contains(gameId)) return;
    RunningSession* sess = m_running.take(gameId);

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

    updateEmulationLifecycle();
    emit runningGamesChanged();
}

void LaunchPipeline::updateEmulationLifecycle() {
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

void LaunchPipeline::stopGame(const QString& gameId) {
    if (!m_running.contains(gameId)) return;
    RunningSession* sess = m_running.value(gameId);

    m_diagMgr->appendGameLog(gameId, QStringLiteral("\n[Tsuki] Terminating game processes…\n"));

    // 1. Run wineserver -k for this prefix so all Wine child processes exit cleanly
    if (!sess->isNative) {
        if (auto runnerOpt = m_runnerMgr->resolveRunner(sess->runnerId); runnerOpt.has_value()) {
            const QString wineserverBin = m_runnerMgr->findWineserverBinaryForRunner(*runnerOpt);
            if (!wineserverBin.isEmpty()) {
                QProcess killWs;
                QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
                env.insert(QStringLiteral("WINEPREFIX"), sess->prefixPath);
                killWs.setProcessEnvironment(env);
                killWs.start(wineserverBin, {QStringLiteral("-k")});
                killWs.waitForFinished(2000);
            }
        }
    }

    // 2. Terminate and kill QProcess if still alive
    if (sess->process && sess->process->state() != QProcess::NotRunning) {
        const qint64 pid = sess->process->processId();
        if (sess->isNative && pid > 0) {
            ::kill(-static_cast<pid_t>(pid), SIGTERM);
        }
        sess->process->terminate();
        if (!sess->process->waitForFinished(1500)) {
            if (pid > 0) {
                if (sess->isNative) {
                    ::kill(-static_cast<pid_t>(pid), SIGKILL);
                } else {
                    ::kill(static_cast<pid_t>(pid), SIGKILL);
                }
            }
            sess->process->kill();
        }
    }
}

void LaunchPipeline::stopAllGames() {
    const QStringList ids = m_running.keys();
    for (const QString& id : ids) {
        stopGame(id);
    }
}

} // namespace Tsuki

