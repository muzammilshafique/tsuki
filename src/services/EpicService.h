#pragma once

#include "../core/AppSettings.h"
#include "../core/DatabaseManager.h"
#include "../core/Models.h"
#include "EpicManifestParser.h"
#include "PrefixManager.h"
#include "RunnerManager.h"
#include "SteamGridDbService.h"

#include <QAbstractListModel>
#include <QElapsedTimer>
#include <QHash>
#include <QMutex>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QPair>
#include <QQueue>
#include <QSet>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>
#include <functional>
#include <memory>

namespace Tsuki {

class GameManager;
class EpicService;
class DownloadManager;
class UmuIdResolver;

class EpicLibraryModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(QString searchQuery READ searchQuery WRITE setSearchQuery NOTIFY searchQueryChanged)
    Q_PROPERTY(int sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(int hiddenCount READ hiddenCount NOTIFY countChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum EpicRoles {
        AppNameRole = Qt::UserRole + 1,
        NamespaceRole,
        CatalogItemIdRole,
        TitleRole,
        DeveloperRole,
        DescriptionRole,
        CoverPathRole,
        BannerPathRole,
        LogoPathRole,
        DownloadSizeRole,
        InstallSizeRole,
        DownloadSizeFormattedRole,
        InstallSizeFormattedRole,
        BuildVersionRole,
        IsInstalledRole,
        InstalledGameIdRole,
        HasUpdateRole,
        IsHiddenRole,
        IsDownloadingRole,
        IsPausedRole,
        IsQueuedRole,
        DownloadProgressRole,
        DownloadSpeedTextRole,
        DownloadEtaRole,
        DownloadStageRole
    };
    Q_ENUM(EpicRoles)

    explicit EpicLibraryModel(EpicService* service, DatabaseManager* db, QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString searchQuery() const { return m_searchQuery; }
    void setSearchQuery(const QString& query);

    int sortMode() const { return m_sortMode; }
    void setSortMode(int mode);

    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool show);
    int hiddenCount() const { return m_hiddenCount; }

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE void reload();
    void notifyAppChanged(const QString& appName);

signals:
    void searchQueryChanged();
    void sortModeChanged();
    void showHiddenChanged();
    void countChanged();

private:
    EpicService* m_service;
    DatabaseManager* m_db;
    QString m_searchQuery;
    int m_sortMode = 0; // 0: A->Z, 1: Installed First, 2: Recently Synced
    bool m_showHidden = false;
    int m_hiddenCount = 0;
    QList<EpicLibraryItem> m_visibleItems;
    QHash<QString, QString> m_installedGameIdsByApp;
};

class EpicService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isSignedIn READ isSignedIn NOTIFY authStateChanged)
    Q_PROPERTY(bool isSigningIn READ isSigningIn NOTIFY authStateChanged)
    Q_PROPERTY(bool isSyncing READ isSyncing NOTIFY syncingChanged)
    Q_PROPERTY(QString accountDisplayName READ accountDisplayName NOTIFY authStateChanged)
    Q_PROPERTY(QString accountId READ accountId NOTIFY authStateChanged)
    Q_PROPERTY(QString authError READ authError NOTIFY authStateChanged)
    Q_PROPERTY(QString loginUrl READ loginUrl CONSTANT)
    Q_PROPERTY(int activeDownloadCount READ activeDownloadCount NOTIFY activeDownloadsChanged)
    Q_PROPERTY(int updateCount READ updateCount NOTIFY updatesChanged)
    Q_PROPERTY(Tsuki::EpicLibraryModel* libraryModel READ libraryModel CONSTANT)
    Q_PROPERTY(bool eosOverlayInstalled READ isEosOverlayInstalled NOTIFY eosOverlayChanged)
    Q_PROPERTY(QString eosOverlayVersion READ eosOverlayVersion NOTIFY eosOverlayChanged)
    Q_PROPERTY(QString eosOverlayPath READ eosOverlayPath NOTIFY eosOverlayChanged)
    Q_PROPERTY(bool isInstallingEosOverlay READ isInstallingEosOverlay NOTIFY eosOverlayChanged)
    Q_PROPERTY(double eosOverlayProgress READ eosOverlayProgress NOTIFY eosOverlayChanged)

public:
    explicit EpicService(DatabaseManager* db,
                         AppSettings* settings,
                         RunnerManager* runnerMgr,
                         PrefixManager* prefixMgr,
                         SteamGridDbService* sgdb,
                         QObject* parent = nullptr);
    ~EpicService() override;

