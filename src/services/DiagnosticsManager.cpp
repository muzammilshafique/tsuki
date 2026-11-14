#include "DiagnosticsManager.h"
#include <QStandardPaths>
#include <QFileInfo>
#include <QFile>
#include <QDir>
#include <QUrl>
#include <QProcess>
#include <QDateTime>

namespace Tsuki {

DiagnosticsManager::DiagnosticsManager(DatabaseManager* db,
                                       AppSettings* settings,
                                       RunnerManager* runnerMgr,
                                       PrefixManager* prefixMgr,
                                       QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_runnerMgr(runnerMgr)
    , m_prefixMgr(prefixMgr)
{
    runSystemDiagnostics();
}

QString DiagnosticsManager::logFilePathForGame(const QString& gameId) {
    return AppSettings::logsDir() + QStringLiteral("/") + gameId + QStringLiteral(".log");
}

void DiagnosticsManager::setSelectedLogGameId(const QString& gameId) {
    if (m_selectedLogGameId == gameId) return;
    m_selectedLogGameId = gameId;
    emit activeGameLogChanged();
}

QString DiagnosticsManager::activeGameLog() const {
    if (m_selectedLogGameId.isEmpty()) {
        if (!m_inMemoryLogs.isEmpty()) {
            return m_inMemoryLogs.last();
        }
        return QStringLiteral("Select a game or launch a title to view live execution logs.");
    }
    return getGameLogText(m_selectedLogGameId);
}

QString DiagnosticsManager::getGameLogText(const QString& gameId) const {
    if (m_inMemoryLogs.contains(gameId)) {
        return m_inMemoryLogs.value(gameId);
    }
    QFile f(logFilePathForGame(gameId));
    if (f.exists() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString::fromUtf8(f.readAll());
    }
    return QStringLiteral("No logs recorded yet for this game.");
}

void DiagnosticsManager::startNewGameLog(const QString& gameId, const QString& headerInfo) {
    m_selectedLogGameId = gameId;
    m_inMemoryLogs[gameId] = headerInfo + QLatin1Char('\n');

    QFile f(logFilePathForGame(gameId));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        f.write(m_inMemoryLogs[gameId].toUtf8());
        f.close();
    }
    emit activeGameLogChanged();
}

void DiagnosticsManager::appendGameLog(const QString& gameId, const QString& text) {
    if (text.isEmpty()) return;
    m_inMemoryLogs[gameId].append(text);

    QFile f(logFilePathForGame(gameId));
    if (f.open(QIODevice::WriteOnly | QIODevice::Append | QIODevice::Text)) {
        f.write(text.toUtf8());
        f.close();
    }
    if (m_selectedLogGameId == gameId || m_selectedLogGameId.isEmpty()) {
        emit activeGameLogChanged();
    }
}

void DiagnosticsManager::clearGameLog(const QString& gameId) {
    m_inMemoryLogs.remove(gameId);
    QFile::remove(logFilePathForGame(gameId));
    emit activeGameLogChanged();
}

bool DiagnosticsManager::exportGameLog(const QString& gameId, const QString& destinationPath) const {
    QString cleanDest = destinationPath.trimmed();
    if (cleanDest.startsWith(QStringLiteral("file://"))) {
        cleanDest = QUrl(cleanDest).toLocalFile();
    }
    if (cleanDest.isEmpty()) {
        cleanDest = QDir::homePath() + QStringLiteral("/tsuki_%1.log").arg(gameId);
    }
    QFile out(cleanDest);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        return false;
    }
    out.write(getGameLogText(gameId).toUtf8());
    out.close();
    return true;
}

