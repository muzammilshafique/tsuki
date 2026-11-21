#include "UiController.h"
#include <QCoreApplication>
#include <QCursor>
#include <QDesktopServices>
#include <QDirIterator>
#include <QFileDialog>
#include <QDir>
#include <QFileInfo>
#include <QSet>
#include <QStandardPaths>
#include <QUrl>
#include <QEvent>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>

namespace Tsuki {

UiController::UiController(DatabaseManager* db,
                           AppSettings* settings,
                           DownloadManager* dl,
                           RunnerManager* runnerMgr,
                           PrefixManager* prefixMgr,
                           WinetricksManager* wtMgr,
                           ControllerManager* ctrlMgr,
                           SteamGridDbService* sgdb,
                           LaunchPipeline* launchPipeline,
                           DiagnosticsManager* diagMgr,
                           GameManager* gameMgr,
                           EpicService* epicService,
                           EpicCloudSaveService* cloudSaveService,
                           UmuIdResolver* umuIdResolver,
                           QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_dl(dl)
    , m_runnerMgr(runnerMgr)
    , m_prefixMgr(prefixMgr)
    , m_wtMgr(wtMgr)
    , m_ctrlMgr(ctrlMgr)
    , m_sgdb(sgdb)
    , m_launchPipeline(launchPipeline)
    , m_diagMgr(diagMgr)
    , m_gameMgr(gameMgr)
    , m_epicSvc(epicService)
    , m_cloudSaveSvc(cloudSaveService)
    , m_umuResolver(umuIdResolver)
    , m_activeInputType((ctrlMgr && ctrlMgr->isConnected()) ? ctrlMgr->controllerType() : QStringLiteral("keyboard"))
{
    if (QCoreApplication::instance()) {
        QCoreApplication::instance()->installEventFilter(this);
    }

    if (m_ctrlMgr) {
        connect(m_ctrlMgr, &ControllerManager::uiKeySimulated, this, [this]() {
            setActiveInputType(m_ctrlMgr->controllerType());
            setKeyboardNavActive(true);
        });
        connect(m_ctrlMgr, &ControllerManager::gamepadInputReceived, this, [this](const QString& type) {
            setActiveInputType(type);
            setKeyboardNavActive(true);
        });
        connect(m_ctrlMgr, &ControllerManager::controllersChanged, this, [this]() {
            if (isGamepadActive()) {
                if (m_ctrlMgr->isConnected()) {
                    setActiveInputType(m_ctrlMgr->controllerType());
                } else {
                    setActiveInputType(QStringLiteral("keyboard"));
                }
            }
        });
    }
    connect(m_gameMgr, &GameManager::gameOperationStatus, this, &UiController::toastRequested);
    connect(m_runnerMgr, &RunnerManager::runnerOperationStatus, this, &UiController::toastRequested);
    connect(m_prefixMgr, &PrefixManager::prefixOperationFinished, this, [this](const QString&, bool ok, const QString& msg) {
        emit toastRequested(msg, !ok);
    });
    connect(m_wtMgr, &WinetricksManager::verbFinished, this, [this](const QString&, const QString&, bool ok, const QString& msg) {
        emit toastRequested(msg, !ok);
    });
    connect(m_launchPipeline, &LaunchPipeline::gameLaunchFailed, this, [this](const QString&, const QString& reason) {
        emit toastRequested(reason, true);
    });
    connect(m_launchPipeline, &LaunchPipeline::launchStatusMessage, this, &UiController::toastRequested);
    connect(m_launchPipeline, &LaunchPipeline::gameStarted, this, [this](const QString&, const QString& title) {
        setKeyboardNavActive(false);
        if (m_dl) {
            m_dl->pauseForGameplay();
        }
        emit toastRequested(QStringLiteral("Launching %1…").arg(title), false);
    });
    connect(m_launchPipeline, &LaunchPipeline::gameStopped, this, [this](const QString&, int, qint64) {
        if (m_dl && m_launchPipeline->runningCount() == 0) {
            m_dl->resumeAfterGameplay();
        }
    });
    connect(m_diagMgr, &DiagnosticsManager::launchErrorDiagnosed, this,
            [this](const QString&, const QString& title, const QString& summary, const QString& rec) {
                emit toastRequested(QStringLiteral("%1: %2 — %3").arg(title, summary, rec), true);
            });
    if (m_epicSvc) {
        connect(m_epicSvc, &EpicService::operationStatus, this, &UiController::toastRequested);
    }
    if (m_cloudSaveSvc) {
        connect(m_cloudSaveSvc, &EpicCloudSaveService::operationStatus, this, &UiController::toastRequested);
    }
}

UiController::~UiController() {
    updateCursorVisibility(false);
}

void UiController::updateCursorVisibility(bool hide) {
    if (hide && !m_cursorHidden) {
        QGuiApplication::setOverrideCursor(Qt::BlankCursor);
        m_cursorHidden = true;
    } else if (!hide && m_cursorHidden) {
        QGuiApplication::restoreOverrideCursor();
        m_cursorHidden = false;
    }
}

void UiController::setKeyboardNavActive(bool active) {
    if (m_isKeyboardNavActive == active) return;
    m_isKeyboardNavActive = active;
    updateCursorVisibility(active);
    emit keyboardNavActiveChanged();
}

void UiController::setActiveInputType(const QString& inputType) {
    const QString normalized = (inputType == QLatin1String("playstation") || inputType == QLatin1String("xbox"))
        ? inputType
        : QStringLiteral("keyboard");
    if (m_activeInputType == normalized) return;
    m_activeInputType = normalized;
    emit activeInputTypeChanged();
}

bool UiController::eventFilter(QObject* watched, QEvent* event) {
    if (event->type() == QEvent::KeyPress) {
        if (m_ctrlMgr && m_ctrlMgr->isSendingSyntheticKey()) {
            setActiveInputType(m_ctrlMgr->controllerType());
            setKeyboardNavActive(true);
        } else {
            auto* ke = static_cast<QKeyEvent*>(event);
            switch (ke->key()) {
                case Qt::Key_Shift:
                case Qt::Key_Control:
                case Qt::Key_Alt:
                case Qt::Key_Meta:
                case Qt::Key_CapsLock:
                    break;
                case Qt::Key_Up:
                case Qt::Key_Down:
                case Qt::Key_Left:
                case Qt::Key_Right:
                case Qt::Key_Tab:
                case Qt::Key_Backtab:
                case Qt::Key_Return:
                case Qt::Key_Enter:
                case Qt::Key_Space:
                case Qt::Key_Escape:
                case Qt::Key_Backspace:
                case Qt::Key_PageUp:
                case Qt::Key_PageDown:
                case Qt::Key_Slash:
                case Qt::Key_BracketLeft:
                case Qt::Key_BracketRight:
                    setActiveInputType(QStringLiteral("keyboard"));
                    setKeyboardNavActive(true);
                    break;
                default:
                    setActiveInputType(QStringLiteral("keyboard"));
                    break;
            }
        }
    } else if (event->type() == QEvent::MouseButtonPress || event->type() == QEvent::Wheel) {
        setActiveInputType(QStringLiteral("keyboard"));
        setKeyboardNavActive(false);
    } else if (event->type() == QEvent::MouseMove) {
        auto* me = static_cast<QMouseEvent*>(event);
        const QPoint pos = me->globalPosition().toPoint();
        if (!m_hasLastMousePos || (pos - m_lastMousePos).manhattanLength() >= 2) {
            m_lastMousePos = pos;
            m_hasLastMousePos = true;
            setActiveInputType(QStringLiteral("keyboard"));
            setKeyboardNavActive(false);
        }
    } else if (event->type() == QEvent::ApplicationDeactivate || event->type() == QEvent::WindowDeactivate) {
        updateCursorVisibility(false);
    }
    return QObject::eventFilter(watched, event);
}

void UiController::search(const QString& query, int filterType) {
    m_gameMgr->model()->setFilterType(filterType);
    m_gameMgr->model()->setSearchQuery(query);
    emit searchStateChanged(false, QString());
}

void UiController::loadFavorites() {
    m_gameMgr->model()->setFilterType(3);
}

void UiController::loadDownloads() {
    m_gameMgr->model()->setFilterType(4);
}

void UiController::loadRecentMedia() {
    m_gameMgr->model()->reload();
}

void UiController::togglePin(const QString& gameId) {
    m_gameMgr->togglePin(gameId);
}

void UiController::toggleFavorite(const QVariant& itemOrId) {
    if (itemOrId.typeId() == QMetaType::QString) {
        m_gameMgr->toggleFavorite(itemOrId.toString());
    } else if (itemOrId.canConvert<QVariantMap>()) {
        const QVariantMap m = itemOrId.toMap();
        const QString id = m.value(QStringLiteral("id"), m.value(QStringLiteral("tmdbId"))).toString();
        if (!id.isEmpty()) {
            m_gameMgr->toggleFavorite(id);
        }
    }
}

void UiController::removeRecent(const QString& gameId) {
    m_gameMgr->removeGame(gameId, false);
}

QString UiController::selectFile(const QString& title, const QString& filter, const QString& initialPath) {
    updateCursorVisibility(false);
    const QString dlgTitle = title.isEmpty() ? QStringLiteral("Select File") : title;
    const QString startDir = initialPath.isEmpty() ? QDir::homePath() : initialPath;
    const QString selected = QFileDialog::getOpenFileName(nullptr, dlgTitle, startDir, filter);
    return selected;
}

QString UiController::selectFolder(const QString& title, const QString& initialPath) {
    updateCursorVisibility(false);
    const QString dlgTitle = title.isEmpty() ? QStringLiteral("Select Folder") : title;
    const QString startDir = initialPath.isEmpty() ? QDir::homePath() : initialPath;
    const QString selected = QFileDialog::getExistingDirectory(nullptr, dlgTitle, startDir, QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks);
    return selected;
}

bool UiController::openDirectory(const QString& path) {
    const QString clean = path.trimmed();
    if (clean.isEmpty()) return false;
    QDir().mkpath(clean);
    return QDesktopServices::openUrl(QUrl::fromLocalFile(clean));
}

namespace {

struct StorageScanResult {
    qint64 bytes = 0;
    int files = 0;
};

QString normalizedLocalArtPath(const QString& rawPath) {
    QString p = rawPath.trimmed();
    if (p.startsWith(QStringLiteral("file://"))) {
        p = QUrl(p).toLocalFile();
    }
    return p.isEmpty() ? QString() : QDir::cleanPath(p);
}

QSet<QString> collectInstalledGameArtPaths(DatabaseManager* db) {
    QSet<QString> paths;
    if (!db) return paths;
    for (const GameRecord& g : db->getAllGames()) {
        for (const QString& raw : {g.coverPath, g.bannerPath, g.logoPath, g.iconPath}) {
            const QString clean = normalizedLocalArtPath(raw);
            if (!clean.isEmpty()) paths.insert(clean);
        }
    }
    return paths;
}

QSet<QString> collectAllActiveArtPaths(DatabaseManager* db) {
    QSet<QString> paths = collectInstalledGameArtPaths(db);
    if (!db) return paths;
    for (const EpicLibraryItem& item : db->getAllEpicLibraryItems()) {
        for (const QString& raw : {item.coverPath, item.bannerPath, item.logoPath}) {
            const QString clean = normalizedLocalArtPath(raw);
            if (!clean.isEmpty()) paths.insert(clean);
        }
    }
    return paths;
}

QSet<QString> collectInstalledEpicAppNames(DatabaseManager* db) {
    QSet<QString> apps;
    if (!db) return apps;
    for (const GameRecord& g : db->getAllGames()) {
        if (!g.epicAppName.isEmpty()) apps.insert(g.epicAppName);
    }
    return apps;
}

QSet<QString> collectRunningGameIds(LaunchPipeline* lp) {
    QSet<QString> ids;
    if (!lp) return ids;
    for (const QString& id : lp->runningGameIds()) {
        ids.insert(id);
    }
    return ids;
}

QString appSpecificQtCacheDir() {
    const QString qtCache = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::CacheLocation));
    const QString tsukiCache = QDir::cleanPath(AppSettings::cacheDir());
    if (qtCache.isEmpty() || qtCache == tsukiCache) return QString();
    // Guard: never target generic ~/.cache directly
    const QString generic = QDir::cleanPath(QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation));
    if (qtCache == generic || (!qtCache.contains(QStringLiteral("Tsuki"), Qt::CaseInsensitive))) {
        return QString();
    }
    return qtCache;
}

