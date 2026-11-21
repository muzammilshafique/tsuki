#include "DownloadManager.h"
#include "../core/AppSettings.h"
#include "../core/DatabaseManager.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QNetworkRequest>
#include <QProcess>
#include <QUuid>
#include <algorithm>

namespace Tsuki {

DownloadManager::DownloadManager(QObject* parent)
    : QAbstractListModel(parent)
{
    m_bucketTimer.start();
    m_throttleTimer.setInterval(100);
    connect(&m_throttleTimer, &QTimer::timeout, this, [this]() {
        refillBandwidthBucket();
        for (DownloadTask* t : m_taskList) {
            if (!t->isExternal && t->reply && t->file && !t->isPaused && !t->isExtracting) {
                const int limitKBps = speedLimitKBps();
                if (limitKBps > 0 && t->reply->bytesAvailable() > 0) {
                    const qint64 allow = qMax<qint64>(4096, static_cast<qint64>(m_bucketTokensBytes));
                    if (allow > 0) {
                        const QByteArray chunk = t->reply->read(allow);
                        if (!chunk.isEmpty()) {
                            m_bucketTokensBytes = qMax(0.0, m_bucketTokensBytes - static_cast<double>(chunk.size()));
                            t->file->write(chunk);
                        }
                    }
                }
            }
        }
        updateAggregateSpeed();
    });
}

DownloadManager::~DownloadManager() {
    m_throttleTimer.stop();
    const QStringList keys = m_tasks.keys();
    for (const QString& k : keys) {
        DownloadTask* t = m_tasks.value(k);
        if (t && t->isExternal) {
            cleanupTask(k);
        } else {
            cancelDownload(k);
        }
    }
}

void DownloadManager::setAppSettings(AppSettings* settings) {
    if (m_settings == settings) return;
    if (m_settings) {
        disconnect(m_settings, nullptr, this, nullptr);
    }
    m_settings = settings;
    if (m_settings) {
        auto primeBucket = [this]() {
            const int limitKBps = speedLimitKBps();
            if (limitKBps > 0) {
                const double bytesPerSec = static_cast<double>(limitKBps) * 1024.0;
                m_bucketTokensBytes = qMax(bytesPerSec, 256.0 * 1024.0);
                m_bucketTimer.restart();
            } else {
                m_bucketTokensBytes = 0.0;
            }
        };
        primeBucket();
        connect(m_settings, &AppSettings::downloadSettingsChanged, this, [this, primeBucket]() {
            primeBucket();
            applyReadBufferLimits();
            pumpGameQueue();
        });
    }
}

void DownloadManager::setDatabaseManager(DatabaseManager* db) {
    m_db = db;
}

int DownloadManager::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_taskList.size();
}

int DownloadManager::rowForId(const QString& id) const {
    for (int i = 0; i < m_taskList.size(); ++i) {
        if (m_taskList.at(i)->id == id) return i;
    }
    return -1;
}

int DownloadManager::activeDownloadCount() const {
    int count = 0;
    for (const DownloadTask* t : m_taskList) {
        if (!t->isQueued) ++count;
    }
    return count;
}

int DownloadManager::queuedDownloadCount() const {
    int count = 0;
    for (const DownloadTask* t : m_taskList) {
        if (t->isQueued) ++count;
    }
    return count;
}

int DownloadManager::activeGameQueueCount() const {
    int count = 0;
    for (const DownloadTask* t : m_taskList) {
        if (t->isGameQueueItem && !t->isQueued && !t->isPaused) {
            ++count;
        }
    }
    return count;
}

QVariant DownloadManager::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_taskList.size()) {
        return QVariant();
    }
    const DownloadTask* t = m_taskList.at(index.row());
    switch (role) {
    case IdRole:
        return t->id;
    case TitleRole:
    case DisplayNameRole:
    case Qt::DisplayRole:
        return t->title;
    case TypeRole:
        return t->isExternal ? 0 : 1;
    case KindRole:
        return t->kind;
    case AppNameRole:
        return t->appName;
    case CoverPathRole:
        return t->coverPath;
    case ProgressRole:
        return t->progress;
    case DownloadedSizeStrRole:
        return formatBytes(t->bytesDownloaded);
    case TotalSizeStrRole:
        return t->totalBytes > 0 ? formatBytes(t->totalBytes) : QString();
    case SpeedTextRole:
        return t->speedText;
    case StageTextRole:
        if (t->isQueued) return QStringLiteral("Queued");
        if (t->isPaused) return QStringLiteral("Paused");
        if (t->isExtracting) return QStringLiteral("Extracting…");
        return t->stageText.isEmpty() ? QStringLiteral("Downloading…") : t->stageText;
    case EtaRole:
        if (t->isQueued) return QStringLiteral("Queued");
        if (t->isExtracting) return QStringLiteral("Extracting…");
        return t->eta;
    case StatusRole:
        if (t->isQueued) return QStringLiteral("queued");
        if (t->isPaused) return QStringLiteral("paused");
        if (t->isExtracting) return QStringLiteral("extracting");
        return QStringLiteral("active");
    case IsPausedRole:
        return t->isPaused;
    case IsQueuedRole:
        return t->isQueued;
    case IsExtractingRole:
        return t->isExtracting;
    case IsExternalRole:
        return t->isExternal;
    default:
        return QVariant();
    }
}

