#include "GameManager.h"
#include "EpicService.h"
#include <QCoreApplication>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QPointer>
#include <QRegularExpression>
#include <QStorageInfo>
#include <QThreadPool>
#include <QUrl>
#include <QUuid>
#include <algorithm>

namespace Tsuki {

GameListModel::GameListModel(DatabaseManager *db, RunnerManager *runnerMgr,
                             LaunchPipeline *launchPipeline, QObject *parent)
    : QAbstractListModel(parent), m_db(db), m_runnerMgr(runnerMgr),
      m_launchPipeline(launchPipeline) {
  connect(m_launchPipeline, &LaunchPipeline::runningGamesChanged, this,
          &GameListModel::reload);
  connect(m_launchPipeline, &LaunchPipeline::gameStopped, this,
          [this]() { reload(); });
  connect(m_runnerMgr, &RunnerManager::runnersChanged, this,
          &GameListModel::reload);
  reload();
}

void GameListModel::setEpicService(EpicService *epicSvc) {
  if (m_epicService == epicSvc) return;
  m_epicService = epicSvc;
  if (m_epicService) {
    connect(m_epicService, &EpicService::updatesChanged, this, &GameListModel::reload);
  }
}

int GameListModel::rowCount(const QModelIndex &parent) const {
  if (parent.isValid())
    return 0;
  return m_visibleGames.size();
}

QHash<int, QByteArray> GameListModel::roleNames() const {
  return {{IdRole, "id"},
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
          {IsHiddenRole, "isHidden"},
          {IsRunningRole, "isRunning"},
          {PlaytimeSecondsRole, "playtimeSeconds"},
          {PlaytimeFormattedRole, "playtimeFormatted"},
          {LastPlayedFormattedRole, "lastPlayedFormatted"},
          {CategoryRole, "category"},
          {CategoriesRole, "categories"},
          {PrefixIdRole, "prefixId"},
          {ExecutablePathRole, "executablePath"},
          {PlatformRole, "platform"},
          {IsNativeRole, "isNative"},
          {SourceRole, "source"},
          {IsEpicRole, "isEpic"},
          {EpicAppNameRole, "epicAppName"},
          {HasUpdateRole, "hasUpdate"}};
}

QVariant GameListModel::data(const QModelIndex &index, int role) const {
  if (!index.isValid() || index.row() < 0 ||
      index.row() >= m_visibleGames.size()) {
    return QVariant();
  }
  const GameRecord &g = m_visibleGames.at(index.row());
  const bool running = m_launchPipeline->isGameRunning(g.id);
  const QString runnerTag = m_runnerMgr->runnerTagForId(g.runnerId);
  const bool hasUpd = (g.isEpic() && m_epicService && m_epicService->hasUpdate(g.epicAppName));

  switch (role) {
  case IdRole:
  case GameIdRole:
  case TmdbIdRole:
    return g.id;
  case TitleRole:
    return g.title;
  case YearRole:
    return running ? QStringLiteral("RUNNING")
                   : GameRecord::formatPlaytime(g.playtimeSeconds);
  case ReleaseYearRole:
    return QString();
  case CoverPathRole:
    return QUrl(GameRecord::toFileUrlOrOriginal(g.coverPath));
  case BannerPathRole:
    return QUrl(GameRecord::toFileUrlOrOriginal(g.bannerPath));
  case LogoPathRole:
    return QUrl(GameRecord::toFileUrlOrOriginal(g.logoPath));
  case IconPathRole:
    return QUrl(GameRecord::toFileUrlOrOriginal(g.iconPath));
  case TypeRole: {
    if (g.isNative())
      return 3;
    if (runnerTag.contains(QStringLiteral("PROTON")) ||
        runnerTag.contains(QStringLiteral("CACHYOS")) ||
        runnerTag.contains(QStringLiteral("SAREK")))
      return 0;
    if (runnerTag.contains(QStringLiteral("STAGING")) ||
        runnerTag.contains(QStringLiteral("CUSTOM")))
      return 2;
    return 1;
  }
  case RunnerTagRole:
    return g.isNative() ? QStringLiteral("LINUX") : runnerTag;
  case IsPinnedRole:
    return g.isPinned;
  case IsFavoriteRole:
    return g.isFavorite;
  case IsHiddenRole:
    return g.isHidden;
  case IsRunningRole:
    return running;
  case PlaytimeSecondsRole:
    return g.playtimeSeconds;
  case PlaytimeFormattedRole:
    return GameRecord::formatPlaytime(g.playtimeSeconds);
  case LastPlayedFormattedRole:
    return GameRecord::formatLastPlayed(g.lastPlayedTimestamp);
  case CategoryRole:
    return g.categories.isEmpty() ? QString() : g.categories.first();
  case CategoriesRole:
    return g.categories;
  case PrefixIdRole:
    return g.prefixId;
  case ExecutablePathRole:
    return g.executablePath;
  case PlatformRole:
    return g.platform;
  case IsNativeRole:
    return g.isNative();
  case SourceRole:
    return g.source;
  case IsEpicRole:
    return g.isEpic();
  case EpicAppNameRole:
    return g.epicAppName;
  case HasUpdateRole:
    return hasUpd;
  default:
    return QVariant();
  }
}

QVariantMap GameListModel::get(int row) const {
  if (row < 0 || row >= m_visibleGames.size())
    return QVariantMap();
  const GameRecord &g = m_visibleGames.at(row);
  const bool hasUpd = (g.isEpic() && m_epicService && m_epicService->hasUpdate(g.epicAppName));
  return g.toVariantMap(m_launchPipeline->isGameRunning(g.id),
                        g.isNative() ? QStringLiteral("LINUX") : m_runnerMgr->runnerTagForId(g.runnerId),
                        hasUpd);
}

void GameListModel::setFilterType(int type) {
  if (m_filterType == type)
    return;
  m_filterType = type;
  emit filterTypeChanged();
  emit activeFiltersChanged();
  reload();
}

void GameListModel::setSortMode(int mode) {
  if (m_sortMode == mode)
    return;
  m_sortMode = mode;
  emit sortModeChanged();
  reload();
}

void GameListModel::setCategoryFilter(const QString &cat) {
  if (m_categoryFilter == cat)
    return;
  m_categoryFilter = cat;
  emit categoryFilterChanged();
  emit activeFiltersChanged();
  reload();
}

void GameListModel::setActiveFilters(const QStringList &filters) {
  QStringList clean;
  for (const QString &f : filters) {
    const QString low = f.trimmed().toLower();
    if (!low.isEmpty() && !clean.contains(low)) {
      clean.append(low);
    }
  }
  if (m_activeFilters == clean)
    return;
  m_activeFilters = clean;
  emit activeFiltersChanged();
  reload();
}

void GameListModel::setActiveCategories(const QStringList &categories) {
  QStringList clean;
  for (const QString &c : categories) {
    const QString trimmed = c.trimmed();
    if (!trimmed.isEmpty() && !clean.contains(trimmed, Qt::CaseInsensitive)) {
      clean.append(trimmed);
    }
  }
  if (m_activeCategories == clean)
    return;
  m_activeCategories = clean;
  emit activeCategoriesChanged();
  emit activeFiltersChanged();
  reload();
}

void GameListModel::toggleFilter(const QString &filterKey) {
  const QString low = filterKey.trimmed().toLower();
  if (low.isEmpty()) return;
  QStringList next = m_activeFilters;
  if (next.contains(low)) {
    next.removeAll(low);
  } else {
    next.append(low);
  }
  if (m_filterType != -1) {
    m_filterType = -1;
    emit filterTypeChanged();
  }
  setActiveFilters(next);
}

void GameListModel::toggleCategory(const QString &categoryName) {
  const QString trimmed = categoryName.trimmed();
  if (trimmed.isEmpty()) return;
  QStringList next = m_activeCategories;
  int existingIdx = -1;
  for (int i = 0; i < next.size(); ++i) {
    if (next.at(i).compare(trimmed, Qt::CaseInsensitive) == 0) {
      existingIdx = i;
      break;
    }
  }
  if (existingIdx >= 0) {
    next.removeAt(existingIdx);
  } else {
    next.append(trimmed);
  }
  if (!m_categoryFilter.isEmpty()) {
    m_categoryFilter.clear();
    emit categoryFilterChanged();
  }
  setActiveCategories(next);
}

void GameListModel::clearFilters() {
  bool changed = false;
  if (m_filterType != -1) {
    m_filterType = -1;
    emit filterTypeChanged();
    changed = true;
  }
  if (!m_categoryFilter.isEmpty()) {
    m_categoryFilter.clear();
    emit categoryFilterChanged();
    changed = true;
  }
  if (!m_activeFilters.isEmpty()) {
    m_activeFilters.clear();
    changed = true;
  }
  if (!m_activeCategories.isEmpty()) {
    m_activeCategories.clear();
    emit activeCategoriesChanged();
    changed = true;
  }
  if (changed) {
    emit activeFiltersChanged();
    reload();
  }
}

void GameListModel::setSearchQuery(const QString &query) {
  const QString trimmed = query.trimmed();
  if (m_searchQuery == trimmed)
    return;
  m_searchQuery = trimmed;
  reload();
}

void GameListModel::reload() {
  beginResetModel();
  const QList<GameRecord> all = m_db->getAllGames();
  m_visibleGames.clear();

  const QString q = m_searchQuery.toLower();
  const QString catFilter = m_categoryFilter.trimmed();
  const bool fLinux = m_activeFilters.contains(QStringLiteral("linux"));
  const bool fWindows = m_activeFilters.contains(QStringLiteral("windows"));
  const bool fEpic = m_activeFilters.contains(QStringLiteral("epic"));
  const bool fLocal = m_activeFilters.contains(QStringLiteral("local"));
  const bool fFavourite = m_activeFilters.contains(QStringLiteral("favourite"));

  for (const GameRecord &g : all) {
    const QString rTag = m_runnerMgr->runnerTagForId(g.runnerId);
    const bool running = m_launchPipeline->isGameRunning(g.id);

    // Filter 7 explicitly shows hidden games; all other filters exclude hidden games
    if (m_filterType == 7) {
      if (!g.isHidden) continue;
    } else {
      if (g.isHidden) continue;
    }

    const bool isProtonTag = rTag.contains(QStringLiteral("PROTON")) ||
                             rTag.contains(QStringLiteral("CACHYOS")) ||
                             rTag.contains(QStringLiteral("SAREK"));
    if (m_filterType == 0 && (g.isNative() || !isProtonTag))
      continue;
    if (m_filterType == 1 && (g.isNative() || isProtonTag))
      continue;
    if (m_filterType == 2 && !running)
      continue;
    if (m_filterType == 3 && !g.isFavorite)
      continue;
    if (m_filterType == 4 && !g.isNative())
      continue;
    if (m_filterType == 5 && !g.isEpic())
      continue;
    if (m_filterType == 6 && g.isEpic())
      continue;

    // Multi-select filter pills (AND across groups, OR within Platform / Source groups)
    if (fLinux || fWindows) {
      const bool platMatch = (fLinux && g.isNative()) || (fWindows && !g.isNative());
      if (!platMatch) continue;
    }
    if (fEpic || fLocal) {
      const bool srcMatch = (fEpic && g.isEpic()) || (fLocal && !g.isEpic());
      if (!srcMatch) continue;
    }
    if (fFavourite && !g.isFavorite) {
      continue;
    }

    if (!catFilter.isEmpty() && !g.categories.contains(catFilter, Qt::CaseInsensitive))
      continue;

    if (!m_activeCategories.isEmpty()) {
      bool catMatch = false;
      for (const QString &ac : m_activeCategories) {
        if (g.categories.contains(ac, Qt::CaseInsensitive)) {
          catMatch = true;
          break;
        }
      }
      if (!catMatch) continue;
    }

    if (!q.isEmpty() && !g.title.toLower().contains(q) &&
        !g.executablePath.toLower().contains(q)) {
      continue;
    }

    m_visibleGames.append(g);
  }

  std::sort(m_visibleGames.begin(), m_visibleGames.end(),
            [this](const GameRecord &a, const GameRecord &b) {
              if (a.isPinned != b.isPinned)
                return a.isPinned > b.isPinned;
              switch (m_sortMode) {
              case 1: // Title A -> Z
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
              case 2: // Title Z -> A
                return a.title.compare(b.title, Qt::CaseInsensitive) > 0;
              case 3: // Most Played
                if (a.playtimeSeconds != b.playtimeSeconds)
                  return a.playtimeSeconds > b.playtimeSeconds;
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
              case 4: // Recently Added
                if (a.addedTimestamp != b.addedTimestamp)
                  return a.addedTimestamp > b.addedTimestamp;
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
              default: // Recently Played / Default
                if (a.lastPlayedTimestamp != b.lastPlayedTimestamp)
                  return a.lastPlayedTimestamp > b.lastPlayedTimestamp;
                if (a.addedTimestamp != b.addedTimestamp)
                  return a.addedTimestamp > b.addedTimestamp;
                return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
              }
            });

  endResetModel();
  emit countChanged();
}

GameManager::GameManager(DatabaseManager *db, AppSettings *settings,
                         RunnerManager *runnerMgr, PrefixManager *prefixMgr,
                         SteamGridDbService *sgdb,
                         LaunchPipeline *launchPipeline, QObject *parent)
    : QObject(parent), m_db(db), m_settings(settings), m_runnerMgr(runnerMgr),
      m_prefixMgr(prefixMgr), m_sgdb(sgdb), m_launchPipeline(launchPipeline),
      m_model(new GameListModel(db, runnerMgr, launchPipeline, this)) {
  if (m_settings) {
    connect(m_settings, &AppSettings::controllerDefaultsChanged, this, [this]() {
      syncXboxEmulationToAllGames(m_settings->xboxEmulationDefault());
    });
  }
}

QStringList GameManager::categories() const {
  return m_db ? m_db->getAllCollections() : QStringList();
}

void GameManager::setEpicService(EpicService *epicSvc) {
  m_epicService = epicSvc;
  if (m_model) {
    m_model->setEpicService(epicSvc);
  }
}

QString GameManager::detectPlatform(const QString &path) const {
  QString clean = path.trimmed();
  if (clean.startsWith(QStringLiteral("file://"))) {
    clean = QUrl(clean).toLocalFile();
  }
  if (clean.isEmpty()) {
    return QStringLiteral("windows");
  }

  // 1. Check file magic bytes if file exists
  QFile f(clean);
  if (f.open(QIODevice::ReadOnly)) {
    const QByteArray magic = f.read(4);
    f.close();
    if (magic.size() >= 2 && magic[0] == 'M' && magic[1] == 'Z') {
      return QStringLiteral("windows");
    }
    if (magic.size() >= 4 && magic[0] == 0x7f && magic[1] == 'E' &&
        magic[2] == 'L' && magic[3] == 'F') {
      return QStringLiteral("linux");
    }
    if (magic.size() >= 2 && magic[0] == '#' && magic[1] == '!') {
      return QStringLiteral("linux");
    }
  }

  // 2. Fall back to extension
  const QString lower = clean.toLower();
  if (lower.endsWith(QStringLiteral(".exe")) ||
      lower.endsWith(QStringLiteral(".msi")) ||
      lower.endsWith(QStringLiteral(".bat")) ||
      lower.endsWith(QStringLiteral(".lnk"))) {
    return QStringLiteral("windows");
  }
  if (lower.endsWith(QStringLiteral(".sh")) ||
      lower.endsWith(QStringLiteral(".appimage")) ||
      lower.endsWith(QStringLiteral(".x86_64")) ||
      lower.endsWith(QStringLiteral(".x86")) ||
      lower.endsWith(QStringLiteral(".bin"))) {
    return QStringLiteral("linux");
  }

  return QStringLiteral("windows");
}

QString GameManager::guessTitleFromExecutable(const QString &exePath) const {
  QString clean = exePath.trimmed();
  if (clean.startsWith(QStringLiteral("file://"))) {
    clean = QUrl(clean).toLocalFile();
  }
  QFileInfo fi(clean);
  QString candidate = fi.completeBaseName();

  const QStringList linuxSuffixes = {
      QStringLiteral(".x86_64"), QStringLiteral(".x86"),
      QStringLiteral(".bin"),    QStringLiteral(".sh"),
      QStringLiteral(".AppImage"), QStringLiteral("-linux"),
      QStringLiteral("_linux"), QStringLiteral("_x86_64"),
      QStringLiteral("-x86_64")
  };
  for (const QString &s : linuxSuffixes) {
    if (candidate.endsWith(s, Qt::CaseInsensitive)) {
      candidate.chop(s.length());
    }
  }

  const QStringList genericNames = {
      QStringLiteral("game"),     QStringLiteral("Shipping"),
      QStringLiteral("Launcher"), QStringLiteral("start"),
      QStringLiteral("play"),     QStringLiteral("bin"),
      QStringLiteral("x64"),      QStringLiteral("Release"),
      QStringLiteral("App"),      QStringLiteral("Main"),
      QStringLiteral("run")};
  bool isGeneric = candidate.length() <= 3;
  for (const QString &g : genericNames) {
    if (candidate.contains(g, Qt::CaseInsensitive)) {
      isGeneric = true;
      break;
    }
  }

      // Inspect parent directories for clean game title
      QString parentPath = fi.absolutePath();
      int guard = 0;
      while (guard++ < 8) {
        const QString dirName = QFileInfo(parentPath).fileName();
        if (dirName.compare(QStringLiteral("bin"), Qt::CaseInsensitive) == 0 ||
            dirName.compare(QStringLiteral("Win64"), Qt::CaseInsensitive) ==
                0 ||
            dirName.compare(QStringLiteral("x64"), Qt::CaseInsensitive) == 0 ||
            dirName.compare(QStringLiteral("Binaries"), Qt::CaseInsensitive) ==
                0 ||
            dirName.compare(QStringLiteral("Release"), Qt::CaseInsensitive) ==
                0) {
          int slashIdx = parentPath.lastIndexOf(QLatin1Char('/'));
          if (slashIdx > 0) {
            parentPath = parentPath.left(slashIdx);
          } else {
            break;
          }
        } else {
          break;
        }
        }

        const QString parentName = QFileInfo(parentPath).fileName().trimmed();
        const QStringList nonGameFolderNames = {
            QStringLiteral("Games"),
            QStringLiteral("drive_c"),
            QStringLiteral("Program Files"),
            QStringLiteral("Program Files (x86)"),
            QStringLiteral("windows"),
            QStringLiteral("system32"),
            QStringLiteral("Desktop"),
            QStringLiteral("Downloads"),
            QStringLiteral("Home")};
        bool parentIsGood = !parentName.isEmpty() && parentName.length() >= 4;
        for (const QString &ng : nonGameFolderNames) {
          if (parentName.compare(ng, Qt::CaseInsensitive) == 0) {
            parentIsGood = false;
            break;
          }
        }

        // If executable name is an abbreviation / acronym (<= 6 chars like
        // gta_sa, sh2pc, cp2077), generic, or parent directory has cleaner word
        // spacing, prefer the parent game folder name
        if (parentIsGood && (candidate.length() <= 6 || isGeneric ||
                             (parentName.contains(QLatin1Char(' ')) &&
                              !candidate.contains(QLatin1Char(' '))))) {
          candidate = parentName;
        } else if (isGeneric && !parentName.isEmpty()) {
          candidate = parentName;
        }

        candidate.replace(QLatin1Char('_'), QLatin1Char(' '));
        candidate.replace(QLatin1Char('-'), QLatin1Char(' '));
        // Split camelCase words like "GrandTheftAuto" -> "Grand Theft Auto"
        candidate.replace(QRegularExpression(QStringLiteral("([a-z])([A-Z])")),
                          QStringLiteral("\\1 \\2"));
        // Split letter-number boundaries like "Cyberpunk2077" -> "Cyberpunk
        // 2077"
        candidate.replace(
            QRegularExpression(QStringLiteral("([a-zA-Z])([0-9])")),
            QStringLiteral("\\1 \\2"));
        candidate.replace(
            QRegularExpression(QStringLiteral("([0-9])([a-zA-Z])")),
            QStringLiteral("\\1 \\2"));
        return candidate.simplified();
      }