void removeEmptySubdirs(const QString& rootPath) {
    QDir root(rootPath);
    if (!root.exists()) return;
    const QFileInfoList subDirs = root.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo& sd : subDirs) {
        removeEmptySubdirs(sd.absoluteFilePath());
        QDir d(sd.absoluteFilePath());
        if (d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).isEmpty()) {
            root.rmdir(sd.fileName());
        }
    }
}

StorageScanResult scanOrCleanCache(DatabaseManager* db, DownloadManager* dl, bool performDelete) {
    StorageScanResult res;
    const QSet<QString> activeDownloadFiles = dl ? dl->activeDestinationFiles() : QSet<QString>();

    auto processDir = [&](const QString& dirPath, bool skipActiveAndPart) {
        if (dirPath.isEmpty() || !QDir(dirPath).exists()) return;
        QDirIterator it(dirPath, QDir::Files | QDir::NoSymLinks, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            const QFileInfo fi = it.fileInfo();
            const QString cleanPath = QDir::cleanPath(fi.absoluteFilePath());
            if (skipActiveAndPart && (activeDownloadFiles.contains(cleanPath) || fi.fileName().endsWith(QStringLiteral(".part")))) {
                continue;
            }
            const qint64 sz = fi.size();
            if (performDelete) {
                if (QFile::remove(cleanPath)) {
                    res.bytes += sz;
                    ++res.files;
                }
            } else {
                res.bytes += sz;
                ++res.files;
            }
        }
        if (performDelete) removeEmptySubdirs(dirPath);
    };

    processDir(AppSettings::cacheDir(), true);
    processDir(appSpecificQtCacheDir(), false);

    // Unused Epic manifest cache files for uninstalled games
    const QString manifestDir = AppSettings::dataDir() + QStringLiteral("/epic_manifests");
    if (QDir(manifestDir).exists()) {
        const QSet<QString> installedApps = collectInstalledEpicAppNames(db);
        const bool hasActiveDownloads = dl && dl->totalPendingCount() > 0;
        if (!hasActiveDownloads) {
            QDirIterator it(manifestDir, QDir::Files | QDir::NoSymLinks);
            while (it.hasNext()) {
                it.next();
                const QFileInfo fi = it.fileInfo();
                if (installedApps.contains(fi.completeBaseName())) continue;
                const qint64 sz = fi.size();
                if (performDelete) {
                    if (QFile::remove(fi.absoluteFilePath())) {
                        res.bytes += sz;
                        ++res.files;
                    }
                } else {
                    res.bytes += sz;
                    ++res.files;
                }
            }
        }
    }
    return res;
}