QHash<int, QByteArray> DownloadManager::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[TitleRole] = "title";
    roles[DisplayNameRole] = "displayName";
    roles[TypeRole] = "type";
    roles[KindRole] = "kind";
    roles[AppNameRole] = "appName";
    roles[CoverPathRole] = "coverPath";
    roles[ProgressRole] = "progress";
    roles[DownloadedSizeStrRole] = "downloadedSizeStr";
    roles[TotalSizeStrRole] = "totalSizeStr";
    roles[SpeedTextRole] = "speedText";
    roles[StageTextRole] = "stageText";
    roles[EtaRole] = "eta";
    roles[StatusRole] = "status";
    roles[IsPausedRole] = "isPaused";
    roles[IsQueuedRole] = "isQueued";
    roles[IsExtractingRole] = "isExtracting";
    roles[IsExternalRole] = "isExternal";
    return roles;
}

QString DownloadManager::formatBytes(qint64 bytes) {
    if (bytes <= 0) return QStringLiteral("0 B");
    double b = static_cast<double>(bytes);
    if (b < 1024.0) return QStringLiteral("%1 B").arg(bytes);
    b /= 1024.0;
    if (b < 1024.0) return QStringLiteral("%1 KB").arg(b, 0, 'f', 1);
    b /= 1024.0;
    if (b < 1024.0) return QStringLiteral("%1 MB").arg(b, 0, 'f', 1);
    b /= 1024.0;
    return QStringLiteral("%1 GB").arg(b, 0, 'f', 2);
}

bool DownloadManager::verifyFileSha512(const QString& filePath, const QString& expectedHex) {
    const QString cleanExpected = expectedHex.trimmed().toLower();
    if (cleanExpected.isEmpty()) return true;
    QFile f(filePath);
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) return false;
    QCryptographicHash hash(QCryptographicHash::Sha512);
    if (!hash.addData(&f)) {
        f.close();
        return false;
    }
    f.close();
    return QString::fromLatin1(hash.result().toHex()).toLower() == cleanExpected;
}

QVariantList DownloadManager::activeDownloads() const {
    QVariantList list;
    for (const DownloadTask* t : m_taskList) {
        QVariantMap m;
        m["id"] = t->id;
        m["title"] = t->title;
        m["displayName"] = t->title;
        m["type"] = t->isExternal ? 0 : 1;
        m["kind"] = t->kind;
        m["appName"] = t->appName;
        m["coverPath"] = t->coverPath;
        m["progress"] = t->progress;
        m["downloadedSizeStr"] = formatBytes(t->bytesDownloaded);
        m["totalSizeStr"] = t->totalBytes > 0 ? formatBytes(t->totalBytes) : QString();
        m["speedText"] = t->speedText;
        m["stageText"] = t->isQueued ? QStringLiteral("Queued")
                                     : (t->isPaused ? QStringLiteral("Paused")
                                                    : (t->isExtracting ? QStringLiteral("Extracting…") : t->stageText));
        m["eta"] = t->isQueued ? QStringLiteral("Queued") : (t->isExtracting ? QStringLiteral("Extracting…") : t->eta);
        m["status"] = t->isQueued ? QStringLiteral("queued") : (t->isPaused ? QStringLiteral("paused") : QStringLiteral("active"));
        m["isPaused"] = t->isPaused;
        m["isQueued"] = t->isQueued;
        m["isExtracting"] = t->isExtracting;
        m["isExternal"] = t->isExternal;
        list.append(m);
    }
    return list;
}

QVariantList DownloadManager::runnerDownloads() const {
    QVariantList list;
    for (const DownloadTask* t : m_taskList) {
        if (t->isGameQueueItem) continue;
        if (t->kind != QLatin1String("runner") &&
            t->kind != QLatin1String("runtime") &&
            t->kind != QLatin1String("tool")) {
            continue;
        }
        QVariantMap m;
        m["id"] = t->id;
        m["title"] = t->title;
        m["displayName"] = t->title;
        m["kind"] = t->kind;
        m["progress"] = t->progress;
        m["downloadedSizeStr"] = formatBytes(t->bytesDownloaded);
        m["totalSizeStr"] = t->totalBytes > 0 ? formatBytes(t->totalBytes) : QString();
        m["speedText"] = t->speedText;
        m["stageText"] = t->isPaused ? QStringLiteral("Paused")
                                     : (t->isExtracting ? QStringLiteral("Extracting…") : t->stageText);
        m["eta"] = t->isExtracting ? QStringLiteral("Extracting…") : t->eta;
        m["isPaused"] = t->isPaused;
        m["isExtracting"] = t->isExtracting;
        list.append(m);
    }
    return list;
}