    void setGameManager(GameManager* gm);
    void setDownloadManager(DownloadManager* dlMgr);
    void setUmuIdResolver(UmuIdResolver* resolver);

    bool isSignedIn() const { return m_isSignedIn; }
    bool isSigningIn() const { return m_isSigningIn; }
    bool isSyncing() const { return m_isSyncing; }
    QString accountDisplayName() const { return m_displayName; }
    QString accountId() const { return m_accountId; }
    QString accessToken() const { return m_accessToken; }
    QString authError() const { return m_authError; }
    QString loginUrl() const;
    int activeDownloadCount() const { return m_downloads.size(); }
    int updateCount() const { return m_appsWithUpdates.size(); }
    EpicLibraryModel* libraryModel() const { return m_model; }

    // Auth helpers
    static QString extractAuthCode(const QString& rawInput);
    Q_INVOKABLE void openLoginInBrowser();
    Q_INVOKABLE void signInWithAuthCode(const QString& rawInput);
    Q_INVOKABLE void signOut();

    void ensureValidToken(std::function<void(bool ok)> callback);
    void requestExchangeCode(std::function<void(bool ok, const QString& code)> callback);

    // Library, updates, DLCs & metadata
    Q_INVOKABLE void syncLibrary();
    Q_INVOKABLE void checkForUpdates();
    Q_INVOKABLE void toggleHideEpicGame(const QString& appName);
    Q_INVOKABLE void restorePendingDownloads();
    static bool isBlockedNonGameEpicApp(const QString& title,
                                        const QString& appName = QString(),
                                        const QString& namespaceId = QString());
    Q_INVOKABLE bool hasUpdate(const QString& appName) const { return m_appsWithUpdates.contains(appName); }
    Q_INVOKABLE QString latestBuildVersion(const QString& appName) const { return m_latestBuildVersions.value(appName); }
    Q_INVOKABLE void fetchInstallInfo(const QString& appName);
    Q_INVOKABLE QVariantMap getEpicGameMap(const QString& appName) const;
    Q_INVOKABLE QVariantMap getDownloadState(const QString& appName) const;
    Q_INVOKABLE QVariantList getDlcsForGame(const QString& appName) const;
    Q_INVOKABLE QVariantList getInstallTagsForGame(const QString& appName) const;

    // Downloads, updates, DLCs, prerequisites, import & verification
    Q_INVOKABLE void startDownload(const QString& appName,
                                   const QString& installBaseDir,
                                   const QString& runnerId = QString(),
                                   const QString& prefixMode = QStringLiteral("default-prefix"),
                                   const QString& customPrefixName = QString(),
                                   const QString& customPrefixLocation = QString(),
                                   const QString& prefixArch = QStringLiteral("win64"),
                                   const QStringList& selectedInstallTags = QStringList(),
                                   const QStringList& selectedDlcAppNames = QStringList());
    Q_INVOKABLE void updateGame(const QString& gameId);
    Q_INVOKABLE void installDlc(const QString& parentGameId, const QString& dlcAppName);
    Q_INVOKABLE void runGamePrerequisites(const QString& gameId, bool force = false);
    Q_INVOKABLE QVariantMap inspectImportSource(const QString& appName,
                                                const QString& sourceDir,
                                                const QString& targetBaseDir = QString()) const;
    Q_INVOKABLE void importGame(const QString& appName,
                                const QString& sourceDir,
                                const QString& transferMode = QStringLiteral("copy"),
                                const QString& targetBaseDir = QString(),
                                const QString& runnerId = QString(),
                                const QString& prefixMode = QStringLiteral("default-prefix"),
                                const QString& customPrefixName = QString(),
                                const QString& customPrefixLocation = QString(),
                                const QString& prefixArch = QStringLiteral("win64"),
                                bool verifyAfterImport = false,
                                const QString& customExecutable = QString());
    Q_INVOKABLE void pauseDownload(const QString& appName);
    Q_INVOKABLE void resumeDownload(const QString& appName);
    Q_INVOKABLE void cancelDownload(const QString& appName, bool deletePartialFiles = true);
    Q_INVOKABLE void verifyGame(const QString& gameId);