StorageScanResult scanLogs(LaunchPipeline* lp) {
    StorageScanResult res;
    const QSet<QString> runningIds = collectRunningGameIds(lp);
    QDir dir(AppSettings::logsDir());
    if (!dir.exists()) return res;
    for (const QFileInfo& fi : dir.entryInfoList(QDir::Files | QDir::NoDotAndDotDot)) {
        if (fi.suffix().compare(QStringLiteral("log"), Qt::CaseInsensitive) == 0 &&
            runningIds.contains(fi.completeBaseName())) {
            continue;
        }
        res.bytes += fi.size();
        ++res.files;
    }
    return res;
}

StorageScanResult scanOrCleanOldArtwork(DatabaseManager* db, bool performDelete) {
    StorageScanResult res;
    const QString artRootPath = AppSettings::artworkDir();
    QDir artRoot(artRootPath);
    if (!artRoot.exists()) return res;

    const QSet<QString> activeFiles = collectAllActiveArtPaths(db);
    QDirIterator it(artRootPath, QDir::Files | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        const QFileInfo fi = it.fileInfo();
        const QString clean = QDir::cleanPath(fi.absoluteFilePath());
        if (activeFiles.contains(clean)) continue;

        const qint64 sz = fi.size();
        if (performDelete) {
            if (QFile::remove(clean)) {
                res.bytes += sz;
                ++res.files;
            }
        } else {
            res.bytes += sz;
            ++res.files;
        }
    }
    if (performDelete) removeEmptySubdirs(artRootPath);
    return res;
}