int DownloadManager::runnerDownloadCount() const {
    int n = 0;
    for (const DownloadTask* t : m_taskList) {
        if (!t->isGameQueueItem &&
            (t->kind == QLatin1String("runner") ||
             t->kind == QLatin1String("runtime") ||
             t->kind == QLatin1String("tool"))) {
            ++n;
        }
    }
    return n;
}

bool DownloadManager::isMediaDownloading(const QString& id) const {
    return m_tasks.contains(id);
}

int DownloadManager::speedLimitKBps() const {
    return m_settings ? qMax(0, m_settings->downloadSpeedLimitKBps()) : 0;
}

int DownloadManager::maxConcurrentChunkWorkers() const {
    return m_settings ? qBound(1, m_settings->maxConcurrentChunkWorkers(), 16) : 6;
}

int DownloadManager::maxConcurrentGameDownloads() const {
    return m_settings ? qBound(1, m_settings->maxConcurrentGameDownloads(), 4) : 1;
}

qint64 DownloadManager::recommendedReadBufferSize(int activeStreams) const {
    const int limitKBps = speedLimitKBps();
    if (limitKBps <= 0) return 0; // Unlimited
    const int streams = qMax(1, activeStreams);
    const qint64 perStreamBytesPerSec = (static_cast<qint64>(limitKBps) * 1024LL) / streams;
    return qBound(qint64(8192), perStreamBytesPerSec / 4, qint64(512 * 1024));
}

void DownloadManager::refillBandwidthBucket() {
    const int limitKBps = speedLimitKBps();
    const qint64 elapsedMs = m_bucketTimer.restart();
    if (limitKBps <= 0) {
        m_bucketTokensBytes = 0.0;
        return;
    }
    const double bytesPerSec = static_cast<double>(limitKBps) * 1024.0;
    const double added = (bytesPerSec * static_cast<double>(qMax<qint64>(0, elapsedMs))) / 1000.0;
    const double maxBurst = qMax(bytesPerSec, 256.0 * 1024.0);
    m_bucketTokensBytes = qMin(maxBurst, m_bucketTokensBytes + added);
}

bool DownloadManager::tryConsumeBandwidthBytes(qint64 bytes) {
    const int limitKBps = speedLimitKBps();
    if (limitKBps <= 0 || bytes <= 0) return true;
    refillBandwidthBucket();
    if (m_bucketTokensBytes >= static_cast<double>(bytes)) {
        m_bucketTokensBytes -= static_cast<double>(bytes);
        return true;
    }
    return false;
}

qint64 DownloadManager::msUntilBandwidthAvailable(qint64 bytes) const {
    const int limitKBps = speedLimitKBps();
    if (limitKBps <= 0 || bytes <= 0) return 0;
    const double bytesPerSec = static_cast<double>(limitKBps) * 1024.0;
    const double deficit = static_cast<double>(bytes) - m_bucketTokensBytes;
    if (deficit <= 0.0) return 0;
    return qBound(qint64(20), static_cast<qint64>((deficit / bytesPerSec) * 1000.0), qint64(3000));
}

void DownloadManager::applyReadBufferLimits() {
    int activeHttp = 0;
    for (DownloadTask* t : m_taskList) {
        if (!t->isExternal && t->reply && !t->isPaused) ++activeHttp;
    }
    const qint64 bufSize = recommendedReadBufferSize(qMax(1, activeHttp));
    for (DownloadTask* t : m_taskList) {
        if (!t->isExternal && t->reply) {
            t->reply->setReadBufferSize(bufSize);
        }
    }
}

void DownloadManager::updateAggregateSpeed() {
    double totalBps = 0.0;
    for (const DownloadTask* t : m_taskList) {
        if (!t->isPaused && !t->isQueued && !t->isExtracting) {
            totalBps += qMax(0.0, t->speedBps);
        }
    }
    const QString text = (totalBps > 1.0) ? QStringLiteral("%1/s").arg(formatBytes(static_cast<qint64>(totalBps))) : QString();
    if (m_aggregateSpeedText != text) {
        m_aggregateSpeedText = text;
        emit aggregateSpeedChanged();
    }
}

