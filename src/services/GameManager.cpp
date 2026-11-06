#include "GameManager.h"
#include <QFileInfo>
#include <QDir>
#include <QFile>
#include <QUrl>
#include <QUuid>
#include <QDateTime>
#include <QDesktopServices>
#include <QCoreApplication>
#include <QRegularExpression>
#include <algorithm>

namespace Tsuki {

GameListModel::GameListModel(DatabaseManager* db,
                             RunnerManager* runnerMgr,
                             LaunchPipeline* launchPipeline,
                             QObject* parent)
    : QAbstractListModel(parent)
    , m_db(db)
    , m_runnerMgr(runnerMgr)
    , m_launchPipeline(launchPipeline)
{
    connect(m_launchPipeline, &LaunchPipeline::runningGamesChanged, this, &GameListModel::reload);
    connect(m_launchPipeline, &LaunchPipeline::gameStopped, this, [this]() { reload(); });
    connect(m_runnerMgr, &RunnerManager::runnersChanged, this, &GameListModel::reload);
    reload();
}

int GameListModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_visibleGames.size();
}

QHash<int, QByteArray> GameListModel::roleNames() const {
    return {
        {IdRole, "id"},
        {GameIdRole, "gameId"},
        {TmdbIdRole, "tmdbId"},
        {TitleRole, "title"},
        {YearRole, "year"},
        {ReleaseYearRole, "releaseYear"},
        {CoverPathRole, "coverPath"},
        {BannerPathRole, "bannerPath"},
        {LogoPathRole, "logoPath"},
        {IconPathRole, "iconPath"},
        {TypeRole, "type"},
        {RunnerTagRole, "runnerTag"},
        {IsPinnedRole, "isPinned"},
        {IsFavoriteRole, "isFavorite"},
        {IsRunningRole, "isRunning"},
        {PlaytimeSecondsRole, "playtimeSeconds"},
        {PlaytimeFormattedRole, "playtimeFormatted"},
        {LastPlayedFormattedRole, "lastPlayedFormatted"},
        {CategoryRole, "category"},
        {PrefixIdRole, "prefixId"},
        {ExecutablePathRole, "executablePath"}
    };
}

QVariant GameListModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visibleGames.size()) {
        return QVariant();
    }
    const GameRecord& g = m_visibleGames.at(index.row());
    const bool running = m_launchPipeline->isGameRunning(g.id);
    const QString runnerTag = m_runnerMgr->runnerTagForId(g.runnerId);

    switch (role) {
        case IdRole:
        case GameIdRole:
        case TmdbIdRole: return g.id;
        case TitleRole: return g.title;
        case YearRole: return running ? QStringLiteral("RUNNING") : (g.playtimeSeconds > 0 ? GameRecord::formatPlaytime(g.playtimeSeconds) : g.releaseYear);
        case ReleaseYearRole: return g.releaseYear;
        case CoverPathRole: return QUrl(GameRecord::toFileUrlOrOriginal(g.coverPath));
        case BannerPathRole: return QUrl(GameRecord::toFileUrlOrOriginal(g.bannerPath));
        case LogoPathRole: return QUrl(GameRecord::toFileUrlOrOriginal(g.logoPath));
        case IconPathRole: return QUrl(GameRecord::toFileUrlOrOriginal(g.iconPath));
        case TypeRole: {
            if (runnerTag.contains(QStringLiteral("PROTON"))) return 0;
            if (runnerTag.contains(QStringLiteral("STAGING")) || runnerTag.contains(QStringLiteral("CUSTOM"))) return 2;
            return 1;
        }
        case RunnerTagRole: return runnerTag;
        case IsPinnedRole: return g.isPinned;
        case IsFavoriteRole: return g.isFavorite;
        case IsRunningRole: return running;
        case PlaytimeSecondsRole: return g.playtimeSeconds;
        case PlaytimeFormattedRole: return GameRecord::formatPlaytime(g.playtimeSeconds);
        case LastPlayedFormattedRole: return GameRecord::formatLastPlayed(g.lastPlayedTimestamp);
        case CategoryRole: return g.category;
        case PrefixIdRole: return g.prefixId;
        case ExecutablePathRole: return g.executablePath;
        default: return QVariant();
    }
}