StorageScanResult scanOrCleanEpicArtworkCache(DatabaseManager* db, bool performDelete) {
    StorageScanResult res;
    const QString artRootPath = AppSettings::artworkDir();
    QDir artRoot(artRootPath);
    if (!artRoot.exists()) return res;

    const QSet<QString> installedFiles = collectInstalledGameArtPaths(db);
    const QFileInfoList subDirs = artRoot.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo& sd : subDirs) {
        if (!sd.fileName().startsWith(QStringLiteral("epic_"))) continue;
        QDirIterator it(sd.absoluteFilePath(), QDir::Files | QDir::NoSymLinks, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            const QFileInfo fi = it.fileInfo();
            const QString clean = QDir::cleanPath(fi.absoluteFilePath());
            if (installedFiles.contains(clean)) continue;
            const qint64 sz = fi.size();
            if (performDelete) {
                if (QFile::remove(clean)) {
                    res.bytes += sz;
                    ++res.files;
                }
            } else {
                res.bytes += sz;
                ++res.files;
            }
        }
        if (performDelete) {
            removeEmptySubdirs(sd.absoluteFilePath());
            QDir d(sd.absoluteFilePath());
            if (d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).isEmpty()) {
                artRoot.rmdir(sd.fileName());
            }
        }
    }
    return res;
}

} // namespace