QString DownloadManager::enqueueDownload(const QString& id,
                                         const QString& title,
                                         const QUrl& url,
                                         const QString& destinationFile,
                                         const QString& extractToDir,
                                         std::function<void(bool, const QString&)> onComplete,
                                         const QString& expectedSha512,
                                         const QString& kind)
{
    const QString taskId = id.isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : id;
    if (m_tasks.contains(taskId)) {
        return taskId;
    }

    QFileInfo fi(destinationFile);
    QDir().mkpath(fi.absolutePath());

    auto* task = new DownloadTask();
    task->id = taskId;
    task->title = title;
    task->kind = kind.isEmpty() ? QStringLiteral("tool") : kind;
    task->url = url;
    task->destinationFile = destinationFile;
    task->extractToDir = extractToDir;
    task->expectedSha512 = expectedSha512.trimmed();
    task->callback = std::move(onComplete);
    task->stageText = QStringLiteral("Downloading…");
    task->file = new QFile(destinationFile + QStringLiteral(".part"));

    if (!task->file->open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        const QString err = QStringLiteral("Cannot write to %1").arg(destinationFile);
        delete task->file;
        if (task->callback) task->callback(false, err);
        delete task;
        emit downloadFailed(taskId, err);
        return taskId;
    }

    const int newRow = m_taskList.size();
    beginInsertRows(QModelIndex(), newRow, newRow);
    m_taskList.append(task);
    m_tasks.insert(taskId, task);
    endInsertRows();

    if (!m_throttleTimer.isActive()) {
        m_throttleTimer.start();
    }
    emit activeDownloadsChanged();
    startRequest(taskId);
    return taskId;
}

bool DownloadManager::registerExternalTask(const QString& id,
                                           const QString& title,
                                           const QString& kind,
                                           const QString& appName,
                                           const QString& coverPath,
                                           bool isGameQueueItem,
                                           ExternalAdapter adapter,
                                           bool startImmediatelyIfSlotFree,
                                           bool initialPaused)
{
    if (id.isEmpty() || m_tasks.contains(id)) {
        return false;
    }

    const bool shouldQueue = !initialPaused && isGameQueueItem &&
                             (m_pausedForGameplay || activeGameQueueCount() >= maxConcurrentGameDownloads());

    auto* task = new DownloadTask();
    task->id = id;
    task->title = title;
    task->kind = kind.isEmpty() ? QStringLiteral("epic_install") : kind;
    task->appName = appName;
    task->coverPath = coverPath;
    task->isExternal = true;
    task->isGameQueueItem = isGameQueueItem;
    task->isPaused = initialPaused;
    task->isQueued = shouldQueue;
    task->stageText = initialPaused ? QStringLiteral("Paused")
                                    : (shouldQueue ? QStringLiteral("Queued") : QStringLiteral("Preparing…"));
    task->eta = initialPaused ? QStringLiteral("Paused")
                              : (shouldQueue ? QStringLiteral("Queued") : QString());
    task->adapter = std::move(adapter);

    const int newRow = m_taskList.size();
    beginInsertRows(QModelIndex(), newRow, newRow);
    m_taskList.append(task);
    m_tasks.insert(id, task);
    endInsertRows();

    if (!m_throttleTimer.isActive()) {
        m_throttleTimer.start();
    }
    emit activeDownloadsChanged();

    if (!initialPaused && !shouldQueue && startImmediatelyIfSlotFree && task->adapter.startFn) {
        task->adapter.startFn();
    }
    return !initialPaused && !shouldQueue;
}

void DownloadManager::updateExternalTask(const QString& id,
                                         double progress,
                                         qint64 downloadedBytes,
                                         qint64 totalBytes,
                                         double speedBps,
                                         const QString& speedText,
                                         const QString& eta,
                                         const QString& stage,
                                         bool isPaused,
                                         bool isQueued)
{
    DownloadTask* t = m_tasks.value(id, nullptr);
    if (!t || !t->isExternal) return;

    const bool stateChanged = (t->isPaused != isPaused) || (t->isQueued != isQueued);
    t->progress = progress;
    t->bytesDownloaded = downloadedBytes;
    t->totalBytes = totalBytes;
    t->speedBps = (isPaused || isQueued) ? 0.0 : speedBps;
    t->speedText = (isPaused || isQueued) ? QString() : speedText;
    t->eta = isQueued ? QStringLiteral("Queued") : eta;
    t->stageText = isQueued ? QStringLiteral("Queued") : stage;
    t->isPaused = isPaused;
    t->isQueued = isQueued;

    const int row = rowForId(id);
    if (row >= 0) {
        emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                         {ProgressRole, DownloadedSizeStrRole, TotalSizeStrRole,
                          SpeedTextRole, StageTextRole, EtaRole, StatusRole,
                          IsPausedRole, IsQueuedRole});
    }
    emit downloadProgress(id, progress);
    emit downloadProgressDetailed(id, progress, downloadedBytes, totalBytes, t->speedBps, t->eta);
    if (stateChanged) {
        emit activeDownloadsChanged();
        pumpGameQueue();
    }
    updateAggregateSpeed();
}

