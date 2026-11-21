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

class EpicService;

class GameListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int filterType READ filterType WRITE setFilterType NOTIFY filterTypeChanged)
    Q_PROPERTY(int sortMode READ sortMode WRITE setSortMode NOTIFY sortModeChanged)
    Q_PROPERTY(QString categoryFilter READ categoryFilter WRITE setCategoryFilter NOTIFY categoryFilterChanged)
    Q_PROPERTY(QStringList activeFilters READ activeFilters WRITE setActiveFilters NOTIFY activeFiltersChanged)
    Q_PROPERTY(QStringList activeCategories READ activeCategories WRITE setActiveCategories NOTIFY activeCategoriesChanged)
    Q_PROPERTY(bool hasActiveFilters READ hasActiveFilters NOTIFY activeFiltersChanged)
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
        IsHiddenRole,
        IsRunningRole,
        PlaytimeSecondsRole,
        PlaytimeFormattedRole,
        LastPlayedFormattedRole,
        CategoryRole,
        CategoriesRole,
        PrefixIdRole,
        ExecutablePathRole,
        PlatformRole,
        IsNativeRole,
        SourceRole,
        IsEpicRole,
        EpicAppNameRole,
        HasUpdateRole
    };

    explicit GameListModel(DatabaseManager* db,
                           RunnerManager* runnerMgr,
                           LaunchPipeline* launchPipeline,
                           QObject* parent = nullptr);

    void setEpicService(EpicService* epicSvc);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int filterType() const { return m_filterType; }
    void setFilterType(int type);

    int sortMode() const { return m_sortMode; }
    void setSortMode(int mode);

    QString categoryFilter() const { return m_categoryFilter; }
    void setCategoryFilter(const QString& cat);

    QStringList activeFilters() const { return m_activeFilters; }
    void setActiveFilters(const QStringList& filters);
    QStringList activeCategories() const { return m_activeCategories; }
    void setActiveCategories(const QStringList& categories);
    bool hasActiveFilters() const {
        return m_filterType != -1 || !m_categoryFilter.isEmpty() || !m_activeFilters.isEmpty() || !m_activeCategories.isEmpty();
    }
    Q_INVOKABLE void toggleFilter(const QString& filterKey);
    Q_INVOKABLE void toggleCategory(const QString& categoryName);
    Q_INVOKABLE void clearFilters();

    void setSearchQuery(const QString& query);
    QString searchQuery() const { return m_searchQuery; }

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE void reload();

signals:
    void filterTypeChanged();
    void sortModeChanged();
    void categoryFilterChanged();
    void activeFiltersChanged();
    void activeCategoriesChanged();
    void countChanged();

private:
    DatabaseManager* m_db;
    RunnerManager* m_runnerMgr;
    LaunchPipeline* m_launchPipeline;
    EpicService* m_epicService = nullptr;

    int m_filterType = -1;
    int m_sortMode = 0;
    QString m_categoryFilter;
    QStringList m_activeFilters;
    QStringList m_activeCategories;
    QString m_searchQuery;
    QList<GameRecord> m_visibleGames;
};

class GameManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList categories READ categories NOTIFY gamesChanged)
    Q_PROPERTY(bool isRelocating READ isRelocating NOTIFY relocatingChanged)
    Q_PROPERTY(double relocationProgress READ relocationProgress NOTIFY relocatingChanged)

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
    bool isRelocating() const { return m_isRelocating; }
    double relocationProgress() const { return m_relocationProgress; }
    void setEpicService(EpicService* epicSvc);

    // Core Game CRUD
    Q_INVOKABLE QString detectPlatform(const QString& path) const;

    Q_INVOKABLE QString addGame(const QString& title,
                                const QString& executablePath,
                                const QString& workingDirectory = QString(),
                                const QString& launchArguments = QString(),
                                const QString& runnerId = QString(),
                                const QString& prefixMode = QStringLiteral("dedicated"), // "dedicated" or existing prefixId
                                const QString& customPrefixName = QString(),
                                const QString& customPrefixLocation = QString(),
                                const QString& prefixArch = QStringLiteral("win64"));

    Q_INVOKABLE QString addNativeGame(const QString& title,
                                      const QString& executablePath,
                                      const QString& workingDirectory = QString(),
                                      const QString& launchArguments = QString());

    Q_INVOKABLE QString registerEpicGame(const QString& appName,
                                         const QString& namespaceId,
                                         const QString& catalogItemId,
                                         const QString& title,
                                         const QString& executablePath,
                                         const QString& installDir,
                                         const QString& launchArguments = QString(),
                                         const QString& buildVersion = QString(),
                                         const QString& runnerId = QString(),
                                         const QString& prefixMode = QStringLiteral("default-prefix"),
                                         const QString& customPrefixName = QString(),
                                         const QString& customPrefixLocation = QString(),
                                         const QString& prefixArch = QStringLiteral("win64"),
                                         const QString& coverPath = QString(),
                                         const QString& bannerPath = QString(),
                                         const QString& logoPath = QString(),
                                         bool inPlaceImported = false);

    Q_INVOKABLE bool updateGameDetails(const QString& gameId, const QVariantMap& updates);
    Q_INVOKABLE bool setGameArtwork(const QString& gameId,
                                    const QString& coverPath,
                                    const QString& bannerPath,
                                    const QString& logoPath,
                                    const QString& iconPath);
    Q_INVOKABLE void setGameArtworkFromUrl(const QString& gameId, const QString& type, const QString& url);
    Q_INVOKABLE void refreshArtworkFromSteamGridDb(const QString& gameId);
    Q_INVOKABLE bool removeGame(const QString& gameId, bool deleteDedicatedPrefix = false, bool deleteGameFiles = false);

    Q_INVOKABLE void togglePin(const QString& gameId);
    Q_INVOKABLE void toggleFavorite(const QString& gameId);
    Q_INVOKABLE void toggleHidden(const QString& gameId);

    // Collections / Categories Management
    Q_INVOKABLE bool createCollection(const QString& name);
    Q_INVOKABLE bool renameCollection(const QString& oldName, const QString& newName);
    Q_INVOKABLE bool deleteCollection(const QString& name);
    Q_INVOKABLE bool setGameCategories(const QString& gameId, const QStringList& categories);
    Q_INVOKABLE bool addGameToCollection(const QString& gameId, const QString& collectionName);
    Q_INVOKABLE bool removeGameFromCollection(const QString& gameId, const QString& collectionName);

    // Move / Relocate Installed Game Folder
    Q_INVOKABLE void relocateGame(const QString& gameId, const QString& targetParentDir);

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
    void relocatingChanged();
    void gameRelocationFinished(const QString& gameId, bool success, const QString& newPath);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    PrefixManager* m_prefixMgr;
    SteamGridDbService* m_sgdb;
    LaunchPipeline* m_launchPipeline;
    EpicService* m_epicService = nullptr;
    GameListModel* m_model;
    bool m_isRelocating = false;
    double m_relocationProgress = 0.0;
};

} // namespace Tsuki

