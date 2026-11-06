#pragma once

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFile>
#include <QElapsedTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QMap>
#include <functional>

namespace Tsuki {

class DownloadManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(int activeDownloadCount READ activeDownloadCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QVariantList activeDownloads READ activeDownloads NOTIFY activeDownloadsChanged)

public:
    explicit DownloadManager(QObject* parent = nullptr);
    ~DownloadManager() override;

    int activeDownloadCount() const { return m_tasks.size(); }
    QVariantList activeDownloads() const;

    QString enqueueDownload(const QString& id,
                            const QString& title,
                            const QUrl& url,
                            const QString& destinationFile,
                            const QString& extractToDir = QString(),
                            std::function<void(bool, const QString&)> onComplete = nullptr);

    Q_INVOKABLE void togglePauseDownload(const QString& id);
    Q_INVOKABLE void cancelDownload(const QString& id);
    Q_INVOKABLE bool isMediaDownloading(const QString& id) const;

    static QString formatBytes(qint64 bytes);

signals:
    void activeDownloadsChanged();
    void downloadProgress(const QString& id, double progress);
    void downloadProgressDetailed(const QString& id, double progress, qint64 bytesDownloaded, qint64 totalBytes, double speedBps, const QString& eta);
    void downloadPaused(const QString& id);
    void downloadResumed(const QString& id);
    void downloadFinished(const QString& id, const QString& targetPath);
    void downloadFailed(const QString& id, const QString& error);

private:
    struct DownloadTask {
        QString id;
        QString title;
        QUrl url;
        QString destinationFile;
        QString extractToDir;
        QFile* file = nullptr;
        QNetworkReply* reply = nullptr;
        qint64 resumeOffset = 0;
        qint64 bytesDownloaded = 0;
        qint64 totalBytes = 0;
        double progress = 0.0;
        QString eta;
        bool isPaused = false;
        bool isExtracting = false;
        QElapsedTimer timer;
        std::function<void(bool, const QString&)> callback;
    };

    QNetworkAccessManager m_nam;
    QMap<QString, DownloadTask*> m_tasks;

    void startRequest(DownloadTask* task);
    void extractArchiveAsync(DownloadTask* task);
    void cleanupTask(const QString& id);
};

} // namespace Tsuki