QVariantMap GameListModel::get(int row) const {
    if (row < 0 || row >= m_visibleGames.size()) return QVariantMap();
    const GameRecord& g = m_visibleGames.at(row);
    return g.toVariantMap(m_launchPipeline->isGameRunning(g.id), m_runnerMgr->runnerTagForId(g.runnerId));
}

void GameListModel::setFilterType(int type) {
    if (m_filterType == type) return;
    m_filterType = type;
    emit filterTypeChanged();
    reload();
}

void GameListModel::setSortMode(int mode) {
    if (m_sortMode == mode) return;
    m_sortMode = mode;
    emit sortModeChanged();
    reload();
}

void GameListModel::setCategoryFilter(const QString& cat) {
    if (m_categoryFilter == cat) return;
    m_categoryFilter = cat;
    emit categoryFilterChanged();
    reload();
}

void GameListModel::setSearchQuery(const QString& query) {
    const QString trimmed = query.trimmed();
    if (m_searchQuery == trimmed) return;
    m_searchQuery = trimmed;
    reload();
}

void GameListModel::reload() {
    beginResetModel();
    const QList<GameRecord> all = m_db->getAllGames();
    m_visibleGames.clear();

    const QString q = m_searchQuery.toLower();
    for (const GameRecord& g : all) {
        const QString rTag = m_runnerMgr->runnerTagForId(g.runnerId);
        const bool running = m_launchPipeline->isGameRunning(g.id);

        if (m_filterType == 0 && !rTag.contains(QStringLiteral("PROTON"))) continue;
        if (m_filterType == 1 && rTag.contains(QStringLiteral("PROTON"))) continue;
        if (m_filterType == 2 && !running) continue;
        if (m_filterType == 3 && !g.isFavorite) continue;
        if (m_filterType == 4 && g.lastPlayedTimestamp <= 0) continue;

        if (!m_categoryFilter.isEmpty() && m_categoryFilter != QStringLiteral("All") &&
            g.category.compare(m_categoryFilter, Qt::CaseInsensitive) != 0) {
            continue;
        }

        if (!q.isEmpty() &&
            !g.title.toLower().contains(q) &&
            !g.category.toLower().contains(q) &&
            !g.executablePath.toLower().contains(q)) {
            continue;
        }

        m_visibleGames.append(g);
    }

    std::sort(m_visibleGames.begin(), m_visibleGames.end(), [this](const GameRecord& a, const GameRecord& b) {
        if (a.isPinned != b.isPinned) return a.isPinned > b.isPinned;
        switch (m_sortMode) {
            case 1: // Title A -> Z
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
            case 2: // Title Z -> A
                return a.title.compare(b.title, Qt::CaseInsensitive) > 0;
            case 3: // Most Played
                if (a.playtimeSeconds != b.playtimeSeconds) return a.playtimeSeconds > b.playtimeSeconds;
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
            case 4: // Recently Added
                if (a.addedTimestamp != b.addedTimestamp) return a.addedTimestamp > b.addedTimestamp;
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
            default: // Recently Played / Default
                if (a.lastPlayedTimestamp != b.lastPlayedTimestamp) return a.lastPlayedTimestamp > b.lastPlayedTimestamp;
                if (a.addedTimestamp != b.addedTimestamp) return a.addedTimestamp > b.addedTimestamp;
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
        }
    });

    endResetModel();
    emit countChanged();
}