void DownloadManager::finishExternalTask(const QString& id,
                                         bool success,
                                         const QString& summaryOrError,
                                         const QString& targetGameId,
                                         const QString& targetPath)
{
    DownloadTask* t = m_tasks.value(id, nullptr);
    if (!t) return;

    const QString title = t->title;
    const QString kind = t->kind;
    const QString appName = t->appName;
    const QString coverPath = t->coverPath;
    m_gameplayPausedIds.remove(id);
    if (m_db) {
        m_db->removeQueuedDownload(id);
    }

    cleanupTask(id);
    appendCompletedRecord(id, title, kind, appName, coverPath, success, summaryOrError, targetGameId, targetPath);

    if (success) {
        emit downloadFinished(id, targetPath);
    } else {
        emit downloadFailed(id, summaryOrError);
    }
    pumpGameQueue();
    updateAggregateSpeed();
}

void DownloadManager::appendCompletedRecord(const QString& id,
                                            const QString& title,
                                            const QString& kind,
                                            const QString& appName,
                                            const QString& coverPath,
                                            bool success,
                                            const QString& message,
                                            const QString& targetGameId,
                                            const QString& targetPath)
{
    QVariantMap rec;
    rec[QStringLiteral("id")] = id;
    rec[QStringLiteral("title")] = title;
    rec[QStringLiteral("kind")] = kind;
    rec[QStringLiteral("appName")] = appName;
    rec[QStringLiteral("coverPath")] = coverPath;
    rec[QStringLiteral("success")] = success;
    rec[QStringLiteral("message")] = message;
    rec[QStringLiteral("gameId")] = targetGameId;
    rec[QStringLiteral("targetGameId")] = targetGameId;
    rec[QStringLiteral("targetPath")] = targetPath;
    rec[QStringLiteral("timestamp")] = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm"));
    m_completedHistory.prepend(rec);
    while (m_completedHistory.size() > 30) {
        m_completedHistory.removeLast();
    }
    emit completedDownloadsChanged();
}

void DownloadManager::clearCompletedHistory() {
    if (m_completedHistory.isEmpty()) return;
    m_completedHistory.clear();
    emit completedDownloadsChanged();
}

void DownloadManager::pumpGameQueue() {
    if (m_pausedForGameplay) return;
    const int limit = maxConcurrentGameDownloads();
    while (activeGameQueueCount() < limit) {
        DownloadTask* nextQueued = nullptr;
        for (DownloadTask* t : m_taskList) {
            if (t->isGameQueueItem && t->isQueued && !t->isPaused) {
                nextQueued = t;
                break;
            }
        }
        if (!nextQueued) break;
        nextQueued->isQueued = false;
        nextQueued->stageText = QStringLiteral("Starting…");
        nextQueued->eta.clear();
        const int row = rowForId(nextQueued->id);
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                             {IsQueuedRole, StatusRole, StageTextRole, EtaRole});
        }
        emit activeDownloadsChanged();
        if (nextQueued->adapter.startFn) {
            nextQueued->adapter.startFn();
        }
    }
}

void DownloadManager::moveQueueItemUp(const QString& id) {
    const int row = rowForId(id);
    if (row <= 0) return;
    beginMoveRows(QModelIndex(), row, row, QModelIndex(), row - 1);
    m_taskList.swapItemsAt(row, row - 1);
    endMoveRows();
    emit activeDownloadsChanged();
}

void DownloadManager::moveQueueItemDown(const QString& id) {
    const int row = rowForId(id);
    if (row < 0 || row >= m_taskList.size() - 1) return;
    beginMoveRows(QModelIndex(), row, row, QModelIndex(), row + 2);
    m_taskList.swapItemsAt(row, row + 1);
    endMoveRows();
    emit activeDownloadsChanged();
}

void DownloadManager::prioritizeDownload(const QString& id) {
    const int row = rowForId(id);
    if (row < 0) return;
    DownloadTask* target = m_taskList.at(row);
    if (row > 0) {
        beginMoveRows(QModelIndex(), row, row, QModelIndex(), 0);
        m_taskList.move(row, 0);
        endMoveRows();
    }
    if (target->isQueued) {
        // Pause lowest-priority active game download if at capacity so prioritized item starts immediately
        if (target->isGameQueueItem && activeGameQueueCount() >= maxConcurrentGameDownloads()) {
            for (int i = m_taskList.size() - 1; i >= 0; --i) {
                DownloadTask* other = m_taskList.at(i);
                if (other != target && other->isGameQueueItem && !other->isQueued && !other->isPaused) {
                    togglePauseDownload(other->id);
                    break;
                }
            }
        }
        // togglePauseDownload() above may have already pumped `target` into active state; guard against double-start
        if (target->isQueued) {
            target->isPaused = false;
            target->isQueued = false;
            target->stageText = QStringLiteral("Starting…");
            emit dataChanged(createIndex(0, 0), createIndex(0, 0),
                             {IsPausedRole, IsQueuedRole, StatusRole, StageTextRole});
            if (target->adapter.startFn) {
                target->adapter.startFn();
            }
        }
    } else if (target->isPaused) {
        togglePauseDownload(target->id);
    }
    emit activeDownloadsChanged();
}

