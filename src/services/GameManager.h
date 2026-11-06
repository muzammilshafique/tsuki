#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "RunnerManager.h"
#include "PrefixManager.h"
#include "SteamGridDbService.h"
#include "LaunchPipeline.h"
#include <QAbstractListModel>
#include <QVariantList>
#include <QVariantMap>

namespace Tsuki {

class GameListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int filterType READ filterType WRITE setFilterType NOTIFY filterTypeChanged)
    Q_PROPERTY(int sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)
    Q_PROPERTY(QString categoryFilter READ categoryFilter WRITE setCategoryFilter NOTIFY categoryFilterChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum GameRoles {
        IdRole = Qt::UserRole + 1,
        GameIdRole,
        TmdbIdRole,
        TitleRole,
        YearRole,
        ReleaseYearRole,
        CoverPathRole,
        BannerPathRole,
        LogoPathRole,
        IconPathRole,
        TypeRole,
        RunnerTagRole,
        IsPinnedRole,
        IsFavoriteRole,
        IsRunningRole,
        PlaytimeSecondsRole,
        PlaytimeFormattedRole,
        LastPlayedFormattedRole,
        CategoryRole,
        PrefixIdRole,
        ExecutablePathRole
    };

    explicit GameListModel(DatabaseManager* db,
                           RunnerManager* runnerMgr,
                           LaunchPipeline* launchPipeline,
                           QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int filterType() const { return m_filterType; }
    void setFilterType(int type);

    int sortMode() const { return m_sortMode; }
    void setSortMode(int mode);

    QString categoryFilter() const { return m_categoryFilter; }
    void setCategoryFilter(const QString& cat);

    void setSearchQuery(const QString& query);
    QString searchQuery() const { return m_searchQuery; }

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE void reload();

signals:
    void filterTypeChanged();
    void sortModeChanged();
    void categoryFilterChanged();
    void countChanged();

private:
    DatabaseManager* m_db;
    RunnerManager* m_runnerMgr;
    LaunchPipeline* m_launchPipeline;

    int m_filterType = -1;
    int m_sortMode = 0;
    QString m_categoryFilter;
    QString m_searchQuery;
    QList<GameRecord> m_visibleGames;
};

class GameManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList categories READ categories NOTIFY gamesChanged)

public:
    explicit GameManager(DatabaseManager* db,
                         AppSettings* settings,
                         RunnerManager* runnerMgr,
                         PrefixManager* prefixMgr,
                         SteamGridDbService* sgdb,
                         LaunchPipeline* launchPipeline,
                         QObject* parent = nullptr);

    GameListModel* model() const { return m_model; }
    QStringList categories() const;

    // Core Game CRUD
    Q_INVOKABLE QString addGame(const QString& title,
                                const QString& executablePath,
                                const QString& workingDirectory = QString(),
                                const QString& launchArguments = QString(),
                                const QString& runnerId = QString(),
                                const QString& prefixMode = QStringLiteral("dedicated"), // "dedicated" or existing prefixId
                                const QString& customPrefixName = QString(),
                                const QString& customPrefixLocation = QString(),
                                const QString& prefixArch = QStringLiteral("win64"));

    Q_INVOKABLE bool updateGameDetails(const QString& gameId, const QVariantMap& updates);
    Q_INVOKABLE bool setGameArtwork(const QString& gameId,
                                    const QString& coverPath,
                                    const QString& bannerPath,
                                    const QString& logoPath,
                                    const QString& iconPath);
    Q_INVOKABLE void setGameArtworkFromUrl(const QString& gameId, const QString& type, const QString& url);
    Q_INVOKABLE void refreshArtworkFromSteamGridDb(const QString& gameId);
    Q_INVOKABLE bool removeGame(const QString& gameId, bool deleteDedicatedPrefix = false);

    Q_INVOKABLE void togglePin(const QString& gameId);
    Q_INVOKABLE void toggleFavorite(const QString& gameId);

    Q_INVOKABLE QVariantMap getGameMap(const QString& gameId) const;
    Q_INVOKABLE bool createDesktopShortcut(const QString& gameId, bool alsoOnDesktop = true);
    Q_INVOKABLE void openGameDirectory(const QString& gameId);

    Q_INVOKABLE void syncXboxEmulationToAllGames(bool enabled);

    // Helper to infer game title from .exe path
    Q_INVOKABLE QString guessTitleFromExecutable(const QString& exePath) const;

signals:
    void gamesChanged();
    void gameAdded(const QString& gameId, const QString& title);
    void gameOperationStatus(const QString& message, bool isError);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    PrefixManager* m_prefixMgr;
    SteamGridDbService* m_sgdb;
    LaunchPipeline* m_launchPipeline;
    GameListModel* m_model;
};

} // namespace Tsuki