GameManager::GameManager(DatabaseManager* db,
                         AppSettings* settings,
                         RunnerManager* runnerMgr,
                         PrefixManager* prefixMgr,
                         SteamGridDbService* sgdb,
                         LaunchPipeline* launchPipeline,
                         QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_runnerMgr(runnerMgr)
    , m_prefixMgr(prefixMgr)
    , m_sgdb(sgdb)
    , m_launchPipeline(launchPipeline)
    , m_model(new GameListModel(db, runnerMgr, launchPipeline, this))
{
}

QStringList GameManager::categories() const {
    QStringList cats = {QStringLiteral("All"), QStringLiteral("Action"), QStringLiteral("RPG"), QStringLiteral("Adventure"), QStringLiteral("Strategy"), QStringLiteral("Indie"), QStringLiteral("Uncategorized")};
    for (const GameRecord& g : m_db->getAllGames()) {
        if (!g.category.isEmpty() && !cats.contains(g.category)) {
            cats.append(g.category);
        }
    }
    return cats;
}

QString GameManager::guessTitleFromExecutable(const QString& exePath) const {
    QString clean = exePath.trimmed();
    if (clean.startsWith(QStringLiteral("file://"))) {
        clean = QUrl(clean).toLocalFile();
    }
    QFileInfo fi(clean);
    QString candidate = fi.completeBaseName();

    const QStringList genericNames = {
        QStringLiteral("game"), QStringLiteral("Shipping"), QStringLiteral("Launcher"),
        QStringLiteral("start"), QStringLiteral("play"), QStringLiteral("bin"),
        QStringLiteral("Win64"), QStringLiteral("x64")
    };
    bool isGeneric = candidate.length() <= 3;
    for (const QString& g : genericNames) {
        if (candidate.contains(g, Qt::CaseInsensitive)) {
            isGeneric = true;
            break;
        }
    }
    if (isGeneric) {
        QDir dir = fi.absoluteDir();
        if (dir.dirName().compare(QStringLiteral("bin"), Qt::CaseInsensitive) == 0 ||
            dir.dirName().compare(QStringLiteral("Win64"), Qt::CaseInsensitive) == 0 ||
            dir.dirName().compare(QStringLiteral("x64"), Qt::CaseInsensitive) == 0) {
            dir.cdUp();
        }
        if (!dir.dirName().isEmpty()) {
            candidate = dir.dirName();
        }
    }

    candidate.replace(QLatin1Char('_'), QLatin1Char(' '));
    candidate.replace(QLatin1Char('-'), QLatin1Char(' '));
    // Split camelCase words like "GrandTheftAuto" -> "Grand Theft Auto"
    candidate.replace(QRegularExpression(QStringLiteral("([a-z])([A-Z])")), QStringLiteral("\\1 \\2"));
    return candidate.simplified();
}

QString GameManager::addGame(const QString& title,
                             const QString& executablePath,
                             const QString& workingDirectory,
                             const QString& launchArguments,
                             const QString& runnerId,
                             const QString& prefixMode,
                             const QString& customPrefixName,
                             const QString& customPrefixLocation,
                             const QString& prefixArch,
                             const QString& category)
{
    QString cleanExe = executablePath.trimmed();
    if (cleanExe.startsWith(QStringLiteral("file://"))) {
        cleanExe = QUrl(cleanExe).toLocalFile();
    }
    if (cleanExe.isEmpty()) {
        emit gameOperationStatus(QStringLiteral("Please select a valid Windows executable (.exe)."), true);
        return QString();
    }

    QFileInfo exeFi(cleanExe);
    const QString cleanTitle = title.trimmed().isEmpty() ? guessTitleFromExecutable(cleanExe) : title.trimmed();

    QString cleanWorkDir = workingDirectory.trimmed();
    if (cleanWorkDir.startsWith(QStringLiteral("file://"))) {
        cleanWorkDir = QUrl(cleanWorkDir).toLocalFile();
    }
    if (cleanWorkDir.isEmpty()) {
        cleanWorkDir = exeFi.absolutePath();
    }

    GameRecord rec;
    rec.id = QStringLiteral("game-") + QUuid::createUuid().toString(QUuid::Id128).left(10);
    rec.title = cleanTitle;
    rec.executablePath = exeFi.absoluteFilePath();
    rec.workingDirectory = cleanWorkDir;
    rec.launchArguments = launchArguments.trimmed();
    rec.runnerId = runnerId;
    rec.category = category.trimmed().isEmpty() ? QStringLiteral("Uncategorized") : category.trimmed();
    rec.addedTimestamp = QDateTime::currentSecsSinceEpoch();

    // Prefix resolution: either create a dedicated prefix or bind to an existing prefix ID
    if (prefixMode.isEmpty() || prefixMode == QStringLiteral("dedicated")) {
        const QString pfxName = customPrefixName.trimmed().isEmpty()
                                    ? m_prefixMgr->suggestShortPrefixName(cleanTitle)
                                    : customPrefixName.trimmed();
        rec.prefixId = m_prefixMgr->createPrefix(pfxName,
                                                 customPrefixLocation,
                                                 prefixArch.isEmpty() ? QStringLiteral("win64") : prefixArch,
                                                 QStringLiteral("win10"),
                                                 runnerId,
                                                 false);
    } else {
        rec.prefixId = prefixMode;
    }

    // Generate immediate fallback SVG poster & banner, then trigger async SteamGridDB/Steam artwork fetch
    rec.coverPath = SteamGridDbService::generateFallbackPoster(rec.id, rec.title);
    rec.bannerPath = SteamGridDbService::generateFallbackBanner(rec.id, rec.title);

    m_db->saveGame(rec);
    m_model->reload();
    emit gamesChanged();
    emit gameAdded(rec.id, rec.title);
    emit gameOperationStatus(QStringLiteral("Added '%1' to library.").arg(rec.title), false);

    refreshArtworkFromSteamGridDb(rec.id);
    return rec.id;
}

bool GameManager::updateGameDetails(const QString& gameId, const QVariantMap& updates) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return false;
    GameRecord g = *opt;

    auto cleanPath = [](const QString& p) {
        return p.startsWith(QStringLiteral("file://")) ? QUrl(p).toLocalFile() : p.trimmed();
    };

    if (updates.contains(QStringLiteral("title"))) g.title = updates.value(QStringLiteral("title")).toString().trimmed();
    if (updates.contains(QStringLiteral("executablePath"))) g.executablePath = cleanPath(updates.value(QStringLiteral("executablePath")).toString());
    if (updates.contains(QStringLiteral("workingDirectory"))) g.workingDirectory = cleanPath(updates.value(QStringLiteral("workingDirectory")).toString());
    if (updates.contains(QStringLiteral("launchArguments"))) g.launchArguments = updates.value(QStringLiteral("launchArguments")).toString().trimmed();
    if (updates.contains(QStringLiteral("runnerId"))) g.runnerId = updates.value(QStringLiteral("runnerId")).toString();
    if (updates.contains(QStringLiteral("prefixId"))) g.prefixId = updates.value(QStringLiteral("prefixId")).toString();
    if (updates.contains(QStringLiteral("category"))) g.category = updates.value(QStringLiteral("category")).toString().trimmed();
    if (updates.contains(QStringLiteral("releaseYear"))) g.releaseYear = updates.value(QStringLiteral("releaseYear")).toString().trimmed();

    if (updates.contains(QStringLiteral("dxvkState"))) g.dxvkState = updates.value(QStringLiteral("dxvkState")).toInt();
    if (updates.contains(QStringLiteral("vkd3dState"))) g.vkd3dState = updates.value(QStringLiteral("vkd3dState")).toInt();
    if (updates.contains(QStringLiteral("esyncState"))) g.esyncState = updates.value(QStringLiteral("esyncState")).toInt();
    if (updates.contains(QStringLiteral("fsyncState"))) g.fsyncState = updates.value(QStringLiteral("fsyncState")).toInt();
    if (updates.contains(QStringLiteral("dxvkHud"))) g.dxvkHud = updates.value(QStringLiteral("dxvkHud")).toString();
    if (updates.contains(QStringLiteral("virtualDesktop"))) g.virtualDesktop = updates.value(QStringLiteral("virtualDesktop")).toBool();
    if (updates.contains(QStringLiteral("virtualDesktopResolution"))) g.virtualDesktopResolution = updates.value(QStringLiteral("virtualDesktopResolution")).toString().trimmed();
    if (updates.contains(QStringLiteral("preLaunchScript"))) g.preLaunchScript = updates.value(QStringLiteral("preLaunchScript")).toString();
    if (updates.contains(QStringLiteral("postExitScript"))) g.postExitScript = updates.value(QStringLiteral("postExitScript")).toString();
    if (updates.contains(QStringLiteral("cpuAffinity"))) g.cpuAffinity = updates.value(QStringLiteral("cpuAffinity")).toString().trimmed();
    if (updates.contains(QStringLiteral("processPriority"))) g.processPriority = updates.value(QStringLiteral("processPriority")).toInt();
    if (updates.contains(QStringLiteral("mangohudState"))) g.mangohudState = updates.value(QStringLiteral("mangohudState")).toInt();
    if (updates.contains(QStringLiteral("gamemodeState"))) g.gamemodeState = updates.value(QStringLiteral("gamemodeState")).toInt();
    if (updates.contains(QStringLiteral("controllerProfileId"))) g.controllerProfileId = updates.value(QStringLiteral("controllerProfileId")).toString();
    if (updates.contains(QStringLiteral("xboxEmulationState"))) g.xboxEmulationState = updates.value(QStringLiteral("xboxEmulationState")).toInt();
    if (updates.contains(QStringLiteral("environmentVariables"))) g.environmentVariables = updates.value(QStringLiteral("environmentVariables")).toMap();
    if (updates.contains(QStringLiteral("dllOverrides"))) g.dllOverrides = updates.value(QStringLiteral("dllOverrides")).toMap();

    const bool ok = m_db->saveGame(g);
    if (ok) {
        m_model->reload();
        emit gamesChanged();
        emit gameOperationStatus(QStringLiteral("Saved configuration for '%1'.").arg(g.title), false);
    }
    return ok;
}