void DownloadManager::pauseAll() {
    for (DownloadTask* t : m_taskList) {
        if (!t->isPaused && !t->isQueued && !t->isExtracting) {
            togglePauseDownload(t->id);
        }
    }
}

void DownloadManager::resumeAll() {
    m_pausedForGameplay = false;
    m_gameplayPausedIds.clear();
    for (DownloadTask* t : m_taskList) {
        if (t->isPaused) {
            togglePauseDownload(t->id);
        }
    }
    pumpGameQueue();
}

void DownloadManager::pauseForGameplay() {
    if (m_settings && !m_settings->pauseDownloadsOnGameLaunch()) return;
    if (m_pausedForGameplay) return;
    m_pausedForGameplay = true;
    m_gameplayPausedIds.clear();

    for (DownloadTask* t : m_taskList) {
        if (!t->isPaused && !t->isQueued && !t->isExtracting) {
            m_gameplayPausedIds.insert(t->id);
            togglePauseDownload(t->id);
        }
    }
    emit activeDownloadsChanged();
}

void DownloadManager::resumeAfterGameplay() {
    if (!m_pausedForGameplay) return;
    m_pausedForGameplay = false;
    const QSet<QString> toResume = m_gameplayPausedIds;
    m_gameplayPausedIds.clear();

    for (const QString& id : toResume) {
        DownloadTask* t = m_tasks.value(id, nullptr);
        if (t && t->isPaused) {
            togglePauseDownload(id);
        }
    }
    pumpGameQueue();
    emit activeDownloadsChanged();
}

void DownloadManager::startRequest(const QString& taskId) {
    if (!m_tasks.contains(taskId)) return;
    DownloadTask* task = m_tasks.value(taskId);

    QNetworkRequest req(task->url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0 (Linux; Qt6)"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    if (task->resumeOffset > 0) {
        req.setRawHeader("Range", QByteArray("bytes=") + QByteArray::number(task->resumeOffset) + "-");
    }

    task->timer.start();
    QNetworkReply* reply = m_nam.get(req);
    reply->setReadBufferSize(recommendedReadBufferSize(1));
    task->reply = reply;

    connect(reply, &QNetworkReply::readyRead, this, [this, taskId, reply]() {
        if (!m_tasks.contains(taskId)) return;
        DownloadTask* t = m_tasks.value(taskId);
        if (t->reply != reply || !t->file) return;

        const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (statusCode == 200 && t->resumeOffset > 0) {
            t->resumeOffset = 0;
            t->file->resize(0);
            t->file->seek(0);
        }

        if (speedLimitKBps() > 0) {
            refillBandwidthBucket();
            const qint64 allow = static_cast<qint64>(m_bucketTokensBytes);
            if (allow <= 0) return; // Throttle timer will drain when tokens refill
            const QByteArray chunk = reply->read(allow);
            if (!chunk.isEmpty()) {
                m_bucketTokensBytes = qMax(0.0, m_bucketTokensBytes - static_cast<double>(chunk.size()));
                t->file->write(chunk);
            }
        } else {
            const QByteArray chunk = reply->readAll();
            t->file->write(chunk);
        }
    });

    connect(reply, &QNetworkReply::downloadProgress, this, [this, taskId, reply](qint64 bytesReceived, qint64 bytesTotal) {
        if (!m_tasks.contains(taskId)) return;
        DownloadTask* t = m_tasks.value(taskId);
        if (t->reply != reply || t->isPaused) return;

        const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const qint64 offset = (statusCode == 200) ? 0 : t->resumeOffset;
        const qint64 totalDl = offset + bytesReceived;
        const qint64 totalSize = bytesTotal > 0 ? (offset + bytesTotal) : 0;
        t->bytesDownloaded = totalDl;
        t->totalBytes = totalSize;

        double pct = 0.0;
        if (totalSize > 0) {
            pct = (static_cast<double>(totalDl) / static_cast<double>(totalSize)) * (t->extractToDir.isEmpty() ? 100.0 : 90.0);
        }
        t->progress = pct;

        const qint64 elapsedMs = qMax<qint64>(1, t->timer.elapsed());
        const double speedBps = (static_cast<double>(bytesReceived) * 1000.0) / static_cast<double>(elapsedMs);
        t->speedBps = speedBps;
        t->speedText = QStringLiteral("%1/s").arg(formatBytes(static_cast<qint64>(speedBps)));

        QString etaStr;
        if (speedBps > 100.0 && totalSize > totalDl) {
            const qint64 remSecs = static_cast<qint64>((totalSize - totalDl) / speedBps);
            if (remSecs < 60) etaStr = QStringLiteral("%1s left").arg(remSecs);
            else etaStr = QStringLiteral("%1m %2s left").arg(remSecs / 60).arg(remSecs % 60);
        } else {
            etaStr = t->speedText;
        }
        t->eta = etaStr;

        emit downloadProgress(taskId, t->progress);
        emit downloadProgressDetailed(taskId, t->progress, totalDl, totalSize, speedBps, etaStr);

        const int row = m_taskList.indexOf(t);
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                             {ProgressRole, DownloadedSizeStrRole, TotalSizeStrRole, SpeedTextRole, EtaRole});
        }
        updateAggregateSpeed();
    });

    connect(reply, &QNetworkReply::finished, this, [this, taskId, reply]() {
        if (!m_tasks.contains(taskId)) {
            reply->deleteLater();
            return;
        }
        DownloadTask* t = m_tasks.value(taskId);
        if (t->reply != reply) {
            reply->deleteLater();
            return;
        }
        t->reply = nullptr;

        if (t->isPaused) {
            reply->deleteLater();
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            const QString err = reply->errorString();
            const QString title = t->title;
            const QString kind = t->kind;
            reply->deleteLater();
            auto cb = t->callback;
            cleanupTask(taskId);
            appendCompletedRecord(taskId, title, kind, QString(), QString(), false, err, QString(), QString());
            if (cb) cb(false, err);
            emit downloadFailed(taskId, err);
            return;
        }

        if (t->file) {
            const QByteArray remaining = reply->readAll();
            if (!remaining.isEmpty()) t->file->write(remaining);
            t->file->flush();
            t->file->close();
        }
        reply->deleteLater();

        QFile::remove(t->destinationFile);
        QFile::rename(t->destinationFile + QStringLiteral(".part"), t->destinationFile);

        if (!t->expectedSha512.isEmpty() && !verifyFileSha512(t->destinationFile, t->expectedSha512)) {
            const QString err = QStringLiteral("SHA-512 checksum verification failed for %1").arg(t->title);
            const QString title = t->title;
            const QString kind = t->kind;
            QFile::remove(t->destinationFile);
            auto cb = t->callback;
            cleanupTask(taskId);
            appendCompletedRecord(taskId, title, kind, QString(), QString(), false, err, QString(), QString());
            if (cb) cb(false, err);
            emit downloadFailed(taskId, err);
            return;
        }

        if (!t->extractToDir.isEmpty()) {
            extractArchiveAsync(taskId);
        } else {
            t->progress = 100.0;
            emit downloadProgress(taskId, 100.0);
            const QString dest = t->destinationFile;
            const QString title = t->title;
            const QString kind = t->kind;
            auto cb = t->callback;
            cleanupTask(taskId);
            appendCompletedRecord(taskId, title, kind, QString(), QString(), true, QStringLiteral("Downloaded"), QString(), dest);
            if (cb) cb(true, dest);
            emit downloadFinished(taskId, dest);
        }
    });
}