    // Epic Online Services (EOS) Overlay management
    bool isEosOverlayInstalled() const;
    QString eosOverlayVersion() const;
    QString eosOverlayPath() const;
    bool isInstallingEosOverlay() const;
    double eosOverlayProgress() const;
    Q_INVOKABLE void installEosOverlay();
    Q_INVOKABLE void removeEosOverlay();

    // Filesystem helpers for QML
    Q_INVOKABLE qint64 getFreeDiskSpace(const QString& path) const;
    Q_INVOKABLE QString getFreeDiskSpaceFormatted(const QString& path) const;
    Q_INVOKABLE QString suggestInstallDirectory(const QString& baseDir, const QString& gameTitle) const;
    Q_INVOKABLE QString formatBytes(qint64 bytes) const;

    // Path helpers
    static QString sanitizeFolderName(const QString& title);
    static QString resolveExistingRelativePath(const QString& baseDir, const QString& relativePath);

signals:
    void authStateChanged();
    void syncingChanged();
    void libraryUpdated();
    void activeDownloadsChanged();
    void downloadStateChanged(const QString& appName);
    void downloadFinished(const QString& appName, const QString& gameId);
    void downloadFailed(const QString& appName, const QString& error);
    void installInfoReady(const QString& appName, qint64 downloadSize, qint64 installSize);
    void installDetailsReady(const QString& appName, const QVariantList& installTags, const QVariantList& dlcs);
    void updatesChanged();
    void prerequisitesFinished(const QString& gameId, bool success, const QString& message);
    void eosOverlayChanged();
    void operationStatus(const QString& message, bool isError);

private:
    struct ChunkTargetSlice {
        int fileIndex = -1;
        qint64 fileOffset = 0;
        quint32 chunkOffset = 0;
        quint32 size = 0;
    };

    struct ChunkJob {
        QString guid;
        EpicChunkInfo info;
        QList<ChunkTargetSlice> targets;
        int retries = 0;
        int mirrorIndex = 0;
    };

    struct MirrorEndpoint {
        QString baseUrl;
        QList<QPair<QString, QString>> queryParams;
    };

    struct DownloadSession {
        QString queueId;
        QString appName;
        QString namespaceId;
        QString catalogItemId;
        QString title;
        QString coverPath;
        QString installDir;
        QString runnerId;
        QString prefixMode;
        QString customPrefixName;
        QString customPrefixLocation;
        QString prefixArch;
        bool verifyOnly = false;
        bool isUpdate = false;
        bool isDlc = false;
        bool isImporting = false;
        bool isEosOverlay = false;
        bool verifyAfterImport = false;
        bool importedInPlace = false;
        QString transferMode;
        QString importSourceDir;
        QString explicitExecutable;
        QString existingGameId;
        QString parentAppName;
        QStringList selectedInstallTags;
        QStringList selectedDlcs;
        QStringList filesToRemoveOnFinalize;
        QList<EpicFileManifest> activeFiles;

        EpicManifest manifest;
        EpicManifest previousManifest;
        bool hasPreviousManifest = false;
        QList<MirrorEndpoint> mirrors;
        QHash<QString, ChunkJob> chunkJobs;
        QQueue<QString> pendingChunks;
        QSet<QString> inFlightChunks;
        QSet<QString> completedChunks;
        QList<QNetworkReply*> activeReplies;
        QHash<int, std::shared_ptr<QMutex>> fileMutexes;

        int activeWorkers = 0;
        int chunksSinceSave = 0;
        qint64 totalDownloadBytes = 0;
        qint64 downloadedBytes = 0;
        qint64 totalInstallBytes = 0;
        qint64 sessionBytes = 0;
        double speedBps = 0.0;
        double progress = 0.0;
        QString speedText;
        QString etaText;
        QString stageText;
        bool isQueued = false;
        bool isPaused = false;
        bool isCancelled = false;
        bool isVerifying = false;
        bool deleteOnCancel = true;
        QElapsedTimer speedTimer;
        QElapsedTimer uiEmitTimer;
    };