bool GameManager::setGameArtwork(const QString& gameId,
                                 const QString& coverPath,
                                 const QString& bannerPath,
                                 const QString& logoPath,
                                 const QString& iconPath)
{
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return false;
    GameRecord g = *opt;

    auto cleanPath = [](const QString& p) {
        return p.startsWith(QStringLiteral("file://")) ? QUrl(p).toLocalFile() : p.trimmed();
    };

    if (!coverPath.isEmpty()) g.coverPath = cleanPath(coverPath);
    if (!bannerPath.isEmpty()) g.bannerPath = cleanPath(bannerPath);
    if (!logoPath.isEmpty()) g.logoPath = cleanPath(logoPath);
    if (!iconPath.isEmpty()) g.iconPath = cleanPath(iconPath);

    const bool ok = m_db->saveGame(g);
    if (ok) {
        m_model->reload();
        emit gamesChanged();
    }
    return ok;
}

void GameManager::refreshArtworkFromSteamGridDb(const QString& gameId) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return;
    const QString title = opt->title;

    m_sgdb->fetchArtworkForGame(gameId, title, [this, gameId](const QString& cover,
                                                              const QString& banner,
                                                              const QString& logo,
                                                              const QString& icon,
                                                              const QString& year) {
        auto gOpt = m_db->getGame(gameId);
        if (!gOpt.has_value()) return;
        GameRecord g = *gOpt;
        bool changed = false;
        if (!cover.isEmpty()) { g.coverPath = cover; changed = true; }
        if (!banner.isEmpty()) { g.bannerPath = banner; changed = true; }
        if (!logo.isEmpty()) { g.logoPath = logo; changed = true; }
        if (!icon.isEmpty()) { g.iconPath = icon; changed = true; }
        if (!year.isEmpty() && g.releaseYear.isEmpty()) { g.releaseYear = year; changed = true; }
        if (changed) {
            m_db->saveGame(g);
            m_model->reload();
            emit gamesChanged();
        }
    });
}