      QString GameManager::addGame(
          const QString &title, const QString &executablePath,
          const QString &workingDirectory, const QString &launchArguments,
          const QString &runnerId, const QString &prefixMode,
          const QString &customPrefixName, const QString &customPrefixLocation,
          const QString &prefixArch) {
        QString cleanExe = executablePath.trimmed();
        if (cleanExe.startsWith(QStringLiteral("file://"))) {
          cleanExe = QUrl(cleanExe).toLocalFile();
        }
        if (cleanExe.isEmpty()) {
          emit gameOperationStatus(
              QStringLiteral(
                  "Please select a valid Windows executable (.exe)."),
              true);
          return QString();
        }

        QFileInfo exeFi(cleanExe);
        const QString cleanTitle = title.trimmed().isEmpty()
                                       ? guessTitleFromExecutable(cleanExe)
                                       : title.trimmed();

        QString cleanWorkDir = workingDirectory.trimmed();
        if (cleanWorkDir.startsWith(QStringLiteral("file://"))) {
          cleanWorkDir = QUrl(cleanWorkDir).toLocalFile();
        }
        if (cleanWorkDir.isEmpty()) {
          cleanWorkDir = exeFi.absolutePath();
        }

        GameRecord rec;
        rec.id = QStringLiteral("game-") +
                 QUuid::createUuid().toString(QUuid::Id128).left(10);
        rec.title = cleanTitle;
        rec.executablePath = exeFi.absoluteFilePath();
        rec.workingDirectory = cleanWorkDir;
        rec.launchArguments = launchArguments.trimmed();
        rec.runnerId = runnerId;
        rec.xboxEmulationState = m_settings ? (m_settings->xboxEmulationDefault() ? 1 : 0) : 0;
        rec.addedTimestamp = QDateTime::currentSecsSinceEpoch();

        // Prefix resolution: either create a dedicated prefix or bind to an
        // existing prefix ID
        if (prefixMode.isEmpty() || prefixMode == QStringLiteral("dedicated")) {
          const QString pfxName =
              customPrefixName.trimmed().isEmpty()
                  ? m_prefixMgr->suggestShortPrefixName(cleanTitle)
                  : customPrefixName.trimmed();
          rec.prefixId = m_prefixMgr->createPrefix(
              pfxName, customPrefixLocation,
              prefixArch.isEmpty() ? QStringLiteral("win64") : prefixArch,
              QStringLiteral("win10"), runnerId, false);
        } else {
          rec.prefixId = prefixMode;
        }

        // Generate immediate fallback SVG poster & banner, then trigger async
        // SteamGridDB/Steam artwork fetch
        rec.coverPath =
            SteamGridDbService::generateFallbackPoster(rec.id, rec.title);
        rec.bannerPath =
            SteamGridDbService::generateFallbackBanner(rec.id, rec.title);

        m_db->saveGame(rec);
        m_model->reload();
        emit gamesChanged();
        emit gameAdded(rec.id, rec.title);
        emit gameOperationStatus(
            QStringLiteral("Added '%1' to library.").arg(rec.title), false);

        refreshArtworkFromSteamGridDb(rec.id);
        return rec.id;
      }