QVariantMap DiagnosticsManager::analyzeGameLogForErrors(const QString& gameId, int exitCode) {
    const QString log = getGameLogText(gameId);
    QVariantMap diag;
    diag["gameId"] = gameId;
    diag["exitCode"] = exitCode;
    diag["timestamp"] = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));

    QString summary;
    QString recommendation;

    auto gameOpt = m_db->getGame(gameId);
    const bool isNative = gameOpt.has_value() && gameOpt->isNative();

    if (isNative) {
        if (log.contains(QStringLiteral("error while loading shared libraries"), Qt::CaseInsensitive)) {
            summary = QStringLiteral("Missing Native Shared Library (.so)");
            recommendation = QStringLiteral("A required native Linux system library is missing. Install the missing package using your Linux distribution package manager.");
        } else if (log.contains(QStringLiteral("Permission denied"), Qt::CaseInsensitive)) {
            summary = QStringLiteral("Executable Permission Denied");
            recommendation = QStringLiteral("Ensure the game binary or launch script has executable permissions (chmod +x).");
        } else if (exitCode != 0) {
            summary = QStringLiteral("Native game process exited with code %1").arg(exitCode);
            recommendation = QStringLiteral("Check the game log output above, working directory, or missing runtime dependencies.");
        }
    } else {
        if (log.contains(QStringLiteral("c0000135"), Qt::CaseInsensitive) ||
            log.contains(QStringLiteral("module not found"), Qt::CaseInsensitive) ||
            log.contains(QStringLiteral("failed to load"), Qt::CaseInsensitive)) {
            summary = QStringLiteral("Missing DLL Dependency (STATUS_DLL_NOT_FOUND / 0xC0000135)");
            recommendation = QStringLiteral("Open Winetricks for this game's prefix and install Visual C++ 2015–2022 (vcrun2022) and DirectX 9/11 (d3dx9, d3dcompiler_47).");
        } else if (log.contains(QStringLiteral("0xc000007b"), Qt::CaseInsensitive) ||
                   log.contains(QStringLiteral("bad_exe_format"), Qt::CaseInsensitive)) {
            summary = QStringLiteral("32-bit / 64-bit Architecture Mismatch (0xC000007B)");
            recommendation = QStringLiteral("Ensure both 32-bit and 64-bit Visual C++ redistributables are installed in the prefix, or recreate the prefix as 64-bit (win64).");
        } else if (log.contains(QStringLiteral("vulkan"), Qt::CaseInsensitive) &&
                   (log.contains(QStringLiteral("failed"), Qt::CaseInsensitive) ||
                    log.contains(QStringLiteral("VK_ERROR"), Qt::CaseInsensitive))) {
            summary = QStringLiteral("Vulkan / DXVK Initialization Error");
            recommendation = QStringLiteral("Verify that host Vulkan ICD drivers are installed, or disable DXVK in the game's launch configuration to fall back to WineD3D (OpenGL).");
        } else if (log.contains(QStringLiteral("mscoree.dll"), Qt::CaseInsensitive)) {
            summary = QStringLiteral("Missing .NET Framework / Wine Mono Runtime");
            recommendation = QStringLiteral("Install dotnet48 via Winetricks for this game's prefix.");
        } else if (exitCode != 0) {
            summary = QStringLiteral("Game process exited with code %1").arg(exitCode);
            recommendation = QStringLiteral("Check the game executable path, working directory, or switch the runner between Proton-GE and System Wine.");
        }
    }

    diag["summary"] = summary;
    diag["recommendation"] = recommendation;

    if (!summary.isEmpty()) {
        m_detectedIssues.prepend(diag);
        while (m_detectedIssues.size() > 25) m_detectedIssues.removeLast();
        emit detectedIssuesChanged();

        QString gameTitle = gameId;
        if (auto g = m_db->getGame(gameId); g.has_value()) {
            gameTitle = g->title;
        }
        emit launchErrorDiagnosed(gameId, gameTitle, summary, recommendation);
    }
    return diag;
}