bool GameManager::removeGame(const QString& gameId, bool deleteDedicatedPrefix) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return false;
    const GameRecord g = *opt;

    if (m_launchPipeline->isGameRunning(gameId)) {
        m_launchPipeline->stopGame(gameId);
    }

    if (deleteDedicatedPrefix && !g.prefixId.isEmpty() && g.prefixId != QStringLiteral("default-prefix")) {
        m_prefixMgr->deletePrefix(g.prefixId, true);
    }

    // Note: Per specification, removing a game from the library NEVER deletes the game's actual files!
    const bool ok = m_db->removeGame(gameId);
    if (ok) {
        m_model->reload();
        emit gamesChanged();
        emit gameOperationStatus(QStringLiteral("Removed '%1' from library (game files preserved).").arg(g.title), false);
    }
    return ok;
}

void GameManager::togglePin(const QString& gameId) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return;
    GameRecord g = *opt;
    g.isPinned = !g.isPinned;
    m_db->saveGame(g);
    m_model->reload();
    emit gamesChanged();
}

void GameManager::toggleFavorite(const QString& gameId) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return;
    GameRecord g = *opt;
    g.isFavorite = !g.isFavorite;
    m_db->saveGame(g);
    m_model->reload();
    emit gamesChanged();
}

QVariantMap GameManager::getGameMap(const QString& gameId) const {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return QVariantMap();
    return opt->toVariantMap(m_launchPipeline->isGameRunning(gameId), m_runnerMgr->runnerTagForId(opt->runnerId));
}

