#pragma once

#include <QAbstractListModel>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFile>
#include <QProcess>
#include <QElapsedTimer>
#include <QVariantList>
#include <QVariantMap>
#include <QMap>
#include <QList>
#include <functional>

namespace Tsuki {

class DownloadManager : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int activeDownloadCount READ activeDownloadCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QVariantList activeDownloads READ activeDownloads NOTIFY activeDownloadsChanged)

public:
    enum DownloadRoles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        DisplayNameRole,
        TypeRole,
        ProgressRole,
        DownloadedSizeStrRole,
        TotalSizeStrRole,
        EtaRole,
        IsPausedRole,
        IsExtractingRole
    };
    Q_ENUM(DownloadRoles)

    explicit DownloadManager(QObject* parent = nullptr);
    ~DownloadManager() override;

    // QAbstractListModel overrides
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

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
        QProcess* process = nullptr;
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
    QList<DownloadTask*> m_taskList;
    QMap<QString, DownloadTask*> m_tasks;

    void startRequest(const QString& taskId);
    void extractArchiveAsync(const QString& taskId);
    void cleanupTask(const QString& id);
};

} // namespace Tsuki
