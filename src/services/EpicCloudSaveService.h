#pragma once

#include "../core/AppSettings.h"
#include "../core/DatabaseManager.h"
#include "../core/Models.h"
#include "EpicManifestParser.h"
#include "PrefixManager.h"

#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

namespace Tsuki {

class EpicService;

class EpicCloudSaveService : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isSyncing READ isSyncing NOTIFY syncingChanged)

public:
    enum class SyncDecision {
        UpToDate,
        DownloadRecommended,
        UploadRecommended,
        Conflict,
        NotConfigured
    };
    Q_ENUM(SyncDecision)

    struct LocalFileEntry {
        QString relativePath;
        QString absolutePath;
        QByteArray sha1;
        qint64 size = 0;
        qint64 mtimeEpoch = 0;
    };

    struct RemoteManifestEntry {
        QString manifestPath;
        QString readLink;
        qint64 lastModifiedEpoch = 0;
        QString hash;
    };

    explicit EpicCloudSaveService(DatabaseManager* db,
                                  AppSettings* settings,
                                  PrefixManager* prefixMgr,
                                  EpicService* epicService,
                                  QObject* parent = nullptr);

    bool isSyncing() const { return !m_syncingGames.isEmpty(); }
    Q_INVOKABLE bool isGameSyncing(const QString& gameId) const { return m_syncingGames.contains(gameId); }

    /// Resolve Epic/Windows save path placeholders inside a Wine/Proton prefix.
    /// Supports {AppData}, {LocalAppData}, {UserDir}, {InstallDir}, {EpicID},
    /// %USERPROFILE%, %APPDATA%, %LOCALAPPDATA%, %DOCUMENTS%, {MyDocuments}.
    static QString resolveSaveFolderPath(const QString& rawTemplate,
                                         const QString& prefixPath,
                                         const QString& installDir,
                                         const QString& epicAccountId);

    /// Resolve the effective local save directory for a registered game.
    Q_INVOKABLE QString resolveLocalSaveDirForGame(const QString& gameId) const;

    /// Scan local files respecting optional include/exclude globs.
    static QList<LocalFileEntry> scanLocalSaveFiles(const QString& saveDir,
                                                    const QStringList& includePatterns = {},
                                                    const QStringList& excludePatterns = {});

    /// Classify sync state from local snapshot vs remote manifest timestamp/hash + prior sync state.
    static SyncDecision evaluateSyncState(const QList<LocalFileEntry>& localFiles,
                                          qint64 localLatestMtime,
                                          bool hasRemoteManifest,
                                          qint64 remoteMtimeEpoch,
                                          const QString& remoteManifestHash,
                                          const std::optional<DatabaseManager::CloudSaveState>& prevState);

    /// Create a safety tar.gz snapshot of local saves before any destructive sync (prunes to keepMax).
    static QString createLocalSafetySnapshot(const QString& gameId,
                                             const QString& localSaveDir,
                                             const QString& backupsBaseDir = QString(),
                                             int keepMax = 5);

    Q_INVOKABLE QVariantList listLocalSnapshots(const QString& gameId) const;
    Q_INVOKABLE bool restoreLocalSnapshot(const QString& gameId, const QString& snapshotPath);
    Q_INVOKABLE QVariantMap getCloudSaveStatus(const QString& gameId) const;
    Q_INVOKABLE void openSaveFolder(const QString& gameId) const;

    /// Sync cloud saves. mode = "auto", "download", or "upload".
    /// If mode == "auto" and a Conflict is detected, emits syncConflictDetected and invokes callback(false, "conflict", details).
    Q_INVOKABLE void syncGameSaves(const QString& gameId,
                                   const QString& mode = QStringLiteral("auto")) {
        syncGameSaves(gameId, mode, nullptr);
    }
    void syncGameSaves(const QString& gameId,
                       const QString& mode,
                       std::function<void(bool ok, const QString& outcome, const QVariantMap& details)> callback);

signals:
    void syncingChanged();
    void cloudSaveStatusChanged(const QString& gameId);
    void syncConflictDetected(const QString& gameId, const QVariantMap& conflictDetails);
    void operationStatus(const QString& message, bool isError);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    PrefixManager* m_prefixMgr;
    EpicService* m_epicSvc;
    QNetworkAccessManager m_nam;
    QSet<QString> m_syncingGames;

    void fetchRemoteSaveIndex(const GameRecord& game,
                              const QString& accountId,
                              const QString& accessToken,
                              std::function<void(bool ok,
                                                 const QList<RemoteManifestEntry>& manifests,
                                                 const QHash<QString, QString>& chunkReadLinks,
                                                 const QString& error)> callback);

    void performDownloadSync(const GameRecord& game,
                             const QString& localDir,
                             const RemoteManifestEntry& latestManifest,
                             const QHash<QString, QString>& chunkReadLinks,
                             std::function<void(bool, const QString&, const QVariantMap&)> callback);

    void performUploadSync(const GameRecord& game,
                           const QString& accountId,
                           const QString& accessToken,
                           const QString& localDir,
                           const QList<LocalFileEntry>& localFiles,
                           std::function<void(bool, const QString&, const QVariantMap&)> callback);

    void saveStateSnapshot(const QString& gameId,
                           const QList<LocalFileEntry>& files,
                           const QString& manifestHash);

    void finishSync(const QString& gameId,
                    bool ok,
                    const QString& outcome,
                    const QVariantMap& details,
                    const QString& statusMsg,
                    bool isError,
                    std::function<void(bool, const QString&, const QVariantMap&)> callback);
};

} // namespace Tsuki