QVariantMap UiController::getStorageCleaningStats() const {
    const StorageScanResult cache = scanOrCleanCache(m_db, m_dl, false);
    const StorageScanResult logs = scanLogs(m_launchPipeline);
    const StorageScanResult oldArt = scanOrCleanOldArtwork(m_db, false);
    const StorageScanResult epicArt = scanOrCleanEpicArtworkCache(m_db, false);
    const qint64 cleanAllBytes = cache.bytes + logs.bytes + oldArt.bytes;
    const int cleanAllFiles = cache.files + logs.files + oldArt.files;

    QVariantMap m;
    m[QStringLiteral("cacheBytes")] = cache.bytes;
    m[QStringLiteral("cacheFiles")] = cache.files;
    m[QStringLiteral("cacheFormatted")] = DownloadManager::formatBytes(cache.bytes);
    m[QStringLiteral("logsBytes")] = logs.bytes;
    m[QStringLiteral("logsFiles")] = logs.files;
    m[QStringLiteral("logsFormatted")] = DownloadManager::formatBytes(logs.bytes);
    m[QStringLiteral("oldArtworkBytes")] = oldArt.bytes;
    m[QStringLiteral("oldArtworkFiles")] = oldArt.files;
    m[QStringLiteral("oldArtworkFormatted")] = DownloadManager::formatBytes(oldArt.bytes);
    m[QStringLiteral("epicArtworkBytes")] = epicArt.bytes;
    m[QStringLiteral("epicArtworkFiles")] = epicArt.files;
    m[QStringLiteral("epicArtworkFormatted")] = DownloadManager::formatBytes(epicArt.bytes);
    m[QStringLiteral("cleanAllBytes")] = cleanAllBytes;
    m[QStringLiteral("cleanAllFiles")] = cleanAllFiles;
    m[QStringLiteral("cleanAllFormatted")] = DownloadManager::formatBytes(cleanAllBytes);
    return m;
}