void DownloadManager::extractArchiveAsync(const QString& taskId) {
    if (!m_tasks.contains(taskId)) return;
    DownloadTask* task = m_tasks.value(taskId);
    task->isExtracting = true;
    task->speedBps = 0.0;
    task->speedText.clear();
    task->progress = 92.0;
    task->stageText = QStringLiteral("Extracting…");
    task->eta = QStringLiteral("Extracting…");

    const int row = m_taskList.indexOf(task);
    if (row >= 0) {
        emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                         {ProgressRole, EtaRole, StageTextRole, SpeedTextRole, StatusRole, IsExtractingRole});
    }
    emit downloadProgressDetailed(taskId, 92.0, task->bytesDownloaded, task->totalBytes, 0, task->eta);
    updateAggregateSpeed();

    QDir().mkpath(task->extractToDir);
    auto* proc = new QProcess(this);
    task->process = proc;

    QString program = QStringLiteral("tar");
    QStringList args = {QStringLiteral("-xf"), task->destinationFile, QStringLiteral("-C"), task->extractToDir, QStringLiteral("--no-same-owner"), QStringLiteral("--delay-directory-restore")};

    if (task->destinationFile.endsWith(QStringLiteral(".zip"), Qt::CaseInsensitive)) {
        program = QStringLiteral("7z");
        args = {QStringLiteral("x"), task->destinationFile, QStringLiteral("-o") + task->extractToDir, QStringLiteral("-y")};
    }

    connect(proc, &QProcess::finished, this, [this, taskId, proc](int exitCode, QProcess::ExitStatus status) {
        const QString errOut = QString::fromUtf8(proc->readAllStandardError());
        proc->deleteLater();

        if (!m_tasks.contains(taskId)) return;
        DownloadTask* t = m_tasks.value(taskId);
        t->process = nullptr;

        const QString extractDir = t->extractToDir;
        const QString archiveFile = t->destinationFile;
        const QString title = t->title;
        const QString kind = t->kind;
        auto cb = t->callback;

        QFile::remove(archiveFile);
        cleanupTask(taskId);

        if (status == QProcess::NormalExit && exitCode == 0) {
            appendCompletedRecord(taskId, title, kind, QString(), QString(), true, QStringLiteral("Installed"), QString(), extractDir);
            if (cb) cb(true, extractDir);
            emit downloadFinished(taskId, extractDir);
        } else {
            const QString errMsg = errOut.isEmpty() ? QStringLiteral("Archive extraction failed (exit code %1)").arg(exitCode) : errOut;
            appendCompletedRecord(taskId, title, kind, QString(), QString(), false, errMsg, QString(), QString());
            if (cb) cb(false, errMsg);
            emit downloadFailed(taskId, errMsg);
        }
    });

    proc->start(program, args);
}