void DiagnosticsManager::runSystemDiagnostics() {
    m_systemChecks.clear();

    auto addCheck = [this](const QString& name, bool ok, const QString& detail, const QString& category) {
        QVariantMap m;
        m["name"] = name;
        m["ok"] = ok;
        m["detail"] = detail;
        m["category"] = category;
        m_systemChecks.append(m);
    };

    // 1. Wine / Proton Runners
    const auto runners = m_runnerMgr->installedRunners();
    addCheck(QStringLiteral("Wine / Proton Runners"),
             !runners.isEmpty(),
             runners.isEmpty() ? QStringLiteral("No runners installed") : QStringLiteral("%1 runner(s) detected").arg(runners.size()),
             QStringLiteral("Runner"));

    // 2. 32-bit glibc support (essential for 32-bit Windows games)
    const bool has32BitLibc = QFileInfo::exists(QStringLiteral("/lib/ld-linux.so.2")) ||
                              QFileInfo::exists(QStringLiteral("/usr/lib32/ld-linux.so.2")) ||
                              QFileInfo::exists(QStringLiteral("/lib/i386-linux-gnu/ld-linux.so.2"));
    addCheck(QStringLiteral("32-bit Runtime Libraries (multilib)"),
             has32BitLibc,
             has32BitLibc ? QStringLiteral("ld-linux.so.2 available") : QStringLiteral("32-bit libraries missing"),
             QStringLiteral("System"));

    // 3. Vulkan ICD Loader
    const bool hasVulkan = QFileInfo::exists(QStringLiteral("/usr/share/vulkan/icd.d")) ||
                           QFileInfo::exists(QStringLiteral("/etc/vulkan/icd.d"));
    addCheck(QStringLiteral("Vulkan Graphics Support"),
             hasVulkan,
             hasVulkan ? QStringLiteral("Vulkan ICD configs present") : QStringLiteral("No Vulkan ICD directory found"),
             QStringLiteral("Graphics"));

    // 4. DXVK & VKD3D-Proton
    const int dxvkCount = m_runnerMgr->findDxvkDirectories().size();
    const int vkd3dCount = m_runnerMgr->findVkd3dDirectories().size();
    addCheck(QStringLiteral("DXVK & VKD3D-Proton Layers"),
             dxvkCount > 0 || vkd3dCount > 0,
             QStringLiteral("DXVK: %1 build(s), VKD3D: %2 build(s)").arg(dxvkCount).arg(vkd3dCount),
             QStringLiteral("Graphics"));

    // 5. Winetricks
    const QString wtBin = QStandardPaths::findExecutable(QStringLiteral("winetricks"));
    const QString tsukiWt = AppSettings::toolsDir() + QStringLiteral("/winetricks");
    const bool hasWt = !wtBin.isEmpty() || QFileInfo::exists(tsukiWt) ||
                       QFileInfo::exists(QDir::homePath() + QStringLiteral("/.config/heroic/tools/winetricks"));
    addCheck(QStringLiteral("Winetricks Integration"),
             hasWt,
             hasWt ? QStringLiteral("Winetricks available") : QStringLiteral("Will auto-download on demand"),
             QStringLiteral("Tools"));

    // 6. MangoHud, GameMode & Gamescope
    const QString mangoBin = QStandardPaths::findExecutable(QStringLiteral("mangohud"));
    const QString gmBin = QStandardPaths::findExecutable(QStringLiteral("gamemoderun"));
    const QString gsBin = QStandardPaths::findExecutable(QStringLiteral("gamescope"));
    const bool hasMango = !mangoBin.isEmpty();
    const bool hasGamemode = !gmBin.isEmpty();
    m_gamescopeAvailable = !gsBin.isEmpty();
    addCheck(QStringLiteral("MangoHud Overlay"),
             hasMango,
             hasMango ? QStringLiteral("%1 ready").arg(mangoBin) : QStringLiteral("Not installed"),
             QStringLiteral("Performance"));
    addCheck(QStringLiteral("Feral GameMode"),
             hasGamemode,
             hasGamemode ? QStringLiteral("%1 ready").arg(gmBin) : QStringLiteral("Not installed"),
             QStringLiteral("Performance"));
    addCheck(QStringLiteral("Gamescope Micro-Compositor"),
             m_gamescopeAvailable,
             m_gamescopeAvailable ? QStringLiteral("%1 ready").arg(gsBin) : QStringLiteral("Not installed"),
             QStringLiteral("Performance"));

    // 7. uinput Xbox Controller Emulation
    QFileInfo uinputFi(QStringLiteral("/dev/uinput"));
    addCheck(QStringLiteral("Xbox Controller Emulation (/dev/uinput)"),
             uinputFi.exists() && uinputFi.isWritable(),
             (uinputFi.exists() && uinputFi.isWritable())
                 ? QStringLiteral("/dev/uinput writable (Kernel XInput ready)")
                 : QStringLiteral("/dev/uinput not writable (Fallback SDL_GAMECONTROLLERCONFIG active)"),
             QStringLiteral("Controller"));

    emit systemChecksChanged();
}

