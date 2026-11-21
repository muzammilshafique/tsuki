#pragma once

#include "Models.h"
#include <QObject>
#include <QSqlDatabase>
#include <QMutex>
#include <QList>
#include <optional>

namespace Tsuki {

class DatabaseManager : public QObject {
    Q_OBJECT
public:
    explicit DatabaseManager(const QString& dbFilePath = QString(), QObject* parent = nullptr);
    ~DatabaseManager() override;

    bool initialize();
    bool isOpen() const;

    // Games CRUD
    bool saveGame(const GameRecord& game);
    bool removeGame(const QString& gameId);
    std::optional<GameRecord> getGame(const QString& gameId) const;
    std::optional<GameRecord> getGameByEpicAppName(const QString& appName) const;
    QList<GameRecord> getAllGames() const;
    bool updatePlaytime(const QString& gameId, qint64 additionalSeconds, qint64 lastPlayedEpoch);

    // Epic Games Library Cache CRUD
    bool saveEpicLibraryItem(const EpicLibraryItem& item);
    bool saveEpicLibraryItems(const QList<EpicLibraryItem>& items);
    std::optional<EpicLibraryItem> getEpicLibraryItem(const QString& appName) const;
    QList<EpicLibraryItem> getAllEpicLibraryItems() const;
    bool updateEpicLibraryArtwork(const QString& appName,
                                  const QString& coverPath,
                                  const QString& bannerPath,
                                  const QString& logoPath);
    bool clearEpicLibraryArtworkFields(const QString& appName,
                                       bool clearCover,
                                       bool clearBanner,
                                       bool clearLogo);
    bool clearEpicLibraryArtworkPaths();
    bool updateEpicLibrarySizes(const QString& appName, qint64 downloadSize, qint64 installSize, const QString& buildVersion);
    bool setEpicLibraryItemHidden(const QString& appName, bool hidden);
    bool clearEpicLibrary();

    // Epic DLCs CRUD
    bool saveEpicDlcs(const QList<EpicDlcItem>& dlcs);
    QList<EpicDlcItem> getEpicDlcsForGame(const QString& parentAppName) const;
    bool setEpicDlcInstalled(const QString& dlcAppName, bool installed);
    bool clearEpicDlcs();

    // Collections CRUD
    QStringList getAllCollections() const;
    bool createCollection(const QString& name);
    bool renameCollection(const QString& oldName, const QString& newName);
    bool deleteCollection(const QString& name);

    // UMU Game ID Cache CRUD
    QString getCachedUmuId(const QString& store, const QString& codename) const;
    bool saveCachedUmuId(const QString& store, const QString& codename, const QString& umuId, const QString& title = QString());

    // Cloud Save Sync State CRUD
    struct CloudSaveState {
        QString gameId;
        qint64 lastSyncEpoch = 0;
        QString lastManifestHash;
        QVariantMap trackedFiles; // relativePath -> {hash, mtime, size}
    };
    std::optional<CloudSaveState> getCloudSaveState(const QString& gameId) const;
    bool saveCloudSaveState(const CloudSaveState& state);
    bool clearCloudSaveState(const QString& gameId);

    // Persistent Download Queue CRUD
    bool saveQueuedDownload(const QueuedDownloadRecord& rec);
    bool removeQueuedDownload(const QString& id);
    QList<QueuedDownloadRecord> getAllQueuedDownloads() const;
    bool clearQueuedDownloads();

    // Prefixes CRUD
    bool savePrefix(const PrefixRecord& prefix);
    bool removePrefix(const QString& prefixId);
    std::optional<PrefixRecord> getPrefix(const QString& prefixId) const;
    std::optional<PrefixRecord> getPrefixByName(const QString& name) const;
    QList<PrefixRecord> getAllPrefixes() const;

    // Runners CRUD
    bool saveRunner(const RunnerRecord& runner);
    bool removeRunner(const QString& runnerId);
    std::optional<RunnerRecord> getRunner(const QString& runnerId) const;
    QList<RunnerRecord> getAllRunners() const;

    // Controller Emulation State Management
    bool setAllGamesXboxEmulationState(bool enabled);

private:
    QString m_dbPath;
    QString m_connectionName;
    mutable QMutex m_mutex;

    QSqlDatabase db() const;
    static GameRecord recordFromQuery(class QSqlQuery& q);
    static EpicLibraryItem epicItemFromQuery(class QSqlQuery& q);
    static PrefixRecord prefixFromQuery(class QSqlQuery& q);
    static RunnerRecord runnerFromQuery(class QSqlQuery& q);
};

} // namespace Tsuki

