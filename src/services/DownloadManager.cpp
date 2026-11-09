#include "DownloadManager.h"
#include <QNetworkRequest>
#include <QProcess>
#include <QDir>
#include <QFileInfo>
#include <QUuid>

namespace Tsuki {

DownloadManager::DownloadManager(QObject* parent)
    : QAbstractListModel(parent)
{
}

DownloadManager::~DownloadManager() {
    const QStringList keys = m_tasks.keys();
    for (const QString& k : keys) {
        cancelDownload(k);
    }
}

int DownloadManager::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_taskList.size();
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
        return 1;
    case ProgressRole:
        return t->progress;
    case DownloadedSizeStrRole:
        return formatBytes(t->bytesDownloaded);
    case TotalSizeStrRole:
        return t->totalBytes > 0 ? formatBytes(t->totalBytes) : QString();
    case EtaRole:
        return t->isExtracting ? QStringLiteral("Extracting…") : t->eta;
    case IsPausedRole:
        return t->isPaused;
    case IsExtractingRole:
        return t->isExtracting;
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
    roles[ProgressRole] = "progress";
    roles[DownloadedSizeStrRole] = "downloadedSizeStr";
    roles[TotalSizeStrRole] = "totalSizeStr";
    roles[EtaRole] = "eta";
    roles[IsPausedRole] = "isPaused";
    roles[IsExtractingRole] = "isExtracting";
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

QVariantList DownloadManager::activeDownloads() const {
    QVariantList list;
    for (const DownloadTask* t : m_taskList) {
        QVariantMap m;
        m["id"] = t->id;
        m["title"] = t->title;
        m["displayName"] = t->title;
        m["type"] = 1;
        m["progress"] = t->progress;
        m["downloadedSizeStr"] = formatBytes(t->bytesDownloaded);
        m["totalSizeStr"] = t->totalBytes > 0 ? formatBytes(t->totalBytes) : QString();
        m["eta"] = t->isExtracting ? QStringLiteral("Extracting…") : t->eta;
        m["isPaused"] = t->isPaused;
        m["isExtracting"] = t->isExtracting;
        list.append(m);
    }
    return list;
}

bool DownloadManager::isMediaDownloading(const QString& id) const {
    return m_tasks.contains(id);
}

QString DownloadManager::enqueueDownload(const QString& id,
                                         const QString& title,
                                         const QUrl& url,
                                         const QString& destinationFile,
                                         const QString& extractToDir,
                                         std::function<void(bool, const QString&)> onComplete)
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
    task->url = url;
    task->destinationFile = destinationFile;
    task->extractToDir = extractToDir;
    task->callback = std::move(onComplete);
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

    emit activeDownloadsChanged();
    startRequest(taskId);
    return taskId;
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

        const QByteArray chunk = reply->readAll();
        t->file->write(chunk);
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
        QString etaStr;
        if (speedBps > 100.0 && totalSize > totalDl) {
            const qint64 remSecs = static_cast<qint64>((totalSize - totalDl) / speedBps);
            if (remSecs < 60) etaStr = QStringLiteral("%1s left").arg(remSecs);
            else etaStr = QStringLiteral("%1m %2s left").arg(remSecs / 60).arg(remSecs % 60);
        } else {
            etaStr = QStringLiteral("%1/s").arg(formatBytes(static_cast<qint64>(speedBps)));
        }
        t->eta = etaStr;

        emit downloadProgress(taskId, t->progress);
        emit downloadProgressDetailed(taskId, t->progress, totalDl, totalSize, speedBps, etaStr);

        const int row = m_taskList.indexOf(t);
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0),
                             {ProgressRole, DownloadedSizeStrRole, TotalSizeStrRole, EtaRole});
        }
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
            reply->deleteLater();
            auto cb = t->callback;
            cleanupTask(taskId);
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

        if (!t->extractToDir.isEmpty()) {
            extractArchiveAsync(taskId);
        } else {
            t->progress = 100.0;
            emit downloadProgress(taskId, 100.0);
            const QString dest = t->destinationFile;
            auto cb = t->callback;
            cleanupTask(taskId);
            if (cb) cb(true, dest);
            emit downloadFinished(taskId, dest);
        }
    });
}

void DownloadManager::extractArchiveAsync(const QString& taskId) {
    if (!m_tasks.contains(taskId)) return;
    DownloadTask* task = m_tasks.value(taskId);
    task->isExtracting = true;
    task->progress = 92.0;
    task->eta = QStringLiteral("Extracting…");

    const int row = m_taskList.indexOf(task);
    if (row >= 0) {
        emit dataChanged(createIndex(row, 0), createIndex(row, 0), {ProgressRole, EtaRole, IsExtractingRole});
    }
    emit downloadProgressDetailed(taskId, 92.0, task->bytesDownloaded, task->totalBytes, 0, task->eta);

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
        auto cb = t->callback;

        QFile::remove(archiveFile);
        cleanupTask(taskId);

        if (status == QProcess::NormalExit && exitCode == 0) {
            if (cb) cb(true, extractDir);
            emit downloadFinished(taskId, extractDir);
        } else {
            const QString errMsg = errOut.isEmpty() ? QStringLiteral("Archive extraction failed (exit code %1)").arg(exitCode) : errOut;
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

    if (!task->isPaused) {
        task->isPaused = true;
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
        task->eta = QStringLiteral("Paused");
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0), {IsPausedRole, EtaRole});
        }
        emit downloadPaused(id);
    } else {
        task->isPaused = false;
        task->eta = QStringLiteral("Resuming…");
        if (task->file) {
            if (!task->file->open(QIODevice::WriteOnly | QIODevice::Append)) {
                task->file->open(QIODevice::WriteOnly | QIODevice::Truncate);
                task->resumeOffset = 0;
            }
        }
        if (row >= 0) {
            emit dataChanged(createIndex(row, 0), createIndex(row, 0), {IsPausedRole, EtaRole});
        }
        startRequest(id);
        emit downloadResumed(id);
    }
}

void DownloadManager::cancelDownload(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.value(id);
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

    emit activeDownloadsChanged();
}

} // namespace Tsuki