      QString GameManager::addNativeGame(
          const QString &title, const QString &executablePath,
          const QString &workingDirectory, const QString &launchArguments) {
        QString cleanExe = executablePath.trimmed();
        if (cleanExe.startsWith(QStringLiteral("file://"))) {
          cleanExe = QUrl(cleanExe).toLocalFile();
        }
        if (cleanExe.isEmpty()) {
          emit gameOperationStatus(
              QStringLiteral("Please select a valid Linux executable or script."),
              true);
          return QString();
        }

        QFileInfo exeFi(cleanExe);
        if (exeFi.exists()) {
          QFile::Permissions perms = QFile::permissions(cleanExe);
          if (!(perms & QFile::ExeUser)) {
            QFile::setPermissions(cleanExe, perms | QFile::ExeUser | QFile::ExeGroup | QFile::ExeOther);
          }
        }

        const QString cleanTitle = title.trimmed().isEmpty()
                                       ? guessTitleFromExecutable(cleanExe)
                                       : title.trimmed();

        QString cleanWorkDir = workingDirectory.trimmed();
        if (cleanWorkDir.startsWith(QStringLiteral("file://"))) {
          cleanWorkDir = QUrl(cleanWorkDir).toLocalFile();
        }
        if (cleanWorkDir.isEmpty()) {
          cleanWorkDir = exeFi.absolutePath();
        }

        GameRecord rec;
        rec.id = QStringLiteral("game-") +
                 QUuid::createUuid().toString(QUuid::Id128).left(10);
        rec.platform = QStringLiteral("linux");
        rec.title = cleanTitle;
        rec.executablePath = exeFi.absoluteFilePath();
        rec.workingDirectory = cleanWorkDir;
        rec.launchArguments = launchArguments.trimmed();
        rec.runnerId.clear();
        rec.prefixId.clear();
        rec.xboxEmulationState = m_settings ? (m_settings->xboxEmulationDefault() ? 1 : 0) : 0;
        rec.addedTimestamp = QDateTime::currentSecsSinceEpoch();

        rec.coverPath =
            SteamGridDbService::generateFallbackPoster(rec.id, rec.title);
        rec.bannerPath =
            SteamGridDbService::generateFallbackBanner(rec.id, rec.title);

        m_db->saveGame(rec);
        m_model->reload();
        emit gamesChanged();
        emit gameAdded(rec.id, rec.title);
        emit gameOperationStatus(
            QStringLiteral("Added '%1' to library.").arg(rec.title), false);

        refreshArtworkFromSteamGridDb(rec.id);
        return rec.id;
      }