    struct ArtworkTask {
        QString appName;
        QString type; // "cover", "banner", "logo"
        QString url;
        QString destPath;
    };

    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    PrefixManager* m_prefixMgr;
    SteamGridDbService* m_sgdb;
    GameManager* m_gameMgr = nullptr;
    DownloadManager* m_dlMgr = nullptr;
    UmuIdResolver* m_umuResolver = nullptr;

    QNetworkAccessManager m_nam;
    bool m_isSignedIn = false;
    bool m_isSigningIn = false;
    bool m_isSyncing = false;
    bool m_isRefreshingToken = false;
    QString m_accessToken;
    QString m_refreshToken;
    QString m_accountId;
    QString m_displayName;
    QString m_authError;
    qint64 m_expiresAtEpoch = 0;
    qint64 m_refreshExpiresAtEpoch = 0;
    QList<std::function<void(bool)>> m_pendingRefreshCallbacks;

    // Sync state
    QList<EpicLibraryItem> m_pendingEntitlements;
    QHash<QString, QList<EpicLibraryItem>> m_pendingBatchesByNs;
    QList<QPair<QString, QList<EpicLibraryItem>>> m_catalogQueue;
    QList<EpicLibraryItem> m_syncedCatalogItems;
    QList<EpicDlcItem> m_syncedDlcs;

    // Update tracking
    QSet<QString> m_appsWithUpdates;
    QHash<QString, QString> m_latestBuildVersions;

    // Artwork queue
    QQueue<ArtworkTask> m_artworkQueue;
    QSet<QString> m_queuedArtKeys;
    int m_activeArtworkDownloads = 0;

    // Active chunk downloads keyed by appName
    QHash<QString, std::shared_ptr<DownloadSession>> m_downloads;
    EpicLibraryModel* m_model = nullptr;

    void notifyDownloadManagerProgress(const std::shared_ptr<DownloadSession>& session);
    void beginSessionExecution(const std::shared_ptr<DownloadSession>& session);
    void persistDownloadQueueItem(const std::shared_ptr<DownloadSession>& session);
    void removePersistedDownloadQueueItem(const QString& queueId);

    QString authFilePath() const;
    QString manifestCachePath(const QString& appName) const;
    void loadAuthSession();
    void saveAuthSession();
    void clearAuthSession();
    void applyOAuthJson(const QJsonObject& obj);

    void fetchEntitlementPage(const QString& cursor);
    void enqueueCatalogBatches();
    void processNextCatalogBatch();
    void finishLibrarySync();

    void queueArtworkForItems(const QList<EpicLibraryItem>& items);
    void pumpArtworkQueue();

    void fetchAssetManifestWithToken(const EpicLibraryItem& item,
                                     const QString& bearerToken,
                                     std::function<void(bool ok,
                                                        const EpicManifest& manifest,
                                                        const QList<MirrorEndpoint>& mirrors,
                                                        const QByteArray& rawManifest,
                                                        const QString& error)> callback);
    void fetchAssetManifest(const EpicLibraryItem& item,
                            std::function<void(bool ok,
                                               const EpicManifest& manifest,
                                               const QList<MirrorEndpoint>& mirrors,
                                               const QByteArray& rawManifest,
                                               const QString& error)> callback);

    void prepareAndStartSession(const std::shared_ptr<DownloadSession>& session);
    void pumpDownloadChunks(const std::shared_ptr<DownloadSession>& session);
    void startChunkRequest(const std::shared_ptr<DownloadSession>& session, const QString& chunkGuid);
    void onChunkWriteFinished(const std::shared_ptr<DownloadSession>& session,
                              const QString& chunkGuid,
                              bool ok,
                              const QString& error);
    void finalizeDownloadSession(const std::shared_ptr<DownloadSession>& session);
    void completeImportSession(const std::shared_ptr<DownloadSession>& session);
    void failDownloadSession(const std::shared_ptr<DownloadSession>& session, const QString& error);
    void saveResumeState(const std::shared_ptr<DownloadSession>& session);
    QSet<QString> loadResumeState(const QString& installDir, const QString& buildVersion) const;
    void cleanupSessionFiles(const std::shared_ptr<DownloadSession>& session);
};

} // namespace Tsuki