void DownloadManager::togglePauseDownload(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.value(id);
    if (task->isExtracting) return;

    const int row = m_taskList.indexOf(task);

    if (task->isExternal) {
        if (task->isQueued) {
            // Starting a queued task explicitly via toggle
            prioritizeDownload(id);
            return;
        }
        if (!task->isPaused) {
            task->isPaused = true;
            task->speedBps = 0.0;
            task->speedText.clear();
            task->stageText = QStringLiteral("Paused");
            task->eta = QStringLiteral("Paused");
            if (row >= 0) {
                emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                                 {IsPausedRole, StatusRole, StageTextRole, SpeedTextRole, EtaRole});
            }
            if (task->adapter.pauseFn) task->adapter.pauseFn();
            emit downloadPaused(id);
            emit activeDownloadsChanged();
            updateAggregateSpeed();
            pumpGameQueue();
        } else {
            task->isPaused = false;
            task->stageText = QStringLiteral("Resuming…");
            task->eta = QStringLiteral("Resuming…");
            if (row >= 0) {
                emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                                 {IsPausedRole, StatusRole, StageTextRole, EtaRole});
            }
            if (task->adapter.resumeFn) task->adapter.resumeFn();
            emit downloadResumed(id);
            emit activeDownloadsChanged();
        }
        return;
    }

    if (!task->isPaused) {
        task->isPaused = true;
        task->speedBps = 0.0;
        task->speedText.clear();
        if (task->reply) {
            task->reply->disconnect(this);
            task->reply->abort();
            task->reply->deleteLater();
            task->reply = nullptr;
        }
        if (task->file) {
            task->file->flush();
            task->resumeOffset = task->file->size();
            task->file->close();
        }
        task->stageText = QStringLiteral("Paused");
        task->eta = QStringLiteral("Paused");
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                             {IsPausedRole, StatusRole, StageTextRole, SpeedTextRole, EtaRole});
        }
        emit downloadPaused(id);
        updateAggregateSpeed();
    } else {
        task->isPaused = false;
        task->stageText = QStringLiteral("Resuming…");
        task->eta = QStringLiteral("Resuming…");
        if (task->file) {
            if (!task->file->open(QIODevice::WriteOnly | QIODevice::Append)) {
                task->file->open(QIODevice::WriteOnly | QIODevice::Truncate);
                task->resumeOffset = 0;
            }
        }
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                             {IsPausedRole, StatusRole, StageTextRole, EtaRole});
        }
        startRequest(id);
        emit downloadResumed(id);
    }
}

void DownloadManager::cancelDownload(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.value(id);
    m_gameplayPausedIds.remove(id);

    if (task->isExternal) {
        auto cancelFn = task->adapter.cancelFn;
        if (m_db) m_db->removeQueuedDownload(id);
        if (cancelFn) {
            cancelFn(true);
            // If adapter didn't already call finishExternalTask, ensure cleaned up
            if (m_tasks.contains(id)) {
                cleanupTask(id);
                pumpGameQueue();
            }
        } else {
            cleanupTask(id);
            pumpGameQueue();
        }
        return;
    }

    const QString partFile = task->destinationFile + QStringLiteral(".part");
    const QString archiveFile = task->destinationFile;
    auto cb = task->callback;

    cleanupTask(id);

    QFile::remove(partFile);
    QFile::remove(archiveFile);

    if (cb) cb(false, QStringLiteral("Download cancelled"));
    emit downloadFailed(id, QStringLiteral("Cancelled"));
}

void DownloadManager::cleanupTask(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.value(id);

    const int row = m_taskList.indexOf(task);
    if (row >= 0) {
        beginRemoveRows(QModelIndex(), row, row);
        m_taskList.removeAt(row);
        m_tasks.remove(id);
        endRemoveRows();
    } else {
        m_tasks.remove(id);
    }

    if (task->reply) {
        task->reply->disconnect(this);
        task->reply->abort();
        task->reply->deleteLater();
        task->reply = nullptr;
    }
    if (task->process) {
        task->process->disconnect(this);
        task->process->kill();
        task->process->deleteLater();
        task->process = nullptr;
    }
    if (task->file) {
        if (task->file->isOpen()) task->file->close();
        delete task->file;
        task->file = nullptr;
    }
    delete task;

    if (m_taskList.isEmpty() && m_throttleTimer.isActive()) {
        m_throttleTimer.stop();
    }
    updateAggregateSpeed();
    emit activeDownloadsChanged();
}

} // namespace Tsuki