      QString GameManager::registerEpicGame(
          const QString &appName, const QString &namespaceId,
          const QString &catalogItemId, const QString &title,
          const QString &executablePath, const QString &installDir,
          const QString &launchArguments, const QString &buildVersion,
          const QString &runnerId, const QString &prefixMode,
          const QString &customPrefixName, const QString &customPrefixLocation,
          const QString &prefixArch, const QString &coverPath,
          const QString &bannerPath, const QString &logoPath,
          bool inPlaceImported) {
        if (appName.trimmed().isEmpty()) {
          return QString();
        }

        QString safeIdPart = appName.trimmed();
        safeIdPart.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]")),
                           QStringLiteral("_"));
        const QString gameId = QStringLiteral("epic-") + safeIdPart;

        auto existing = m_db->getGameByEpicAppName(appName);
        GameRecord rec = existing.has_value() ? *existing : GameRecord{};
        if (rec.id.isEmpty()) {
          rec.id = gameId;
          rec.addedTimestamp = QDateTime::currentSecsSinceEpoch();
          rec.xboxEmulationState =
              m_settings ? (m_settings->xboxEmulationDefault() ? 1 : 0) : 0;
        }

        rec.source = QStringLiteral("epic");
        rec.platform = QStringLiteral("windows");
        rec.epicAppName = appName.trimmed();
        rec.epicNamespace = namespaceId.trimmed();
        rec.epicCatalogItemId = catalogItemId.trimmed();
        rec.epicBuildVersion = buildVersion.trimmed();
        rec.epicInstallDir = QDir::cleanPath(installDir.trimmed());
        rec.epicInPlaceImported = inPlaceImported;
        rec.title = title.trimmed().isEmpty() ? appName : title.trimmed();
        rec.executablePath = executablePath.trimmed();
        rec.workingDirectory = !rec.executablePath.isEmpty()
                                   ? QFileInfo(rec.executablePath).absolutePath()
                                   : rec.epicInstallDir;
        rec.launchArguments = launchArguments.trimmed();
        rec.runnerId = runnerId;

        if (prefixMode == QStringLiteral("dedicated")) {
          const QString pfxName =
              customPrefixName.trimmed().isEmpty()
                  ? m_prefixMgr->suggestShortPrefixName(rec.title)
                  : customPrefixName.trimmed();
          rec.prefixId = m_prefixMgr->createPrefix(
              pfxName, customPrefixLocation,
              prefixArch.isEmpty() ? QStringLiteral("win64") : prefixArch,
              QStringLiteral("win10"), runnerId, false);
        } else if (!prefixMode.isEmpty()) {
          rec.prefixId = prefixMode;
        } else {
          rec.prefixId = QStringLiteral("default-prefix");
        }

        const bool hasCover = !coverPath.isEmpty() && QFileInfo::exists(coverPath);
        const bool hasBanner =
            !bannerPath.isEmpty() && QFileInfo::exists(bannerPath);
        const bool hasLogo = !logoPath.isEmpty() && QFileInfo::exists(logoPath);

        rec.coverPath =
            hasCover
                ? coverPath
                : SteamGridDbService::generateFallbackPoster(rec.id, rec.title);
        rec.bannerPath =
            hasBanner
                ? bannerPath
                : SteamGridDbService::generateFallbackBanner(rec.id, rec.title);
        if (hasLogo) {
          rec.logoPath = logoPath;
        }

        m_db->saveGame(rec);
        m_model->reload();
        emit gamesChanged();
        emit gameAdded(rec.id, rec.title);
        emit gameOperationStatus(
            QStringLiteral("Installed '%1' to Library.").arg(rec.title), false);

        if (!hasCover || !hasBanner) {
          refreshArtworkFromSteamGridDb(rec.id);
        }
        return rec.id;
      }

      bool GameManager::updateGameDetails(const QString &gameId,
                                          const QVariantMap &updates) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return false;
        const GameRecord orig = *opt;
        GameRecord g = orig;

        auto cleanPath = [](const QString &p) {
          return p.startsWith(QStringLiteral("file://")) ? QUrl(p).toLocalFile()
                                                         : p.trimmed();
        };

        if (updates.contains(QStringLiteral("title")))
          g.title = updates.value(QStringLiteral("title")).toString().trimmed();
        if (updates.contains(QStringLiteral("executablePath")))
          g.executablePath = cleanPath(
              updates.value(QStringLiteral("executablePath")).toString());
        if (updates.contains(QStringLiteral("workingDirectory")))
          g.workingDirectory = cleanPath(
              updates.value(QStringLiteral("workingDirectory")).toString());
        if (updates.contains(QStringLiteral("launchArguments")))
          g.launchArguments = updates.value(QStringLiteral("launchArguments"))
                                  .toString()
                                  .trimmed();
        if (updates.contains(QStringLiteral("runnerId")))
          g.runnerId = updates.value(QStringLiteral("runnerId")).toString();
        if (updates.contains(QStringLiteral("prefixId")))
          g.prefixId = updates.value(QStringLiteral("prefixId")).toString();

        if (updates.contains(QStringLiteral("dxvkState")))
          g.dxvkState = updates.value(QStringLiteral("dxvkState")).toInt();
        if (updates.contains(QStringLiteral("vkd3dState")))
          g.vkd3dState = updates.value(QStringLiteral("vkd3dState")).toInt();
        if (updates.contains(QStringLiteral("esyncState")))
          g.esyncState = updates.value(QStringLiteral("esyncState")).toInt();
        if (updates.contains(QStringLiteral("fsyncState")))
          g.fsyncState = updates.value(QStringLiteral("fsyncState")).toInt();
        if (updates.contains(QStringLiteral("ntsyncState")))
          g.ntsyncState = updates.value(QStringLiteral("ntsyncState")).toInt();
        if (updates.contains(QStringLiteral("umuState")))
          g.umuState = updates.value(QStringLiteral("umuState")).toInt();
        if (updates.contains(QStringLiteral("umuGameId")))
          g.umuGameId = updates.value(QStringLiteral("umuGameId")).toString().trimmed();
        if (updates.contains(QStringLiteral("disableProtonfixes")))
          g.disableProtonfixes = updates.value(QStringLiteral("disableProtonfixes")).toBool();
        if (updates.contains(QStringLiteral("disableMonoGecko")))
          g.disableMonoGecko = updates.value(QStringLiteral("disableMonoGecko")).toBool();
        if (updates.contains(QStringLiteral("waylandDriverState")))
          g.waylandDriverState = updates.value(QStringLiteral("waylandDriverState")).toInt();
        if (updates.contains(QStringLiteral("hdrState")))
          g.hdrState = updates.value(QStringLiteral("hdrState")).toInt();
        if (updates.contains(QStringLiteral("nvapiState")))
          g.nvapiState = updates.value(QStringLiteral("nvapiState")).toInt();
        if (updates.contains(QStringLiteral("fsrState")))
          g.fsrState = updates.value(QStringLiteral("fsrState")).toInt();
        if (updates.contains(QStringLiteral("fsrStrength")))
          g.fsrStrength = qBound(0, updates.value(QStringLiteral("fsrStrength")).toInt(), 5);
        if (updates.contains(QStringLiteral("gpuSelection")))
          g.gpuSelection = updates.value(QStringLiteral("gpuSelection")).toString().trimmed();
        if (updates.contains(QStringLiteral("isHidden")))
          g.isHidden = updates.value(QStringLiteral("isHidden")).toBool();
        if (updates.contains(QStringLiteral("categories")))
          g.categories = updates.value(QStringLiteral("categories")).toStringList();
        if (updates.contains(QStringLiteral("epicCloudSavesEnabled")))
          g.epicCloudSavesEnabled = updates.value(QStringLiteral("epicCloudSavesEnabled")).toBool();
        if (updates.contains(QStringLiteral("epicAutoSyncCloudSaves")))
          g.epicAutoSyncCloudSaves = updates.value(QStringLiteral("epicAutoSyncCloudSaves")).toBool();
        if (updates.contains(QStringLiteral("epicCloudSaveFolder")))
          g.epicCloudSaveFolder = cleanPath(updates.value(QStringLiteral("epicCloudSaveFolder")).toString());
        if (updates.contains(QStringLiteral("epicSelectedInstallTags")))
          g.epicSelectedInstallTags = updates.value(QStringLiteral("epicSelectedInstallTags")).toStringList();
        if (updates.contains(QStringLiteral("epicSelectedDlcs")))
          g.epicSelectedDlcs = updates.value(QStringLiteral("epicSelectedDlcs")).toStringList();
        if (updates.contains(QStringLiteral("dxvkHud")))
          g.dxvkHud = updates.value(QStringLiteral("dxvkHud")).toString();
        if (updates.contains(QStringLiteral("virtualDesktop")))
          g.virtualDesktop =
              updates.value(QStringLiteral("virtualDesktop")).toBool();
        if (updates.contains(QStringLiteral("virtualDesktopResolution")))
          g.virtualDesktopResolution =
              updates.value(QStringLiteral("virtualDesktopResolution"))
                  .toString()
                  .trimmed();
        if (updates.contains(QStringLiteral("preLaunchScript")))
          g.preLaunchScript =
              updates.value(QStringLiteral("preLaunchScript")).toString();
        if (updates.contains(QStringLiteral("postExitScript")))
          g.postExitScript =
              updates.value(QStringLiteral("postExitScript")).toString();
        if (updates.contains(QStringLiteral("cpuAffinity")))
          g.cpuAffinity =
              updates.value(QStringLiteral("cpuAffinity")).toString().trimmed();
        if (updates.contains(QStringLiteral("processPriority")))
          g.processPriority =
              updates.value(QStringLiteral("processPriority")).toInt();
        if (updates.contains(QStringLiteral("mangohudState")))
          g.mangohudState =
              updates.value(QStringLiteral("mangohudState")).toInt();
        if (updates.contains(QStringLiteral("gamemodeState")))
          g.gamemodeState =
              updates.value(QStringLiteral("gamemodeState")).toInt();
        if (updates.contains(QStringLiteral("gamescopeState")))
          g.gamescopeState =
              updates.value(QStringLiteral("gamescopeState")).toInt();
        if (updates.contains(QStringLiteral("gamescope"))) {
          g.gamescope = GamescopeConfig::fromVariantMap(
              updates.value(QStringLiteral("gamescope")).toMap());
        }
        if (updates.contains(QStringLiteral("xboxEmulationState")))
          g.xboxEmulationState =
              updates.value(QStringLiteral("xboxEmulationState")).toInt();
        if (updates.contains(QStringLiteral("epicOfflineMode")))
          g.epicOfflineMode =
              updates.value(QStringLiteral("epicOfflineMode")).toBool();
        if (updates.contains(QStringLiteral("enableEosOverlay")))
          g.enableEosOverlay =
              updates.value(QStringLiteral("enableEosOverlay")).toBool();
        if (updates.contains(QStringLiteral("enableEacRuntime")))
          g.enableEacRuntime =
              updates.value(QStringLiteral("enableEacRuntime")).toBool();
        if (updates.contains(QStringLiteral("enableBattlEyeRuntime")))
          g.enableBattlEyeRuntime =
              updates.value(QStringLiteral("enableBattlEyeRuntime")).toBool();
        if (updates.contains(QStringLiteral("environmentVariables")))
          g.environmentVariables =
              updates.value(QStringLiteral("environmentVariables")).toMap();
        if (updates.contains(QStringLiteral("dllOverrides")))
          g.dllOverrides =
              updates.value(QStringLiteral("dllOverrides")).toMap();

        if (g.isNative()) {
          g.runnerId.clear();
          g.prefixId.clear();
        }

        if (g.title == orig.title && g.executablePath == orig.executablePath &&
            g.workingDirectory == orig.workingDirectory &&
            g.launchArguments == orig.launchArguments &&
            g.runnerId == orig.runnerId && g.prefixId == orig.prefixId &&
            g.dxvkState == orig.dxvkState && g.vkd3dState == orig.vkd3dState &&
            g.esyncState == orig.esyncState &&
            g.fsyncState == orig.fsyncState &&
            g.ntsyncState == orig.ntsyncState &&
            g.umuState == orig.umuState &&
            g.umuGameId == orig.umuGameId &&
            g.disableProtonfixes == orig.disableProtonfixes &&
            g.disableMonoGecko == orig.disableMonoGecko &&
            g.waylandDriverState == orig.waylandDriverState &&
            g.hdrState == orig.hdrState &&
            g.nvapiState == orig.nvapiState &&
            g.fsrState == orig.fsrState &&
            g.fsrStrength == orig.fsrStrength &&
            g.gpuSelection == orig.gpuSelection &&
            g.isHidden == orig.isHidden &&
            g.categories == orig.categories &&
            g.epicCloudSavesEnabled == orig.epicCloudSavesEnabled &&
            g.epicAutoSyncCloudSaves == orig.epicAutoSyncCloudSaves &&
            g.epicCloudSaveFolder == orig.epicCloudSaveFolder &&
            g.epicSelectedInstallTags == orig.epicSelectedInstallTags &&
            g.epicSelectedDlcs == orig.epicSelectedDlcs &&
            g.dxvkHud == orig.dxvkHud &&
            g.virtualDesktop == orig.virtualDesktop &&
            g.virtualDesktopResolution == orig.virtualDesktopResolution &&
            g.preLaunchScript == orig.preLaunchScript &&
            g.postExitScript == orig.postExitScript &&
            g.cpuAffinity == orig.cpuAffinity &&
            g.processPriority == orig.processPriority &&
            g.mangohudState == orig.mangohudState &&
            g.gamemodeState == orig.gamemodeState &&
            g.gamescopeState == orig.gamescopeState &&
            g.gamescope == orig.gamescope &&
            g.xboxEmulationState == orig.xboxEmulationState &&
            g.epicOfflineMode == orig.epicOfflineMode &&
            g.enableEosOverlay == orig.enableEosOverlay &&
            g.enableEacRuntime == orig.enableEacRuntime &&
            g.enableBattlEyeRuntime == orig.enableBattlEyeRuntime &&
            g.environmentVariables == orig.environmentVariables &&
            g.dllOverrides == orig.dllOverrides) {
          return true;
        }

        const bool titleChanged = (!g.title.isEmpty() && g.title != orig.title);
        if (titleChanged) {
          // Update fallback artwork immediately if using fallback SVGs
          if (g.coverPath.contains(QStringLiteral("fallback_cover.svg")) ||
              g.coverPath.isEmpty()) {
            g.coverPath =
                SteamGridDbService::generateFallbackPoster(g.id, g.title);
          }
          if (g.bannerPath.contains(QStringLiteral("fallback_banner.svg")) ||
              g.bannerPath.isEmpty()) {
            g.bannerPath =
                SteamGridDbService::generateFallbackBanner(g.id, g.title);
          }
        }

        const bool ok = m_db->saveGame(g);
        if (ok) {
          m_model->reload();
          emit gamesChanged();
          emit gameOperationStatus(
              QStringLiteral("Saved configuration for '%1'.").arg(g.title),
              false);

          // Automatically fetch new artwork from SteamGridDB/Steam Store when
          // game title is changed
          if (titleChanged) {
            refreshArtworkFromSteamGridDb(g.id);
          }
        }
        return ok;
      }

      bool GameManager::setGameArtwork(
          const QString &gameId, const QString &coverPath,
          const QString &bannerPath, const QString &logoPath,
          const QString &iconPath) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return false;
        GameRecord g = *opt;

        auto cleanPath = [](const QString &p) {
          return p.startsWith(QStringLiteral("file://")) ? QUrl(p).toLocalFile()
                                                         : p.trimmed();
        };

        if (!coverPath.isEmpty())
          g.coverPath = cleanPath(coverPath);
        if (!bannerPath.isEmpty())
          g.bannerPath = cleanPath(bannerPath);
        if (!logoPath.isEmpty())
          g.logoPath = cleanPath(logoPath);
        if (!iconPath.isEmpty())
          g.iconPath = cleanPath(iconPath);

        const bool ok = m_db->saveGame(g);
        if (ok) {
          m_model->reload();
          emit gamesChanged();
        }
        return ok;
      }

      void GameManager::setGameArtworkFromUrl(
          const QString &gameId, const QString &type, const QString &url) {
        const QString cleanUrl = url.trimmed();
        if (cleanUrl.isEmpty())
          return;

        QUrl qurl(cleanUrl);
        if (!qurl.isValid()) {
          emit gameOperationStatus(
              QStringLiteral("Invalid image link provided."), true);
          return;
        }

        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return;

        const QString artDir =
            AppSettings::artworkDir() + QStringLiteral("/") + gameId;
        QDir().mkpath(artDir);

        QString ext = QStringLiteral("jpg");
        const QString pathLower = qurl.path().toLower();
        if (pathLower.endsWith(QStringLiteral(".png")))
          ext = QStringLiteral("png");
        else if (pathLower.endsWith(QStringLiteral(".webp")))
          ext = QStringLiteral("webp");
        else if (pathLower.endsWith(QStringLiteral(".svg")))
          ext = QStringLiteral("svg");

        const QString destFile = artDir + QStringLiteral("/") + type +
                                 QStringLiteral("_link.") + ext;

        emit gameOperationStatus(
            QStringLiteral("Downloading %1 from link…").arg(type), false);

        m_sgdb->downloadImageToFile(
            qurl, destFile, [this, gameId, type, destFile](bool ok) {
              if (!ok) {
                emit gameOperationStatus(
                    QStringLiteral(
                        "Failed to download image from the provided link."),
                    true);
                return;
              }
              auto gOpt = m_db->getGame(gameId);
              if (!gOpt.has_value())
                return;
              GameRecord g = *gOpt;
              if (type == QStringLiteral("cover"))
                g.coverPath = destFile;
              else if (type == QStringLiteral("banner"))
                g.bannerPath = destFile;
              else if (type == QStringLiteral("logo"))
                g.logoPath = destFile;
              else if (type == QStringLiteral("icon"))
                g.iconPath = destFile;

              m_db->saveGame(g);
              m_model->reload();
              emit gamesChanged();
              emit gameOperationStatus(
                  QStringLiteral("Successfully updated %1.").arg(type), false);
            });
      }

      void GameManager::refreshArtworkFromSteamGridDb(const QString &gameId) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return;
        const QString title = opt->title;

        m_sgdb->fetchArtworkForGame(
            gameId, title,
            [this, gameId](const QString &cover, const QString &banner,
                           const QString &logo, const QString &icon,
                           const QString &year) {
              auto gOpt = m_db->getGame(gameId);
              if (!gOpt.has_value())
                return;
              GameRecord g = *gOpt;
              bool changed = false;
              if (!cover.isEmpty()) {
                g.coverPath = cover;
                changed = true;
              }
              if (!banner.isEmpty()) {
                g.bannerPath = banner;
                changed = true;
              }
              if (!logo.isEmpty()) {
                g.logoPath = logo;
                changed = true;
              }
              if (!icon.isEmpty()) {
                g.iconPath = icon;
                changed = true;
              }
              if (changed) {
                m_db->saveGame(g);
                m_model->reload();
                emit gamesChanged();
              }
            });
      }

      bool GameManager::removeGame(const QString &gameId,
                                   bool deleteDedicatedPrefix,
                                   bool deleteGameFiles) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return false;
        const GameRecord g = *opt;

        if (m_launchPipeline->isGameRunning(gameId)) {
          m_launchPipeline->stopGame(gameId);
        }

        if (deleteDedicatedPrefix && !g.isNative() && !g.prefixId.isEmpty() &&
            g.prefixId != QStringLiteral("default-prefix")) {
          m_prefixMgr->deletePrefix(g.prefixId, true);
        }

        bool deletedDiskFiles = false;
        if (deleteGameFiles && g.isEpic() && !g.epicInstallDir.isEmpty()) {
          const QString cleanDir = QDir::cleanPath(g.epicInstallDir);
          const QString homeClean = QDir::cleanPath(QDir::homePath());
          if (!cleanDir.isEmpty() && cleanDir != QStringLiteral("/") &&
              cleanDir != homeClean && QDir(cleanDir).exists()) {
            deletedDiskFiles = QDir(cleanDir).removeRecursively();
          }
        }

        const bool ok = m_db->removeGame(gameId);
        if (ok) {
          m_model->reload();
          emit gamesChanged();
          emit gameOperationStatus(
              deletedDiskFiles
                  ? QStringLiteral(
                        "Uninstalled '%1' and deleted game files from disk.")
                        .arg(g.title)
                  : QStringLiteral(
                        "Removed '%1' from library (game files preserved).")
                        .arg(g.title),
              false);
        }
        return ok;
      }

      void GameManager::togglePin(const QString &gameId) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return;
        GameRecord g = *opt;
        g.isPinned = !g.isPinned;
        m_db->saveGame(g);
        m_model->reload();
        emit gamesChanged();
      }

      void GameManager::toggleFavorite(const QString &gameId) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return;
        GameRecord g = *opt;
        g.isFavorite = !g.isFavorite;
        m_db->saveGame(g);
        m_model->reload();
        emit gamesChanged();
      }

      void GameManager::toggleHidden(const QString &gameId) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return;
        GameRecord g = *opt;
        g.isHidden = !g.isHidden;
        m_db->saveGame(g);
        m_model->reload();
        emit gamesChanged();
        emit gameOperationStatus(
            g.isHidden
                ? QStringLiteral("Hidden '%1' from main library.").arg(g.title)
                : QStringLiteral("Restored '%1' to library.").arg(g.title),
            false);
      }

      bool GameManager::createCollection(const QString &name) {
        const bool ok = m_db && m_db->createCollection(name);
        if (ok) {
          emit gamesChanged();
          emit gameOperationStatus(
              QStringLiteral("Created collection '%1'.").arg(name.trimmed()), false);
        }
        return ok;
      }

      bool GameManager::renameCollection(const QString &oldName, const QString &newName) {
        const bool ok = m_db && m_db->renameCollection(oldName, newName);
        if (ok) {
          if (m_model && m_model->categoryFilter() == oldName.trimmed()) {
            m_model->setCategoryFilter(newName.trimmed());
          } else if (m_model) {
            m_model->reload();
          }
          emit gamesChanged();
        }
        return ok;
      }

      bool GameManager::deleteCollection(const QString &name) {
        const bool ok = m_db && m_db->deleteCollection(name);
        if (ok) {
          if (m_model && m_model->categoryFilter() == name.trimmed()) {
            m_model->setCategoryFilter(QString());
          } else if (m_model) {
            m_model->reload();
          }
          emit gamesChanged();
        }
        return ok;
      }

      bool GameManager::setGameCategories(const QString &gameId, const QStringList &categories) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value()) return false;
        GameRecord g = *opt;
        QStringList clean;
        for (const QString &c : categories) {
          const QString t = c.trimmed();
          if (!t.isEmpty() && !clean.contains(t, Qt::CaseInsensitive)) {
            clean.append(t);
            m_db->createCollection(t);
          }
        }
        g.categories = clean;
        const bool ok = m_db->saveGame(g);
        if (ok) {
          m_model->reload();
          emit gamesChanged();
        }
        return ok;
      }

      bool GameManager::addGameToCollection(const QString &gameId, const QString &collectionName) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value() || collectionName.trimmed().isEmpty()) return false;
        QStringList cats = opt->categories;
        const QString clean = collectionName.trimmed();
        if (!cats.contains(clean, Qt::CaseInsensitive)) {
          cats.append(clean);
        }
        return setGameCategories(gameId, cats);
      }

      bool GameManager::removeGameFromCollection(const QString &gameId, const QString &collectionName) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value()) return false;
        QStringList cats;
        for (const QString &c : opt->categories) {
          if (c.compare(collectionName.trimmed(), Qt::CaseInsensitive) != 0) {
            cats.append(c);
          }
        }
        return setGameCategories(gameId, cats);
      }

      void GameManager::relocateGame(const QString &gameId, const QString &targetParentDir) {
        if (m_isRelocating) {
          emit gameOperationStatus(QStringLiteral("Another game relocation is already in progress."), true);
          return;
        }
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value()) return;
        const GameRecord g = *opt;
        if (m_launchPipeline && m_launchPipeline->isGameRunning(gameId)) {
          emit gameOperationStatus(QStringLiteral("Stop '%1' before moving its files.").arg(g.title), true);
          return;
        }

        QString cleanParent = targetParentDir.trimmed();
        if (cleanParent.startsWith(QStringLiteral("file://"))) {
          cleanParent = QUrl(cleanParent).toLocalFile();
        }
        cleanParent = QDir::cleanPath(cleanParent);
        if (cleanParent.isEmpty()) return;

        QString srcDir;
        if (!g.epicInstallDir.isEmpty()) {
          srcDir = QDir::cleanPath(g.epicInstallDir);
        } else {
          const QString exeDir = QDir::cleanPath(QFileInfo(g.executablePath).absolutePath());
          const QString workDir = QDir::cleanPath(g.workingDirectory);
          const QString homeClean = QDir::cleanPath(QDir::homePath());
          if (!workDir.isEmpty() && workDir != QStringLiteral("/") && workDir != homeClean &&
              (exeDir == workDir || exeDir.startsWith(workDir + QLatin1Char('/')))) {
            srcDir = workDir;
          } else {
            srcDir = exeDir;
          }
        }
        if (srcDir.isEmpty() || !QDir(srcDir).exists()) {
          emit gameOperationStatus(QStringLiteral("Source game folder does not exist."), true);
          emit gameRelocationFinished(gameId, false, QString());
          return;
        }

        const QString folderName = QFileInfo(srcDir).fileName();
        const QString dstDir = QDir::cleanPath(QDir(cleanParent).filePath(folderName));
        if (dstDir == srcDir || dstDir.startsWith(srcDir + QLatin1Char('/'))) {
          emit gameOperationStatus(QStringLiteral("Choose a different destination folder."), true);
          emit gameRelocationFinished(gameId, false, QString());
          return;
        }
        if (QFileInfo::exists(dstDir)) {
          emit gameOperationStatus(QStringLiteral("Destination folder already exists: %1").arg(dstDir), true);
          emit gameRelocationFinished(gameId, false, QString());
          return;
        }

        m_isRelocating = true;
        m_relocationProgress = 0.0;
        emit relocatingChanged();
        emit gameOperationStatus(QStringLiteral("Moving '%1' to %2…").arg(g.title, dstDir), false);

        QPointer<GameManager> self(this);
        QThreadPool::globalInstance()->start([self, gameId, g, srcDir, dstDir, cleanParent]() {
          QDir().mkpath(cleanParent);
          bool ok = false;
          QString errMsg;

          const QStorageInfo srcVol(srcDir);
          const QStorageInfo dstVol(cleanParent);
          const bool sameFs = srcVol.isValid() && dstVol.isValid() &&
                              !srcVol.device().isEmpty() && srcVol.device() == dstVol.device();

          if (sameFs && QDir().rename(srcDir, dstDir)) {
            ok = true;
          } else {
            // Cross-filesystem streamed copy + cleanup
            qint64 totalBytes = 0;
            struct FileItem { QString rel; QString abs; qint64 size; QFileDevice::Permissions perms; bool isLink; QString linkTarget; };
            QList<FileItem> items;
            QDirIterator it(srcDir, QDir::Files | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
            while (it.hasNext()) {
              it.next();
              const QFileInfo fi = it.fileInfo();
              FileItem item;
              item.abs = fi.absoluteFilePath();
              item.rel = QDir(srcDir).relativeFilePath(item.abs);
              item.isLink = fi.isSymLink();
              item.linkTarget = item.isLink ? fi.symLinkTarget() : QString();
              item.size = item.isLink ? 0 : fi.size();
              item.perms = fi.permissions();
              totalBytes += item.size;
              items.append(item);
            }

            const qint64 freeBytes = QStorageInfo(cleanParent).bytesAvailable();
            if (freeBytes >= 0 && totalBytes > freeBytes) {
              errMsg = QStringLiteral("Insufficient free space on destination drive.");
            } else if (!QDir().mkpath(dstDir)) {
              errMsg = QStringLiteral("Failed to create destination folder.");
            } else {
              qint64 copied = 0;
              QByteArray buf(1024 * 1024, '\0');
              ok = true;
              for (const FileItem &item : items) {
                const QString dstFile = QDir(dstDir).filePath(item.rel);
                QDir().mkpath(QFileInfo(dstFile).absolutePath());
                if (item.isLink) {
                  QFile::remove(dstFile);
                  QFile::link(item.linkTarget, dstFile);
                  continue;
                }
                QFile sf(item.abs);
                QFile df(dstFile);
                if (!sf.open(QIODevice::ReadOnly) || !df.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                  ok = false;
                  errMsg = QStringLiteral("I/O error while moving %1").arg(item.rel);
                  break;
                }
                while (!sf.atEnd()) {
                  const qint64 n = sf.read(buf.data(), buf.size());
                  if (n <= 0) break;
                  if (df.write(buf.constData(), n) != n) {
                    ok = false;
                    errMsg = QStringLiteral("Write error while moving %1").arg(item.rel);
                    break;
                  }
                  copied += n;
                }
                sf.close();
                df.close();
                if (!ok) break;
                QFile::setPermissions(dstFile, item.perms);
                const double pct = totalBytes > 0 ? (100.0 * static_cast<double>(copied) / static_cast<double>(totalBytes)) : 100.0;
                if (self) {
                  QMetaObject::invokeMethod(self, [self, pct]() {
                    if (!self) return;
                    self->m_relocationProgress = pct;
                    emit self->relocatingChanged();
                  }, Qt::QueuedConnection);
                }
              }
              if (ok) {
                const QString homeClean = QDir::cleanPath(QDir::homePath());
                if (srcDir != QStringLiteral("/") && srcDir != homeClean) {
                  QDir(srcDir).removeRecursively();
                }
              } else {
                QDir(dstDir).removeRecursively();
              }
            }
          }

          if (self) {
            QMetaObject::invokeMethod(self, [self, gameId, srcDir, dstDir, ok, errMsg]() {
              if (!self) return;
              self->m_isRelocating = false;
              self->m_relocationProgress = ok ? 100.0 : 0.0;
              emit self->relocatingChanged();

              if (ok) {
                if (auto fresh = self->m_db->getGame(gameId); fresh.has_value()) {
                  GameRecord upd = *fresh;
                  auto remap = [&srcDir, &dstDir](const QString &p) {
                    const QString clean = QDir::cleanPath(p);
                    if (clean == srcDir) return dstDir;
                    if (clean.startsWith(srcDir + QLatin1Char('/'))) {
                      return dstDir + clean.mid(srcDir.length());
                    }
                    return p;
                  };
                  upd.executablePath = remap(upd.executablePath);
                  upd.workingDirectory = remap(upd.workingDirectory);
                  if (!upd.epicInstallDir.isEmpty()) {
                    upd.epicInstallDir = dstDir;
                  }
                  self->m_db->saveGame(upd);
                  self->m_model->reload();
                  emit self->gamesChanged();
                  emit self->gameOperationStatus(QStringLiteral("Moved '%1' to %2.").arg(upd.title, dstDir), false);
                }
              } else {
                emit self->gameOperationStatus(
                    errMsg.isEmpty() ? QStringLiteral("Failed to move game folder.") : errMsg, true);
              }
              emit self->gameRelocationFinished(gameId, ok, ok ? dstDir : QString());
            }, Qt::QueuedConnection);
          }
        });
      }

      void GameManager::syncXboxEmulationToAllGames(bool enabled) {
        if (m_db) {
          m_db->setAllGamesXboxEmulationState(enabled);
        }
        if (m_model) {
          m_model->reload();
        }
        emit gamesChanged();
      }

      QVariantMap GameManager::getGameMap(const QString &gameId) const {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return QVariantMap();
        const bool hasUpd = (opt->isEpic() && m_epicService && m_epicService->hasUpdate(opt->epicAppName));
        return opt->toVariantMap(m_launchPipeline->isGameRunning(gameId),
                                 opt->isNative() ? QStringLiteral("LINUX") : m_runnerMgr->runnerTagForId(opt->runnerId),
                                 hasUpd);
      }

      bool GameManager::createDesktopShortcut(const QString &gameId,
                                              bool alsoOnDesktop) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return false;
        const GameRecord g = *opt;

        // Prefer APPIMAGE env var inside AppImages because applicationFilePath() points to an ephemeral /tmp/.mount_* path
        QString appBin;
        const QString appImagePath = qEnvironmentVariable("APPIMAGE").trimmed();
        if (!appImagePath.isEmpty() && QFileInfo::exists(appImagePath)) {
          appBin = QFileInfo(appImagePath).absoluteFilePath();
        } else {
          appBin = QCoreApplication::applicationFilePath();
        }
        if (appBin.isEmpty())
          appBin = QStringLiteral("tsuki");

        // Escape Desktop Entry Exec double-quoted special characters (\, ", $, `)
        auto escapeDesktopArg = [](QString s) {
          s.replace(QLatin1Char('\\'), QStringLiteral("\\\\"));
          s.replace(QLatin1Char('"'), QStringLiteral("\\\""));
          s.replace(QLatin1Char('$'), QStringLiteral("\\$"));
          s.replace(QLatin1Char('`'), QStringLiteral("\\`"));
          return s;
        };

        const QString iconPath =
            !g.iconPath.isEmpty()
                ? g.iconPath
                : (!g.coverPath.isEmpty()
                       ? g.coverPath
                       : QStringLiteral("applications-games"));

        const QString desktopContent =
            QStringLiteral("[Desktop Entry]\n"
                           "Type=Application\n"
                           "Name=%1\n"
                           "Comment=Launch %1 via Tsuki Game Launcher\n"
                           "Exec=\"%2\" --launch \"%3\"\n"
                           "Path=%4\n"
                           "Icon=%5\n"
                           "Terminal=false\n"
                           "Categories=Game;\n"
                           "StartupNotify=true\n")
                .arg(g.title, escapeDesktopArg(appBin), escapeDesktopArg(g.id), g.workingDirectory, iconPath);

        QString safeFile = g.title;
        safeFile.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]")),
                         QStringLiteral("_"));
        const QString fileName =
            QStringLiteral("tsuki-%1.desktop").arg(safeFile.toLower());

        const QString appsDir = QStandardPaths::writableLocation(
            QStandardPaths::ApplicationsLocation);
        QDir().mkpath(appsDir);
        const QString appEntryPath = appsDir + QStringLiteral("/") + fileName;

        QFile f1(appEntryPath);
        bool ok = false;
        if (f1.open(QIODevice::WriteOnly | QIODevice::Truncate |
                    QIODevice::Text)) {
          f1.write(desktopContent.toUtf8());
          f1.close();
          f1.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                            QFileDevice::ExeOwner | QFileDevice::ReadGroup |
                            QFileDevice::ExeGroup | QFileDevice::ReadOther |
                            QFileDevice::ExeOther);
          ok = true;
        }

        if (alsoOnDesktop) {
          const QString desktopDir =
              QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
          if (!desktopDir.isEmpty() && QDir(desktopDir).exists()) {
            const QString deskFilePath =
                desktopDir + QStringLiteral("/") + fileName;
            QFile f2(deskFilePath);
            if (f2.open(QIODevice::WriteOnly | QIODevice::Truncate |
                        QIODevice::Text)) {
              f2.write(desktopContent.toUtf8());
              f2.close();
              f2.setPermissions(QFileDevice::ReadOwner |
                                QFileDevice::WriteOwner |
                                QFileDevice::ExeOwner | QFileDevice::ReadGroup |
                                QFileDevice::ExeGroup | QFileDevice::ReadOther |
                                QFileDevice::ExeOther);
            }
          }
        }

        emit gameOperationStatus(
            ok ? QStringLiteral("Created desktop shortcut for '%1'.")
                     .arg(g.title)
               : QStringLiteral("Failed to write desktop shortcut."),
            !ok);
        return ok;
      }

      void GameManager::openGameDirectory(const QString &gameId) {
        auto opt = m_db->getGame(gameId);
        if (!opt.has_value())
          return;
        const QString dir = opt->workingDirectory.isEmpty()
                                ? QFileInfo(opt->executablePath).absolutePath()
                                : opt->workingDirectory;
        QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
      }

    } // namespace Tsuki