QVariantMap UiController::clearCacheStorage() {
    const StorageScanResult res = scanOrCleanCache(m_db, m_dl, true);
    emit storageStatsChanged();
    const QString freedStr = DownloadManager::formatBytes(res.bytes);
    emit toastRequested(
        res.files > 0
            ? QStringLiteral("Cleared %1 (%2 cache file(s)).").arg(freedStr).arg(res.files)
            : QStringLiteral("No cache files to clear."),
        false);
    return {{QStringLiteral("freedBytes"), res.bytes},
            {QStringLiteral("removedFiles"), res.files},
            {QStringLiteral("freedFormatted"), freedStr}};
}

QVariantMap UiController::clearLogsStorage() {
    qint64 freed = 0;
    int removed = 0;
    if (m_diagMgr) {
        removed = m_diagMgr->clearInactiveGameLogs(collectRunningGameIds(m_launchPipeline), &freed);
    }
    emit storageStatsChanged();
    const QString freedStr = DownloadManager::formatBytes(freed);
    emit toastRequested(
        removed > 0
            ? QStringLiteral("Cleared %1 (%2 log file(s)).").arg(freedStr).arg(removed)
            : QStringLiteral("No inactive log files to clear."),
        false);
    return {{QStringLiteral("freedBytes"), freed},
            {QStringLiteral("removedFiles"), removed},
            {QStringLiteral("freedFormatted"), freedStr}};
}

QVariantMap UiController::clearOldArtworkStorage() {
    const StorageScanResult res = scanOrCleanOldArtwork(m_db, true);
    emit storageStatsChanged();
    const QString freedStr = DownloadManager::formatBytes(res.bytes);
    emit toastRequested(
        res.files > 0
            ? QStringLiteral("Removed %1 of old artwork (%2 file(s)).").arg(freedStr).arg(res.files)
            : QStringLiteral("No old or unused artwork files found."),
        false);
    return {{QStringLiteral("freedBytes"), res.bytes},
            {QStringLiteral("removedFiles"), res.files},
            {QStringLiteral("freedFormatted"), freedStr}};
}

QVariantMap UiController::clearEpicArtworkCache() {
    const StorageScanResult res = scanOrCleanEpicArtworkCache(m_db, true);
    if (m_db) {
        m_db->clearEpicLibraryArtworkPaths();
    }
    if (m_epicSvc) {
        m_epicSvc->resetCachedArtworkState();
    }
    emit storageStatsChanged();
    const QString freedStr = DownloadManager::formatBytes(res.bytes);
    emit toastRequested(
        res.files > 0
            ? QStringLiteral("Cleared %1 of Epic thumbnail cache (%2 file(s)).").arg(freedStr).arg(res.files)
            : QStringLiteral("No cached Epic thumbnails to clear."),
        false);
    return {{QStringLiteral("freedBytes"), res.bytes},
            {QStringLiteral("removedFiles"), res.files},
            {QStringLiteral("freedFormatted"), freedStr}};
}

QVariantMap UiController::clearAllCleanableStorage() {
    const StorageScanResult cache = scanOrCleanCache(m_db, m_dl, true);
    qint64 logFreed = 0;
    int logRemoved = 0;
    if (m_diagMgr) {
        logRemoved = m_diagMgr->clearInactiveGameLogs(collectRunningGameIds(m_launchPipeline), &logFreed);
    }
    const StorageScanResult oldArt = scanOrCleanOldArtwork(m_db, true);
    const qint64 totalBytes = cache.bytes + logFreed + oldArt.bytes;
    const int totalFiles = cache.files + logRemoved + oldArt.files;

    emit storageStatsChanged();
    const QString freedStr = DownloadManager::formatBytes(totalBytes);
    emit toastRequested(
        totalFiles > 0
            ? QStringLiteral("Cleaned %1 across %2 cache, log, and old artwork file(s).").arg(freedStr).arg(totalFiles)
            : QStringLiteral("Storage is already clean."),
        false);
    return {{QStringLiteral("freedBytes"), totalBytes},
            {QStringLiteral("removedFiles"), totalFiles},
            {QStringLiteral("freedFormatted"), freedStr}};
}

} // namespace Tsuki

