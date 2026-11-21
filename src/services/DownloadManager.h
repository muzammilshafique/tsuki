#pragma once

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QFile>
#include <QList>
#include <QMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

namespace Tsuki {

class AppSettings;
class DatabaseManager;

class DownloadManager : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int activeDownloadCount READ activeDownloadCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(int queuedDownloadCount READ queuedDownloadCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(int totalPendingCount READ totalPendingCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QString aggregateSpeedText READ aggregateSpeedText NOTIFY aggregateSpeedChanged)
    Q_PROPERTY(bool pausedForGameplay READ isPausedForGameplay NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QVariantList activeDownloads READ activeDownloads NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QVariantList runnerDownloads READ runnerDownloads NOTIFY activeDownloadsChanged)
    Q_PROPERTY(int runnerDownloadCount READ runnerDownloadCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(QVariantList completedDownloads READ completedDownloads NOTIFY completedDownloadsChanged)

public:
    enum DownloadRoles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        DisplayNameRole,
        TypeRole,
        KindRole,
        AppNameRole,
        CoverPathRole,
        ProgressRole,
        DownloadedSizeStrRole,
        TotalSizeStrRole,
        SpeedTextRole,
        StageTextRole,
        EtaRole,
        StatusRole,
        IsPausedRole,
        IsQueuedRole,
        IsExtractingRole,
        IsExternalRole
    };
    Q_ENUM(DownloadRoles)

    struct ExternalAdapter {
        std::function<void()> startFn;
        std::function<void()> pauseFn;
        std::function<void()> resumeFn;
        std::function<void(bool deletePartial)> cancelFn;
    };

    explicit DownloadManager(QObject* parent = nullptr);
    ~DownloadManager() override;

    void setAppSettings(AppSettings* settings);
    void setDatabaseManager(DatabaseManager* db);

    // QAbstractListModel overrides
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int activeDownloadCount() const;
    int queuedDownloadCount() const;
    int totalPendingCount() const { return m_taskList.size(); }
    QString aggregateSpeedText() const { return m_aggregateSpeedText; }
    bool isPausedForGameplay() const { return m_pausedForGameplay; }
    QVariantList activeDownloads() const;
    QVariantList runnerDownloads() const;
    int runnerDownloadCount() const;
    QVariantList completedDownloads() const { return m_completedHistory; }

    // Direct HTTP / archive downloads (runners, runtimes, tools)
    QString enqueueDownload(const QString& id,
                            const QString& title,
                            const QUrl& url,
                            const QString& destinationFile,
                            const QString& extractToDir = QString(),
                            std::function<void(bool, const QString&)> onComplete = nullptr,
                            const QString& expectedSha512 = QString(),
                            const QString& kind = QStringLiteral("tool"));

    // External managed downloads (Epic installs/updates/verifies/imports/EOS overlay)
    bool registerExternalTask(const QString& id,
                              const QString& title,
                              const QString& kind,
                              const QString& appName,
                              const QString& coverPath,
                              bool isGameQueueItem,
                              ExternalAdapter adapter,
                              bool startImmediatelyIfSlotFree = true,
                              bool initialPaused = false);
    void updateExternalTask(const QString& id,
                            double progress,
                            qint64 downloadedBytes,
                            qint64 totalBytes,
                            double speedBps,
                            const QString& speedText,
                            const QString& eta,
                            const QString& stage,
                            bool isPaused,
                            bool isQueued = false);
    void finishExternalTask(const QString& id,
                            bool success,
                            const QString& summaryOrError,
                            const QString& targetGameId = QString(),
                            const QString& targetPath = QString());

    // Queue & global controls
    Q_INVOKABLE void togglePauseDownload(const QString& id);
    Q_INVOKABLE void cancelDownload(const QString& id);
    Q_INVOKABLE bool isMediaDownloading(const QString& id) const;
    Q_INVOKABLE void moveQueueItemUp(const QString& id);
    Q_INVOKABLE void moveQueueItemDown(const QString& id);
    Q_INVOKABLE void prioritizeDownload(const QString& id);
    Q_INVOKABLE void pauseAll();
    Q_INVOKABLE void resumeAll();
    Q_INVOKABLE void clearCompletedHistory();

    // Gameplay auto-pause hooks (connected to LaunchPipeline)
    Q_INVOKABLE void pauseForGameplay();
    Q_INVOKABLE void resumeAfterGameplay();

    // Shared bandwidth token bucket for both HTTP streams and Epic chunk workers
    int speedLimitKBps() const;
    int maxConcurrentChunkWorkers() const;
    int maxConcurrentGameDownloads() const;
    qint64 recommendedReadBufferSize(int activeStreams = 1) const;
    bool tryConsumeBandwidthBytes(qint64 bytes);
    qint64 msUntilBandwidthAvailable(qint64 bytes) const;

    static QString formatBytes(qint64 bytes);
    static bool verifyFileSha512(const QString& filePath, const QString& expectedHex);

signals:
    void activeDownloadsChanged();
    void completedDownloadsChanged();
    void aggregateSpeedChanged();
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
        QString kind = QStringLiteral("tool");
        QString appName;
        QString coverPath;
        QUrl url;
        QString destinationFile;
        QString extractToDir;
        QString expectedSha512;
        QFile* file = nullptr;
        QNetworkReply* reply = nullptr;
        QProcess* process = nullptr;
        qint64 resumeOffset = 0;
        qint64 bytesDownloaded = 0;
        qint64 totalBytes = 0;
        double progress = 0.0;
        double speedBps = 0.0;
        QString speedText;
        QString stageText;
        QString eta;
        bool isPaused = false;
        bool isQueued = false;
        bool isExtracting = false;
        bool isExternal = false;
        bool isGameQueueItem = false;
        QElapsedTimer timer;
        std::function<void(bool, const QString&)> callback;
        ExternalAdapter adapter;
    };

    AppSettings* m_settings = nullptr;
    DatabaseManager* m_db = nullptr;
    QNetworkAccessManager m_nam;
    QList<DownloadTask*> m_taskList;
    QMap<QString, DownloadTask*> m_tasks;
    QVariantList m_completedHistory;

    bool m_pausedForGameplay = false;
    QSet<QString> m_gameplayPausedIds;

    // Token bucket bandwidth limiter
    double m_bucketTokensBytes = 0.0;
    QElapsedTimer m_bucketTimer;
    QTimer m_throttleTimer;
    QString m_aggregateSpeedText;

    void startRequest(const QString& taskId);
    void extractArchiveAsync(const QString& taskId);
    void cleanupTask(const QString& id);
    void pumpGameQueue();
    void refillBandwidthBucket();
    void applyReadBufferLimits();
    void updateAggregateSpeed();
    void appendCompletedRecord(const QString& id,
                               const QString& title,
                               const QString& kind,
                               const QString& appName,
                               const QString& coverPath,
                               bool success,
                               const QString& message,
                               const QString& targetGameId,
                               const QString& targetPath);
    int activeGameQueueCount() const;
    int rowForId(const QString& id) const;
};

} // namespace Tsuki