QVariantMap DiagnosticsManager::diagnosePrefix(const QString& prefixId) const {
    QVariantMap report;
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) {
        report["valid"] = false;
        report["status"] = QStringLiteral("Prefix record not found in database.");
        return report;
    }

    const QDir dir(pfx->path);
    const bool hasDriveC = QDir(pfx->path + QStringLiteral("/drive_c")).exists();
    const bool hasSys32 = QDir(pfx->path + QStringLiteral("/drive_c/windows/system32")).exists();
    const bool hasUserReg = QFileInfo::exists(pfx->path + QStringLiteral("/user.reg"));
    const bool hasPfxLink = QFileInfo::exists(pfx->path + QStringLiteral("/pfx"));

    report["id"] = pfx->id;
    report["name"] = pfx->name;
    report["path"] = pfx->path;
    report["exists"] = dir.exists();
    report["hasDriveC"] = hasDriveC;
    report["hasSystem32"] = hasSys32;
    report["hasRegistry"] = hasUserReg;
    report["hasProtonLink"] = hasPfxLink;
    report["valid"] = dir.exists() && hasDriveC && hasSys32;
    report["status"] = (dir.exists() && hasDriveC && hasSys32)
                           ? QStringLiteral("Healthy (%1, %2)").arg(pfx->arch, pfx->windowsVersion.toUpper())
                           : QStringLiteral("Prefix structure incomplete — click Repair Prefix to rebuild.");
    return report;
}

bool DiagnosticsManager::repairPrefix(const QString& prefixId) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return false;

    QDir().mkpath(pfx->path + QStringLiteral("/drive_c/windows/system32"));
    if (pfx->arch == QStringLiteral("win64")) {
        QDir().mkpath(pfx->path + QStringLiteral("/drive_c/windows/syswow64"));
    }
    PrefixManager::ensureProtonSymlink(pfx->path);
    PrefixManager::writeRegistryDllOverrides(pfx->path, pfx->dllOverrides);

    auto runnerOpt = m_runnerMgr->resolveRunner(pfx->runnerId);
    if (runnerOpt.has_value()) {
        const QString wineBin = m_runnerMgr->findWineBinaryForRunner(*runnerOpt);
        const QString wineserverBin = m_runnerMgr->findWineserverBinaryForRunner(*runnerOpt);
        if (!wineserverBin.isEmpty()) {
            QProcess killProc;
            QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
            env.insert(QStringLiteral("WINEPREFIX"), pfx->path);
            killProc.setProcessEnvironment(env);
            killProc.start(wineserverBin, {QStringLiteral("-k")});
            killProc.waitForFinished(2000);
        }
        if (!wineBin.isEmpty() && QFileInfo::exists(wineBin)) {
            auto* bootProc = new QProcess(this);
            QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
            env.insert(QStringLiteral("WINEPREFIX"), pfx->path);
            env.insert(QStringLiteral("WINEARCH"), pfx->arch);
            env.insert(QStringLiteral("WINEDLLOVERRIDES"), QStringLiteral("mscoree,mshtml="));
            bootProc->setProcessEnvironment(env);
            connect(bootProc, &QProcess::finished, bootProc, &QObject::deleteLater);
            bootProc->start(wineBin, {QStringLiteral("wineboot"), QStringLiteral("-u")});
        }
    }
    return true;
}

} // namespace Tsuki