bool GameManager::createDesktopShortcut(const QString& gameId, bool alsoOnDesktop) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return false;
    const GameRecord g = *opt;

    QString appBin = QCoreApplication::applicationFilePath();
    if (appBin.isEmpty()) appBin = QStringLiteral("tsuki");

    const QString iconPath = !g.iconPath.isEmpty() ? g.iconPath : (!g.coverPath.isEmpty() ? g.coverPath : QStringLiteral("applications-games"));

    const QString desktopContent = QStringLiteral(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=%1\n"
        "Comment=Launch %1 via Tsuki Game Launcher\n"
        "Exec=\"%2\" --launch %3\n"
        "Path=%4\n"
        "Icon=%5\n"
        "Terminal=false\n"
        "Categories=Game;\n"
        "StartupNotify=true\n")
        .arg(g.title, appBin, g.id, g.workingDirectory, iconPath);

    QString safeFile = g.title;
    safeFile.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]")), QStringLiteral("_"));
    const QString fileName = QStringLiteral("tsuki-%1.desktop").arg(safeFile.toLower());

    const QString appsDir = QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation);
    QDir().mkpath(appsDir);
    const QString appEntryPath = appsDir + QStringLiteral("/") + fileName;

    QFile f1(appEntryPath);
    bool ok = false;
    if (f1.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        f1.write(desktopContent.toUtf8());
        f1.close();
        f1.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                          QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                          QFileDevice::ReadOther | QFileDevice::ExeOther);
        ok = true;
    }

    if (alsoOnDesktop) {
        const QString desktopDir = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
        if (!desktopDir.isEmpty() && QDir(desktopDir).exists()) {
            const QString deskFilePath = desktopDir + QStringLiteral("/") + fileName;
            QFile f2(deskFilePath);
            if (f2.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                f2.write(desktopContent.toUtf8());
                f2.close();
                f2.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                                  QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                                  QFileDevice::ReadOther | QFileDevice::ExeOther);
            }
        }
    }

    emit gameOperationStatus(ok ? QStringLiteral("Created desktop shortcut for '%1'.").arg(g.title)
                                : QStringLiteral("Failed to write desktop shortcut."),
                             !ok);
    return ok;
}

void GameManager::openGameDirectory(const QString& gameId) {
    auto opt = m_db->getGame(gameId);
    if (!opt.has_value()) return;
    const QString dir = opt->workingDirectory.isEmpty()
                            ? QFileInfo(opt->executablePath).absolutePath()
                            : opt->workingDirectory;
    QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

} // namespace Tsuki

