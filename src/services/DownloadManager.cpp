#include "DownloadManager.h"
#include <QNetworkRequest>
#include <QProcess>
#include <QDir>
#include <QFileInfo>
#include <QUuid>

namespace Tsuki {

DownloadManager::DownloadManager(QObject* parent)
    : QObject(parent)
{
}

DownloadManager::~DownloadManager() {
    const QList<QString> keys = m_tasks.keys();
    for (const QString& k : keys) {
        cancelDownload(k);
    }
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
    for (auto it = m_tasks.constBegin(); it != m_tasks.constEnd(); ++it) {
        const DownloadTask* t = it.value();
        QVariantMap m;
        m["id"] = t->id;
        m["title"] = t->title;
        m["displayName"] = t->title;
        m["type"] = 1; // Hide season/episode subtitle in DownloadsDropdown
        m["progress"] = t->progress;
        m["downloadedSizeStr"] = formatBytes(t->bytesDownloaded);
        m["totalSizeStr"] = t->totalBytes > 0 ? formatBytes(t->totalBytes) : QString();
        m["eta"] = t->isExtracting ? QStringLiteral("Extracting…") : t->eta;
        m["isPaused"] = t->isPaused;
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

    m_tasks.insert(taskId, task);
    emit activeDownloadsChanged();
    startRequest(task);
    return taskId;
}

void DownloadManager::startRequest(DownloadTask* task) {
    QNetworkRequest req(task->url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0 (Linux; Qt6)"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    if (task->resumeOffset > 0) {
        req.setRawHeader("Range", QByteArray("bytes=") + QByteArray::number(task->resumeOffset) + "-");
    }

    task->timer.start();
    task->reply = m_nam.get(req);

    connect(task->reply, &QNetworkReply::readyRead, this, [this, task]() {
        if (!task->file || !task->reply) return;
        const QByteArray chunk = task->reply->readAll();
        task->file->write(chunk);
    });

    connect(task->reply, &QNetworkReply::downloadProgress, this, [this, task](qint64 bytesReceived, qint64 bytesTotal) {
        if (task->isPaused) return;
        const qint64 totalDl = task->resumeOffset + bytesReceived;
        const qint64 totalSize = bytesTotal > 0 ? (task->resumeOffset + bytesTotal) : 0;
        task->bytesDownloaded = totalDl;
        task->totalBytes = totalSize;

        double pct = 0.0;
        if (totalSize > 0) {
            pct = (static_cast<double>(totalDl) / static_cast<double>(totalSize)) * (task->extractToDir.isEmpty() ? 100.0 : 90.0);
        }
        task->progress = pct;

        const qint64 elapsedMs = qMax<qint64>(1, task->timer.elapsed());
        const double speedBps = (static_cast<double>(bytesReceived) * 1000.0) / static_cast<double>(elapsedMs);
        QString etaStr;
        if (speedBps > 100.0 && totalSize > totalDl) {
            const qint64 remSecs = static_cast<qint64>((totalSize - totalDl) / speedBps);
            if (remSecs < 60) etaStr = QStringLiteral("%1s left").arg(remSecs);
            else etaStr = QStringLiteral("%1m %2s left").arg(remSecs / 60).arg(remSecs % 60);
        } else {
            etaStr = QStringLiteral("%1/s").arg(formatBytes(static_cast<qint64>(speedBps)));
        }
        task->eta = etaStr;

        emit downloadProgress(task->id, task->progress);
        emit downloadProgressDetailed(task->id, task->progress, totalDl, totalSize, speedBps, etaStr);
    });

    connect(task->reply, &QNetworkReply::finished, this, [this, task]() {
        if (!task->reply) return;
        QNetworkReply* reply = task->reply;
        task->reply = nullptr;

        if (task->isPaused) {
            reply->deleteLater();
            return;
        }

        if (reply->error() != QNetworkReply::NoError) {
            const QString err = reply->errorString();
            reply->deleteLater();
            const QString id = task->id;
            auto cb = task->callback;
            cleanupTask(id);
            if (cb) cb(false, err);
            emit downloadFailed(id, err);
            return;
        }

        if (task->file) {
            const QByteArray remaining = reply->readAll();
            if (!remaining.isEmpty()) task->file->write(remaining);
            task->file->flush();
            task->file->close();
        }
        reply->deleteLater();

        QFile::remove(task->destinationFile);
        QFile::rename(task->destinationFile + QStringLiteral(".part"), task->destinationFile);

        if (!task->extractToDir.isEmpty()) {
            extractArchiveAsync(task);
        } else {
            task->progress = 100.0;
            emit downloadProgress(task->id, 100.0);
            const QString id = task->id;
            const QString dest = task->destinationFile;
            auto cb = task->callback;
            cleanupTask(id);
            if (cb) cb(true, dest);
            emit downloadFinished(id, dest);
        }
    });
}

void DownloadManager::extractArchiveAsync(DownloadTask* task) {
    task->isExtracting = true;
    task->progress = 92.0;
    task->eta = QStringLiteral("Extracting…");
    emit activeDownloadsChanged();
    emit downloadProgressDetailed(task->id, 92.0, task->bytesDownloaded, task->totalBytes, 0, task->eta);

    QDir().mkpath(task->extractToDir);
    auto* proc = new QProcess(this);
    QString program = QStringLiteral("tar");
    QStringList args = {QStringLiteral("-xf"), task->destinationFile, QStringLiteral("-C"), task->extractToDir};

    if (task->destinationFile.endsWith(QStringLiteral(".zip"), Qt::CaseInsensitive)) {
        program = QStringLiteral("7z");
        args = {QStringLiteral("x"), task->destinationFile, QStringLiteral("-o") + task->extractToDir, QStringLiteral("-y")};
    }

    connect(proc, &QProcess::finished, this, [this, task, proc](int exitCode, QProcess::ExitStatus status) {
        const QString errOut = QString::fromUtf8(proc->readAllStandardError());
        proc->deleteLater();

        const QString id = task->id;
        const QString extractDir = task->extractToDir;
        const QString archiveFile = task->destinationFile;
        auto cb = task->callback;

        QFile::remove(archiveFile);
        cleanupTask(id);

        if (status == QProcess::NormalExit && exitCode == 0) {
            if (cb) cb(true, extractDir);
            emit downloadFinished(id, extractDir);
        } else {
            const QString errMsg = errOut.isEmpty() ? QStringLiteral("Archive extraction failed (exit code %1)").arg(exitCode) : errOut;
            if (cb) cb(false, errMsg);
            emit downloadFailed(id, errMsg);
        }
    });

    proc->start(program, args);
}

void DownloadManager::togglePauseDownload(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.value(id);
    if (task->isExtracting) return;

    if (!task->isPaused) {
        task->isPaused = true;
        if (task->reply) {
            task->reply->abort();
        }
        if (task->file) {
            task->file->flush();
            task->resumeOffset = task->file->size();
        }
        task->eta = QStringLiteral("Paused");
        emit downloadPaused(id);
        emit activeDownloadsChanged();
    } else {
        task->isPaused = false;
        if (task->file && !task->file->isOpen()) {
            task->file->open(QIODevice::WriteOnly | QIODevice::Append);
        }
        startRequest(task);
        emit downloadResumed(id);
        emit activeDownloadsChanged();
    }
}

void DownloadManager::cancelDownload(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.value(id);
    task->isPaused = true;
    if (task->reply) {
        task->reply->abort();
        task->reply->deleteLater();
        task->reply = nullptr;
    }
    const QString partFile = task->destinationFile + QStringLiteral(".part");
    cleanupTask(id);
    QFile::remove(partFile);
}

void DownloadManager::cleanupTask(const QString& id) {
    if (!m_tasks.contains(id)) return;
    DownloadTask* task = m_tasks.take(id);
    if (task->file) {
        if (task->file->isOpen()) task->file->close();
        delete task->file;
    }
    delete task;
    emit activeDownloadsChanged();
}

} // namespace Tsuki

