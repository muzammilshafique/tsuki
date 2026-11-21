#include "EpicService.h"
#include "../core/SecretStore.h"
#include "DownloadManager.h"
#include "GameManager.h"
#include "UmuIdResolver.h"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutexLocker>
#include <QNetworkRequest>
#include <QPointer>
#include <QProcess>
#include <QRegularExpression>
#include <QStorageInfo>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#include <QtConcurrent>
#include <algorithm>
#include <numeric>

namespace Tsuki {

namespace {

constexpr const char* kEpicClientId = "34a02cf8f4414e29b15921876da36f9a";
constexpr const char* kEpicClientSecret = "daafbccc737745039dffe53d94fc76cf";
constexpr const char* kEpicLauncherUserAgent =
    "UELauncher/16.12.1-33490172+++Portal+Release-Live Windows/10.0.19041.1.256.64bit";
constexpr const char* kEosOverlayAppName = "98bc04bc842e4906993fd6d6644ffb8d";
constexpr const char* kEosOverlayNamespace = "302e5ede476149b1bc3e4fe6ae45e50e";
constexpr const char* kEosOverlayCatalogId = "cc15684f44d849e89e9bf4cec0508b68";
constexpr int kMaxConcurrentChunks = 6;
constexpr int kMaxChunkRetries = 3;
constexpr int kMaxConcurrentArtwork = 6;

QByteArray basicAuthHeader() {
    const QByteArray creds = QByteArray(kEpicClientId) + ":" + QByteArray(kEpicClientSecret);
    return QByteArray("Basic ") + creds.toBase64();
}

QByteArray safeReadReply(QNetworkReply* reply) {
    if (!reply || !reply->isOpen() || !reply->isReadable()) {
        return QByteArray();
    }
    return reply->readAll();
}

qint64 parseIsoUtcEpoch(const QString& iso) {
    if (iso.isEmpty()) return 0;
    const QDateTime dt = QDateTime::fromString(iso, Qt::ISODateWithMs);
    if (dt.isValid()) return dt.toSecsSinceEpoch();
    const QDateTime dt2 = QDateTime::fromString(iso, Qt::ISODate);
    return dt2.isValid() ? dt2.toSecsSinceEpoch() : 0;
}

bool isCatalogItemPlayableGame(const QJsonObject& itemObj, const QString& appName) {
    if (appName.trimmed().isEmpty()) return false;
    if (itemObj.contains(QStringLiteral("mainGameItem")) && itemObj.value(QStringLiteral("mainGameItem")).isObject()) {
        return false;
    }
    const QString title = itemObj.value(QStringLiteral("title")).toString();
    const QString ns = itemObj.value(QStringLiteral("namespace")).toString();
    if (EpicService::isBlockedNonGameEpicApp(title, appName, ns)) {
        return false;
    }
    const QJsonArray cats = itemObj.value(QStringLiteral("categories")).toArray();
    bool hasGame = false;
    bool isEngineOrAddonOrSoftware = false;
    for (const QJsonValue& cv : cats) {
        const QString path = cv.toObject().value(QStringLiteral("path")).toString().toLower();
        if (path == QLatin1String("games") ||
            path == QLatin1String("games/edition/base")) {
            hasGame = true;
        } else if (path == QLatin1String("engines") ||
                   path == QLatin1String("plugins") ||
                   path == QLatin1String("addons") ||
                   path == QLatin1String("digitalextras") ||
                   path == QLatin1String("dlc") ||
                   path == QLatin1String("software") ||
                   path == QLatin1String("applications") ||
                   path.startsWith(QLatin1String("software/")) ||
                   path.startsWith(QLatin1String("applications/")) ||
                   path == QLatin1String("tools") ||
                   path == QLatin1String("mods") ||
                   path == QLatin1String("editors")) {
            isEngineOrAddonOrSoftware = true;
        }
    }
    if (hasGame) return true;
    if (isEngineOrAddonOrSoftware) return false;
    // Some legacy catalog records omit categories; allow if not UE
    return ns != QLatin1String("ue");
}

void extractKeyImages(const QJsonObject& itemObj,
                      QString& outCoverUrl,
                      QString& outBannerUrl,
                      QString& outLogoUrl) {
    const QJsonArray imgs = itemObj.value(QStringLiteral("keyImages")).toArray();
    auto scoreCover = [](const QString& t) {
        if (t == QLatin1String("DieselGameBoxTall")) return 100;
        if (t == QLatin1String("OfferImageTall")) return 90;
        if (t == QLatin1String("DieselStoreFrontTall")) return 80;
        if (t == QLatin1String("Thumbnail")) return 60;
        return 0;
    };
    auto scoreBanner = [](const QString& t) {
        if (t == QLatin1String("DieselGameBox")) return 100;
        if (t == QLatin1String("OfferImageWide")) return 90;
        if (t == QLatin1String("DieselStoreFrontWide")) return 80;
        if (t == QLatin1String("DieselGameBoxWide")) return 75;
        return 0;
    };

    int bestCover = 0;
    int bestBanner = 0;
    for (const QJsonValue& iv : imgs) {
        const QJsonObject io = iv.toObject();
        const QString type = io.value(QStringLiteral("type")).toString();
        const QString url = io.value(QStringLiteral("url")).toString().trimmed();
        if (url.isEmpty()) continue;

        const int cs = scoreCover(type);
        if (cs > bestCover) {
            bestCover = cs;
            outCoverUrl = url;
        }
        const int bs = scoreBanner(type);
        if (bs > bestBanner) {
            bestBanner = bs;
            outBannerUrl = url;
        }
        if (type == QLatin1String("DieselGameBoxLogo") && outLogoUrl.isEmpty()) {
            outLogoUrl = url;
        }
    }
    if (outCoverUrl.isEmpty()) outCoverUrl = outBannerUrl;
    if (outBannerUrl.isEmpty()) outBannerUrl = outCoverUrl;
}

QString normalizeLocalPath(const QString& raw) {
    QString p = raw.trimmed();
    if (p.startsWith(QStringLiteral("file://"))) {
        p = QUrl(p).toLocalFile();
    }
    return p.isEmpty() ? QString() : QDir::cleanPath(p);
}

QStringList collectCandidateExecutables(const QString& dirPath) {
    QStringList allExes;
    if (dirPath.isEmpty() || !QDir(dirPath).exists()) return allExes;

    const QString cleanBase = QDir::cleanPath(dirPath);
    QList<QPair<int, qint64>> meta;
    QStringList paths;

    QDirIterator it(cleanBase, {QStringLiteral("*.exe")}, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString fullPath = it.next();
        const QFileInfo fi(fullPath);
        const QString lower = fi.fileName().toLower();
        if (lower.startsWith(QStringLiteral("unins")) ||
            lower.contains(QStringLiteral("crashreport")) ||
            lower.contains(QStringLiteral("redist")) ||
            lower.contains(QStringLiteral("dxsetup")) ||
            lower.contains(QStringLiteral("ue4prereq")) ||
            lower.contains(QStringLiteral("ueprereq")) ||
            lower.contains(QStringLiteral("easyanticheat_setup")) ||
            lower.contains(QStringLiteral("battleye"))) {
            continue;
        }
        const QString rel = QDir(cleanBase).relativeFilePath(fullPath);
        const int depth = rel.count(QLatin1Char('/'));
        paths.append(fullPath);
        meta.append({depth, fi.size()});
    }

    QList<int> order(paths.size());
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        const bool aShip = paths.at(a).contains(QStringLiteral("Shipping"), Qt::CaseInsensitive);
        const bool bShip = paths.at(b).contains(QStringLiteral("Shipping"), Qt::CaseInsensitive);
        if (aShip != bShip) return aShip > bShip;
        if (meta.at(a).first != meta.at(b).first) return meta.at(a).first < meta.at(b).first;
        return meta.at(a).second > meta.at(b).second;
    });

    for (int idx : order) {
        allExes.append(paths.at(idx));
    }
    return allExes;
}

QString resolveImportedExecutable(const QString& installDir,
                                    const QString& manifestLaunchExe,
                                    const QString& explicitExe,
                                    const QString& sourceDir) {
    const QString cleanDest = QDir::cleanPath(installDir);
    const QString cleanSrc = QDir::cleanPath(sourceDir);

    if (!explicitExe.trimmed().isEmpty()) {
        QString cand = normalizeLocalPath(explicitExe);
        if (!cleanSrc.isEmpty() && cleanDest != cleanSrc &&
            cand.startsWith(cleanSrc + QLatin1Char('/'))) {
            const QString rel = QDir(cleanSrc).relativeFilePath(cand);
            cand = QDir(cleanDest).filePath(rel);
        } else if (QFileInfo(cand).isRelative()) {
            cand = QDir(cleanDest).filePath(cand);
        }
        if (QFileInfo::exists(cand)) {
            return QFileInfo(cand).absoluteFilePath();
        }
    }

    if (!manifestLaunchExe.isEmpty()) {
        const QString resolved = EpicService::resolveExistingRelativePath(cleanDest, manifestLaunchExe);
        if (!resolved.isEmpty() && QFileInfo::exists(resolved)) {
            return resolved;
        }
    }

    const QStringList candidates = collectCandidateExecutables(cleanDest);
    if (!candidates.isEmpty()) {
        return candidates.first();
    }

    QDirIterator fallbackIt(cleanDest, {QStringLiteral("*.exe")}, QDir::Files, QDirIterator::Subdirectories);
    return fallbackIt.hasNext() ? fallbackIt.next() : QString();
}

} // namespace

// ─────────────────────────────────────────────────────────────────────────────
// EpicLibraryModel
// ─────────────────────────────────────────────────────────────────────────────

EpicLibraryModel::EpicLibraryModel(EpicService* service, DatabaseManager* db, QObject* parent)
    : QAbstractListModel(parent)
    , m_service(service)
    , m_db(db)
{
    connect(m_service, &EpicService::libraryUpdated, this, &EpicLibraryModel::reload);
    connect(m_service, &EpicService::updatesChanged, this, &EpicLibraryModel::reload);
    connect(m_service, &EpicService::downloadStateChanged, this, &EpicLibraryModel::notifyAppChanged);
    connect(m_service, &EpicService::downloadFinished, this, [this](const QString&, const QString&) {
        reload();
    });
    reload();
}

int EpicLibraryModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return m_visibleItems.size();
}

QHash<int, QByteArray> EpicLibraryModel::roleNames() const {
    return {
        {AppNameRole, "appName"},
        {NamespaceRole, "namespaceId"},
        {CatalogItemIdRole, "catalogItemId"},
        {TitleRole, "title"},
        {DeveloperRole, "developer"},
        {DescriptionRole, "description"},
        {CoverPathRole, "coverPath"},
        {BannerPathRole, "bannerPath"},
        {LogoPathRole, "logoPath"},
        {DownloadSizeRole, "downloadSize"},
        {InstallSizeRole, "installSize"},
        {DownloadSizeFormattedRole, "downloadSizeFormatted"},
        {InstallSizeFormattedRole, "installSizeFormatted"},
        {BuildVersionRole, "buildVersion"},
        {IsInstalledRole, "isInstalled"},
        {InstalledGameIdRole, "installedGameId"},
        {HasUpdateRole, "hasUpdate"},
        {IsHiddenRole, "isHidden"},
        {IsDownloadingRole, "isDownloading"},
        {IsPausedRole, "isPaused"},
        {IsQueuedRole, "isQueued"},
        {DownloadProgressRole, "downloadProgress"},
        {DownloadSpeedTextRole, "downloadSpeedText"},
        {DownloadEtaRole, "downloadEta"},
        {DownloadStageRole, "downloadStage"}
    };
}

QVariant EpicLibraryModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_visibleItems.size()) {
        return QVariant();
    }
    const EpicLibraryItem& item = m_visibleItems.at(index.row());
    const QString gameId = m_installedGameIdsByApp.value(item.appName);
    const bool installed = !gameId.isEmpty();
    const QVariantMap dl = m_service ? m_service->getDownloadState(item.appName) : QVariantMap();

    switch (role) {
    case AppNameRole:
        return item.appName;
    case NamespaceRole:
        return item.namespaceId;
    case CatalogItemIdRole:
        return item.catalogItemId;
    case TitleRole:
        return item.title;
    case DeveloperRole:
        return item.developer;
    case DescriptionRole:
        return item.description;
    case CoverPathRole:
        return QUrl(GameRecord::toFileUrlOrOriginal(!item.coverPath.isEmpty() ? item.coverPath : item.coverUrl));
    case BannerPathRole:
        return QUrl(GameRecord::toFileUrlOrOriginal(!item.bannerPath.isEmpty() ? item.bannerPath : item.bannerUrl));
    case LogoPathRole:
        return QUrl(GameRecord::toFileUrlOrOriginal(!item.logoPath.isEmpty() ? item.logoPath : item.logoUrl));
    case DownloadSizeRole:
        return item.downloadSize;
    case InstallSizeRole:
        return item.installSize;
    case DownloadSizeFormattedRole:
        return EpicLibraryItem::formatSize(item.downloadSize);
    case InstallSizeFormattedRole:
        return EpicLibraryItem::formatSize(item.installSize);
    case BuildVersionRole:
        return item.buildVersion;
    case IsInstalledRole:
        return installed;
    case InstalledGameIdRole:
        return gameId;
    case HasUpdateRole:
        return m_service ? m_service->hasUpdate(item.appName) : false;
    case IsHiddenRole:
        return item.isHidden;
    case IsDownloadingRole:
        return dl.value(QStringLiteral("isDownloading"), false).toBool();
    case IsPausedRole:
        return dl.value(QStringLiteral("isPaused"), false).toBool();
    case IsQueuedRole:
        return dl.value(QStringLiteral("isQueued"), false).toBool();
    case DownloadProgressRole:
        return dl.value(QStringLiteral("progress"), 0.0).toDouble();
    case DownloadSpeedTextRole:
        return dl.value(QStringLiteral("speedText"), QString()).toString();
    case DownloadEtaRole:
        return dl.value(QStringLiteral("eta"), QString()).toString();
    case DownloadStageRole:
        return dl.value(QStringLiteral("stage"), QString()).toString();
    default:
        return QVariant();
    }
}

void EpicLibraryModel::setSearchQuery(const QString& query) {
    const QString trimmed = query.trimmed();
    if (m_searchQuery == trimmed) return;
    m_searchQuery = trimmed;
    emit searchQueryChanged();
    reload();
}

void EpicLibraryModel::setSortMode(int mode) {
    if (m_sortMode == mode) return;
    m_sortMode = mode;
    emit sortModeChanged();
    reload();
}

void EpicLibraryModel::setShowHidden(bool show) {
    if (m_showHidden == show) return;
    m_showHidden = show;
    emit showHiddenChanged();
    reload();
}

QVariantMap EpicLibraryModel::get(int row) const {
    if (row < 0 || row >= m_visibleItems.size()) return QVariantMap();
    const EpicLibraryItem& item = m_visibleItems.at(row);
    const QString gameId = m_installedGameIdsByApp.value(item.appName);
    QVariantMap m = item.toVariantMap(!gameId.isEmpty(), gameId);
    if (m_service) {
        const QVariantMap dl = m_service->getDownloadState(item.appName);
        for (auto it = dl.constBegin(); it != dl.constEnd(); ++it) {
            m.insert(it.key(), it.value());
        }
    }
    return m;
}

void EpicLibraryModel::notifyAppChanged(const QString& appName) {
    for (int i = 0; i < m_visibleItems.size(); ++i) {
        if (m_visibleItems.at(i).appName == appName) {
            // Update local artwork / size fields from DB in case artwork or install info finished
            if (auto fresh = m_db->getEpicLibraryItem(appName); fresh.has_value()) {
                m_visibleItems[i] = *fresh;
            }
            const QModelIndex idx = createIndex(i, 0);
            emit dataChanged(idx, idx);
            break;
        }
    }
}

void EpicLibraryModel::reload() {
    beginResetModel();
    m_visibleItems.clear();
    m_installedGameIdsByApp.clear();

    const QList<GameRecord> games = m_db->getAllGames();
    for (const GameRecord& g : games) {
        if (g.isEpic()) {
            m_installedGameIdsByApp.insert(g.epicAppName, g.id);
        }
    }

    const QList<EpicLibraryItem> all = m_db->getAllEpicLibraryItems();
    const QString q = m_searchQuery.toLower();
    m_hiddenCount = 0;
    for (const EpicLibraryItem& item : all) {
        // Hard-filter non-game bloatware (Discord, Spotify, browsers, engines, tools, etc.)
        if (EpicService::isBlockedNonGameEpicApp(item.title, item.appName, item.namespaceId)) {
            continue;
        }
        if (item.isHidden) {
            ++m_hiddenCount;
            if (!m_showHidden) continue;
        }
        if (!q.isEmpty() && !item.title.toLower().contains(q) &&
            !item.developer.toLower().contains(q) &&
            !item.appName.toLower().contains(q)) {
            continue;
        }
        m_visibleItems.append(item);
    }

    std::sort(m_visibleItems.begin(), m_visibleItems.end(),
              [this](const EpicLibraryItem& a, const EpicLibraryItem& b) {
                  const bool aDl = m_service && m_service->getDownloadState(a.appName).value(QStringLiteral("isDownloading")).toBool();
                  const bool bDl = m_service && m_service->getDownloadState(b.appName).value(QStringLiteral("isDownloading")).toBool();
                  if (aDl != bDl) return aDl > bDl;

                  if (m_sortMode == 1) { // Installed First
                      const bool aInst = m_installedGameIdsByApp.contains(a.appName);
                      const bool bInst = m_installedGameIdsByApp.contains(b.appName);
                      if (aInst != bInst) return aInst > bInst;
                  } else if (m_sortMode == 2) { // Title Z -> A
                      return a.title.compare(b.title, Qt::CaseInsensitive) > 0;
                  }
                  return a.title.compare(b.title, Qt::CaseInsensitive) < 0;
              });

    endResetModel();
    emit countChanged();
}

// ─────────────────────────────────────────────────────────────────────────────
// EpicService
// ─────────────────────────────────────────────────────────────────────────────

EpicService::EpicService(DatabaseManager* db,
                         AppSettings* settings,
                         RunnerManager* runnerMgr,
                         PrefixManager* prefixMgr,
                         SteamGridDbService* sgdb,
                         QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_runnerMgr(runnerMgr)
    , m_prefixMgr(prefixMgr)
    , m_sgdb(sgdb)
{
    loadAuthSession();
    // Construct model only after m_downloads and auth state are initialized,
    // because EpicLibraryModel::reload() queries getDownloadState().
    m_model = new EpicLibraryModel(this, db, this);
}

EpicService::~EpicService() {
    const QList<QString> keys = m_downloads.keys();
    for (const QString& appName : keys) {
        auto s = m_downloads.value(appName);
        if (s) {
            const bool shouldPersist = !s->isCancelled && !s->verifyOnly && !s->isImporting && !s->isEosOverlay;
            s->isCancelled = true;
            for (QNetworkReply* r : s->activeReplies) {
                if (r) {
                    r->disconnect(this);
                    r->abort();
                    r->deleteLater();
                }
            }
            s->activeReplies.clear();
            saveResumeState(s);
            if (shouldPersist) {
                s->isPaused = true;
                persistDownloadQueueItem(s);
            }
        }
    }
    m_downloads.clear();
}

bool EpicService::isBlockedNonGameEpicApp(const QString& title,
                                          const QString& appName,
                                          const QString& namespaceId) {
    if (namespaceId.compare(QStringLiteral("ue"), Qt::CaseInsensitive) == 0) {
        return true;
    }
    const QString t = title.trimmed().toLower();
    const QString a = appName.trimmed().toLower();

    // Exact or well-known non-game apps / launchers / utilities distributed on Epic Games Store
    static const QStringList kExactBlockedTitles = {
        QStringLiteral("discord"),
        QStringLiteral("spotify"),
        QStringLiteral("itch.io"),
        QStringLiteral("obs studio"),
        QStringLiteral("brave"),
        QStringLiteral("brave browser"),
        QStringLiteral("opera"),
        QStringLiteral("opera gx"),
        QStringLiteral("firefox"),
        QStringLiteral("google chrome"),
        QStringLiteral("iheartradio"),
        QStringLiteral("krita"),
        QStringLiteral("blender"),
        QStringLiteral("unreal engine"),
        QStringLiteral("twinmotion"),
        QStringLiteral("quixel bridge"),
        QStringLiteral("realitycapture"),
        QStringLiteral("metahuman"),
        QStringLiteral("fab"),
        QStringLiteral("core"),
        QStringLiteral("epic online services"),
        QStringLiteral("wondershare filmora"),
        QStringLiteral("cyberlink powerdirector"),
        QStringLiteral("magix"),
        QStringLiteral("overwolf"),
        QStringLiteral("voicemod"),
        QStringLiteral("medal"),
        QStringLiteral("medal.tv"),
        QStringLiteral("parsec"),
        QStringLiteral("steam link")
    };
    if (kExactBlockedTitles.contains(t)) {
        return true;
    }
    if (a == QLatin1String("discord") || a.startsWith(QLatin1String("discord-")) ||
        t.startsWith(QLatin1String("discord ")) || t == QLatin1String("discord")) {
        return true;
    }
    if (t.contains(QStringLiteral("original soundtrack")) ||
        t.endsWith(QStringLiteral(" soundtrack")) ||
        t.contains(QStringLiteral("digital artbook")) ||
        t.endsWith(QStringLiteral(" artbook")) ||
        t.contains(QStringLiteral("dedicated server")) ||
        t.contains(QStringLiteral("mod kit")) ||
        t.contains(QStringLiteral("modkit")) ||
        t.contains(QStringLiteral("creation kit")) ||
        t.endsWith(QStringLiteral(" sdk")) ||
        t.endsWith(QStringLiteral(" editor"))) {
        return true;
    }
    return false;
}

void EpicService::toggleHideEpicGame(const QString& appName) {
    if (appName.isEmpty() || !m_db) return;
    auto opt = m_db->getEpicLibraryItem(appName);
    if (!opt.has_value()) return;
    const bool nextHidden = !opt->isHidden;
    if (m_db->setEpicLibraryItemHidden(appName, nextHidden)) {
        m_model->reload();
        emit operationStatus(
            nextHidden ? QStringLiteral("Hidden '%1' from Epic Games library.").arg(opt->title)
                       : QStringLiteral("Unhid '%1' in Epic Games library.").arg(opt->title),
            false);
    }
}

void EpicService::persistDownloadQueueItem(const std::shared_ptr<DownloadSession>& session) {
    if (!m_db || !session || session->queueId.isEmpty() ||
        session->verifyOnly || session->isImporting || session->isEosOverlay) {
        return;
    }
    QJsonObject payload;
    payload[QStringLiteral("appName")] = session->appName;
    payload[QStringLiteral("namespaceId")] = session->namespaceId;
    payload[QStringLiteral("catalogItemId")] = session->catalogItemId;
    payload[QStringLiteral("title")] = session->title;
    payload[QStringLiteral("coverPath")] = session->coverPath;
    payload[QStringLiteral("installDir")] = session->installDir;
    payload[QStringLiteral("runnerId")] = session->runnerId;
    payload[QStringLiteral("prefixMode")] = session->prefixMode;
    payload[QStringLiteral("customPrefixName")] = session->customPrefixName;
    payload[QStringLiteral("customPrefixLocation")] = session->customPrefixLocation;
    payload[QStringLiteral("prefixArch")] = session->prefixArch;
    payload[QStringLiteral("selectedInstallTags")] = QJsonArray::fromStringList(session->selectedInstallTags);
    payload[QStringLiteral("selectedDlcs")] = QJsonArray::fromStringList(session->selectedDlcs);
    payload[QStringLiteral("isUpdate")] = session->isUpdate;
    payload[QStringLiteral("isDlc")] = session->isDlc;
    payload[QStringLiteral("existingGameId")] = session->existingGameId;
    payload[QStringLiteral("parentAppName")] = session->parentAppName;
    payload[QStringLiteral("downloadedBytes")] = session->downloadedBytes;
    payload[QStringLiteral("totalDownloadBytes")] = session->totalDownloadBytes;
    payload[QStringLiteral("progress")] = session->progress;

    QueuedDownloadRecord rec;
    rec.id = session->queueId;
    rec.kind = session->isDlc ? QStringLiteral("epic_dlc")
                              : (session->isUpdate ? QStringLiteral("epic_update") : QStringLiteral("epic_install"));
    rec.title = session->title;
    rec.appName = session->appName;
    rec.payloadJson = QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact));
    rec.status = session->isPaused ? QStringLiteral("paused")
                                   : (session->isQueued ? QStringLiteral("queued") : QStringLiteral("active"));
    rec.createdAt = QDateTime::currentSecsSinceEpoch();
    m_db->saveQueuedDownload(rec);
}

void EpicService::removePersistedDownloadQueueItem(const QString& queueId) {
    if (m_db && !queueId.isEmpty()) {
        m_db->removeQueuedDownload(queueId);
    }
}

void EpicService::restorePendingDownloads() {
    if (!m_db) return;
    const QList<QueuedDownloadRecord> saved = m_db->getAllQueuedDownloads();
    for (const QueuedDownloadRecord& rec : saved) {
        if (!rec.kind.startsWith(QStringLiteral("epic_"))) continue;
        const QJsonObject p = QJsonDocument::fromJson(rec.payloadJson.toUtf8()).object();
        const QString appName = p.value(QStringLiteral("appName")).toString(rec.appName);
        const QString installDir = p.value(QStringLiteral("installDir")).toString();
        if (appName.isEmpty() || installDir.isEmpty() || m_downloads.contains(appName)) {
            continue;
        }
        // Skip if already installed as a non-update fresh install
        const bool isUpdate = p.value(QStringLiteral("isUpdate")).toBool(false);
        const bool isDlc = p.value(QStringLiteral("isDlc")).toBool(false);
        if (!isUpdate && !isDlc && m_db->getGameByEpicAppName(appName).has_value()) {
            m_db->removeQueuedDownload(rec.id);
            continue;
        }

        auto session = std::make_shared<DownloadSession>();
        session->queueId = rec.id;
        session->appName = appName;
        session->namespaceId = p.value(QStringLiteral("namespaceId")).toString();
        session->catalogItemId = p.value(QStringLiteral("catalogItemId")).toString();
        session->title = p.value(QStringLiteral("title")).toString(rec.title);
        session->coverPath = p.value(QStringLiteral("coverPath")).toString();
        session->installDir = installDir;
        session->runnerId = p.value(QStringLiteral("runnerId")).toString();
        session->prefixMode = p.value(QStringLiteral("prefixMode")).toString(QStringLiteral("default-prefix"));
        session->customPrefixName = p.value(QStringLiteral("customPrefixName")).toString();
        session->customPrefixLocation = p.value(QStringLiteral("customPrefixLocation")).toString();
        session->prefixArch = p.value(QStringLiteral("prefixArch")).toString(QStringLiteral("win64"));
        for (const QJsonValue& v : p.value(QStringLiteral("selectedInstallTags")).toArray()) {
            session->selectedInstallTags.append(v.toString());
        }
        for (const QJsonValue& v : p.value(QStringLiteral("selectedDlcs")).toArray()) {
            session->selectedDlcs.append(v.toString());
        }
        session->isUpdate = isUpdate;
        session->isDlc = isDlc;
        session->existingGameId = p.value(QStringLiteral("existingGameId")).toString();
        session->parentAppName = p.value(QStringLiteral("parentAppName")).toString();
        session->downloadedBytes = p.value(QStringLiteral("downloadedBytes")).toVariant().toLongLong();
        session->totalDownloadBytes = p.value(QStringLiteral("totalDownloadBytes")).toVariant().toLongLong();
        session->progress = p.value(QStringLiteral("progress")).toDouble(0.0);
        session->isPaused = true;
        session->isQueued = false;
        session->stageText = QStringLiteral("Paused");
        session->etaText = QStringLiteral("Paused");
        session->speedTimer.start();
        session->uiEmitTimer.start();

        m_downloads.insert(appName, session);
        if (m_dlMgr) {
            QPointer<EpicService> self(this);
            DownloadManager::ExternalAdapter adapter;
            adapter.startFn = [self, session]() {
                if (self) self->beginSessionExecution(session);
            };
            adapter.pauseFn = [self, appName]() {
                if (self) self->pauseDownload(appName);
            };
            adapter.resumeFn = [self, appName]() {
                if (self) self->resumeDownload(appName);
            };
            adapter.cancelFn = [self, appName, isUpdate, isDlc](bool delPartial) {
                if (self) self->cancelDownload(appName, (!isUpdate && !isDlc) ? delPartial : false);
            };
            m_dlMgr->registerExternalTask(
                session->queueId,
                session->title,
                rec.kind,
                session->appName,
                session->coverPath,
                true,
                std::move(adapter),
                false,
                true); // initialPaused = true -> ready to resume cleanly from Downloads or Epic tab!
            notifyDownloadManagerProgress(session);
        }
        emit downloadStateChanged(appName);
    }
    if (!saved.isEmpty()) {
        emit activeDownloadsChanged();
        if (m_model) m_model->reload();
    }
}

void EpicService::setGameManager(GameManager* gm) {
    m_gameMgr = gm;
    if (m_gameMgr) {
        m_gameMgr->setEpicService(this);
        connect(m_gameMgr, &GameManager::gamesChanged, m_model, &EpicLibraryModel::reload);
    }
}

void EpicService::setDownloadManager(DownloadManager* dlMgr) {
    m_dlMgr = dlMgr;
}

void EpicService::setUmuIdResolver(UmuIdResolver* resolver) {
    m_umuResolver = resolver;
}

QString EpicService::loginUrl() const {
    return QStringLiteral(
               "https://www.epicgames.com/id/login?redirectUrl="
               "https%3A%2F%2Fwww.epicgames.com%2Fid%2Fapi%2Fredirect%3F"
               "clientId%3D%1%26responseType%3Dcode")
        .arg(QLatin1String(kEpicClientId));
}

QString EpicService::authFilePath() const {
    return AppSettings::configDir() + QStringLiteral("/epic_auth.json");
}

QString EpicService::manifestCachePath(const QString& appName) const {
    const QString dir = AppSettings::dataDir() + QStringLiteral("/epic_manifests");
    QDir().mkpath(dir);
    return dir + QStringLiteral("/") + sanitizeFolderName(appName) + QStringLiteral(".manifest");
}

void EpicService::loadAuthSession() {
    const QString raw = SecretStore::loadSecret(QStringLiteral("epic_oauth_session"), authFilePath());
    if (raw.isEmpty()) return;
    const QJsonDocument doc = QJsonDocument::fromJson(raw.toUtf8());
    if (!doc.isObject()) return;
    const QJsonObject obj = doc.object();
    m_accessToken = obj.value(QStringLiteral("accessToken")).toString();
    m_refreshToken = obj.value(QStringLiteral("refreshToken")).toString();
    m_accountId = obj.value(QStringLiteral("accountId")).toString();
    m_displayName = obj.value(QStringLiteral("displayName")).toString();
    m_expiresAtEpoch = obj.value(QStringLiteral("expiresAtEpoch")).toVariant().toLongLong();
    m_refreshExpiresAtEpoch = obj.value(QStringLiteral("refreshExpiresAtEpoch")).toVariant().toLongLong();

    const qint64 now = QDateTime::currentSecsSinceEpoch();
    m_isSignedIn = !m_refreshToken.isEmpty() && (m_refreshExpiresAtEpoch <= 0 || m_refreshExpiresAtEpoch > now);
}

void EpicService::saveAuthSession() {
    QDir().mkpath(AppSettings::configDir());
    QJsonObject obj;
    obj[QStringLiteral("accessToken")] = m_accessToken;
    obj[QStringLiteral("refreshToken")] = m_refreshToken;
    obj[QStringLiteral("accountId")] = m_accountId;
    obj[QStringLiteral("displayName")] = m_displayName;
    obj[QStringLiteral("expiresAtEpoch")] = m_expiresAtEpoch;
    obj[QStringLiteral("refreshExpiresAtEpoch")] = m_refreshExpiresAtEpoch;

    const QString payload = QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    SecretStore::saveSecret(QStringLiteral("epic_oauth_session"), payload, authFilePath());
}

void EpicService::clearAuthSession() {
    m_isSignedIn = false;
    m_accessToken.clear();
    m_refreshToken.clear();
    m_accountId.clear();
    m_displayName.clear();
    m_expiresAtEpoch = 0;
    m_refreshExpiresAtEpoch = 0;
    SecretStore::deleteSecret(QStringLiteral("epic_oauth_session"), authFilePath());
}

void EpicService::applyOAuthJson(const QJsonObject& obj) {
    m_accessToken = obj.value(QStringLiteral("access_token")).toString();
    m_refreshToken = obj.value(QStringLiteral("refresh_token")).toString();
    m_accountId = obj.value(QStringLiteral("account_id")).toString();
    m_displayName = obj.value(QStringLiteral("displayName")).toString();
    if (m_displayName.isEmpty()) {
        m_displayName = obj.value(QStringLiteral("account_id")).toString();
    }

    const qint64 now = QDateTime::currentSecsSinceEpoch();
    m_expiresAtEpoch = parseIsoUtcEpoch(obj.value(QStringLiteral("expires_at")).toString());
    if (m_expiresAtEpoch <= 0) {
        m_expiresAtEpoch = now + obj.value(QStringLiteral("expires_in")).toInt(7200);
    }
    m_refreshExpiresAtEpoch = parseIsoUtcEpoch(obj.value(QStringLiteral("refresh_expires_at")).toString());
    if (m_refreshExpiresAtEpoch <= 0) {
        m_refreshExpiresAtEpoch = now + obj.value(QStringLiteral("refresh_expires")).toInt(86400 * 30);
    }

    m_isSignedIn = !m_accessToken.isEmpty() && !m_refreshToken.isEmpty();
    if (m_isSignedIn) {
        saveAuthSession();
    }
}

QString EpicService::extractAuthCode(const QString& rawInput) {
    QString s = rawInput.trimmed();
    if (s.isEmpty()) return QString();

    if (s.startsWith(QLatin1Char('{'))) {
        const QJsonDocument doc = QJsonDocument::fromJson(s.toUtf8());
        if (doc.isObject()) {
            const QJsonObject obj = doc.object();
            for (const char* key : {"authorizationCode", "code", "sid"}) {
                const QString val = obj.value(QLatin1String(key)).toString().trimmed();
                if (!val.isEmpty()) return val;
            }
            const QString redir = obj.value(QStringLiteral("redirectUrl")).toString().trimmed();
            if (!redir.isEmpty()) s = redir;
        }
    }

    if (s.contains(QStringLiteral("code="), Qt::CaseInsensitive)) {
        const QUrl url(s.startsWith(QStringLiteral("http")) ? s : (QStringLiteral("https://dummy.local/?") + s));
        const QUrlQuery q(url);
        const QString code = q.queryItemValue(QStringLiteral("code")).trimmed();
        if (!code.isEmpty()) return code;
    }

    // Strip surrounding quotes if pasted directly from JSON string
    if (s.size() >= 2 && ((s.startsWith(QLatin1Char('"')) && s.endsWith(QLatin1Char('"'))) ||
                          (s.startsWith(QLatin1Char('\'')) && s.endsWith(QLatin1Char('\''))))) {
        s = s.mid(1, s.size() - 2).trimmed();
    }

    // Fallback: regex search inside partial JSON text
    static const QRegularExpression codeRe(QStringLiteral(R"re("authorizationCode"\s*:\s*"([A-Za-z0-9_-]+)")re"));
    const auto m = codeRe.match(s);
    if (m.hasMatch()) return m.captured(1);

    return s;
}

void EpicService::openLoginInBrowser() {
    QDesktopServices::openUrl(QUrl(loginUrl()));
}

void EpicService::signInWithAuthCode(const QString& rawInput) {
    const QString code = extractAuthCode(rawInput);
    if (code.isEmpty()) {
        m_authError = QStringLiteral("Please paste the authorizationCode shown in your browser.");
        emit authStateChanged();
        return;
    }

    m_isSigningIn = true;
    m_authError.clear();
    emit authStateChanged();

    QNetworkRequest req(QUrl(QStringLiteral("https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token")));
    req.setRawHeader("Authorization", basicAuthHeader());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

    QUrlQuery body;
    body.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("authorization_code"));
    body.addQueryItem(QStringLiteral("code"), code);
    body.addQueryItem(QStringLiteral("token_type"), QStringLiteral("eg1"));

    QNetworkReply* reply = m_nam.post(req, body.toString(QUrl::FullyEncoded).toUtf8());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = safeReadReply(reply);
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError netErr = reply->error();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        m_isSigningIn = false;
        if (netErr != QNetworkReply::NoError || httpStatus >= 400) {
            const QJsonObject errObj = QJsonDocument::fromJson(payload).object();
            const QString epicMsg = errObj.value(QStringLiteral("errorMessage")).toString();
            m_authError = !epicMsg.isEmpty() ? epicMsg : (errStr.isEmpty() ? QStringLiteral("Sign in failed (HTTP %1)").arg(httpStatus) : errStr);
            emit authStateChanged();
            emit operationStatus(m_authError, true);
            return;
        }

        const QJsonObject obj = QJsonDocument::fromJson(payload).object();
        applyOAuthJson(obj);
        if (!m_isSignedIn) {
            m_authError = QStringLiteral("Invalid token response from Epic Games.");
            emit authStateChanged();
            emit operationStatus(m_authError, true);
            return;
        }

        m_authError.clear();
        emit authStateChanged();
        emit operationStatus(QStringLiteral("Signed in to Epic Games as %1.").arg(m_displayName), false);
        syncLibrary();
    });
}

void EpicService::signOut() {
    const QList<QString> keys = m_downloads.keys();
    for (const QString& app : keys) {
        cancelDownload(app, true);
    }
    clearAuthSession();
    m_db->clearEpicLibrary();
    m_authError.clear();
    m_model->reload();
    emit authStateChanged();
    emit libraryUpdated();
    emit operationStatus(QStringLiteral("Signed out of Epic Games."), false);
}

void EpicService::ensureValidToken(std::function<void(bool ok)> callback) {
    if (!m_isSignedIn || m_refreshToken.isEmpty()) {
        if (callback) callback(false);
        return;
    }

    const qint64 now = QDateTime::currentSecsSinceEpoch();
    if (!m_accessToken.isEmpty() && m_expiresAtEpoch > now + 300) {
        if (callback) callback(true);
        return;
    }

    if (callback) m_pendingRefreshCallbacks.append(std::move(callback));
    if (m_isRefreshingToken) return;
    m_isRefreshingToken = true;

    QNetworkRequest req(QUrl(QStringLiteral("https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token")));
    req.setRawHeader("Authorization", basicAuthHeader());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

    QUrlQuery body;
    body.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("refresh_token"));
    body.addQueryItem(QStringLiteral("refresh_token"), m_refreshToken);
    body.addQueryItem(QStringLiteral("token_type"), QStringLiteral("eg1"));

    QNetworkReply* reply = m_nam.post(req, body.toString(QUrl::FullyEncoded).toUtf8());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = safeReadReply(reply);
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QNetworkReply::NetworkError netErr = reply->error();
        reply->deleteLater();
        m_isRefreshingToken = false;

        bool ok = false;
        if (netErr == QNetworkReply::NoError && httpStatus < 400) {
            const QJsonObject obj = QJsonDocument::fromJson(payload).object();
            applyOAuthJson(obj);
            ok = m_isSignedIn;
        } else if (httpStatus == 400 || httpStatus == 401) {
            clearAuthSession();
            m_authError = QStringLiteral("Epic Games session expired. Please sign in again.");
            emit authStateChanged();
        }

        auto cbs = std::move(m_pendingRefreshCallbacks);
        m_pendingRefreshCallbacks.clear();
        for (auto& cb : cbs) {
            if (cb) cb(ok);
        }
    });
}

void EpicService::requestExchangeCode(std::function<void(bool ok, const QString& code)> callback) {
    ensureValidToken([this, callback](bool ok) {
        if (!ok) {
            if (callback) callback(false, QString());
            return;
        }

        QNetworkRequest req(QUrl(QStringLiteral("https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/exchange")));
        req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
        req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

        QNetworkReply* reply = m_nam.get(req);
        connect(reply, &QNetworkReply::finished, this, [reply, callback]() {
            const bool netOk = (reply->error() == QNetworkReply::NoError);
            const QByteArray payload = netOk ? safeReadReply(reply) : QByteArray();
            reply->deleteLater();
            if (!netOk) {
                if (callback) callback(false, QString());
                return;
            }
            const QJsonObject obj = QJsonDocument::fromJson(payload).object();
            const QString code = obj.value(QStringLiteral("code")).toString().trimmed();
            if (callback) callback(!code.isEmpty(), code);
        });
    });
}

void EpicService::syncLibrary() {
    if (!m_isSignedIn) return;
    if (m_isSyncing) return;

    m_isSyncing = true;
    emit syncingChanged();

    m_pendingEntitlements.clear();
    m_pendingBatchesByNs.clear();
    m_catalogQueue.clear();
    m_syncedCatalogItems.clear();
    m_syncedDlcs.clear();

    ensureValidToken([this](bool ok) {
        if (!ok) {
            m_isSyncing = false;
            emit syncingChanged();
            return;
        }
        fetchEntitlementPage(QString());
    });
}

void EpicService::fetchEntitlementPage(const QString& cursor) {
    QUrl url(QStringLiteral("https://library-service.live.use1a.on.epicgames.com/library/api/public/items"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("includeMetadata"), QStringLiteral("true"));
    if (!cursor.isEmpty()) {
        q.addQueryItem(QStringLiteral("cursor"), cursor);
    }
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray payload = safeReadReply(reply);
        const QNetworkReply::NetworkError netErr = reply->error();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (netErr != QNetworkReply::NoError) {
            m_isSyncing = false;
            emit syncingChanged();
            emit operationStatus(QStringLiteral("Epic library sync failed: %1").arg(errStr), true);
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(payload).object();
        const QJsonArray records = root.value(QStringLiteral("records")).toArray();
        for (const QJsonValue& rv : records) {
            const QJsonObject ro = rv.toObject();
            const QString ns = ro.value(QStringLiteral("namespace")).toString().trimmed();
            const QString catId = ro.value(QStringLiteral("catalogItemId")).toString().trimmed();
            const QString appName = ro.value(QStringLiteral("appName")).toString().trimmed();
            const QString sandboxType = ro.value(QStringLiteral("sandboxType")).toString();
            if (ns.isEmpty() || catId.isEmpty() || appName.isEmpty()) continue;
            if (ns == QLatin1String("ue") || sandboxType == QLatin1String("PRIVATE")) continue;

            EpicLibraryItem item;
            item.appName = appName;
            item.namespaceId = ns;
            item.catalogItemId = catId;
            item.title = ro.value(QStringLiteral("sandboxName")).toString().trimmed();
            item.lastSynced = QDateTime::currentSecsSinceEpoch();
            m_pendingEntitlements.append(item);
        }

        const QString nextCursor = root.value(QStringLiteral("responseMetadata")).toObject().value(QStringLiteral("nextCursor")).toString();
        if (!nextCursor.isEmpty()) {
            fetchEntitlementPage(nextCursor);
        } else {
            enqueueCatalogBatches();
        }
    });
}

void EpicService::enqueueCatalogBatches() {
    if (m_pendingEntitlements.isEmpty()) {
        finishLibrarySync();
        return;
    }

    QHash<QString, EpicLibraryItem> byApp;
    for (const EpicLibraryItem& it : m_pendingEntitlements) {
        if (!byApp.contains(it.appName)) {
            byApp.insert(it.appName, it);
            m_pendingBatchesByNs[it.namespaceId].append(it);
        }
    }

    for (auto it = m_pendingBatchesByNs.constBegin(); it != m_pendingBatchesByNs.constEnd(); ++it) {
        const QString ns = it.key();
        const QList<EpicLibraryItem>& list = it.value();
        for (int i = 0; i < list.size(); i += 50) {
            m_catalogQueue.append({ns, list.mid(i, 50)});
        }
    }

    processNextCatalogBatch();
}

void EpicService::processNextCatalogBatch() {
    if (m_catalogQueue.isEmpty()) {
        finishLibrarySync();
        return;
    }

    const auto batch = m_catalogQueue.takeFirst();
    const QString ns = batch.first;
    const QList<EpicLibraryItem> items = batch.second;

    QUrl url(QStringLiteral("https://catalog-public-service-prod06.ol.epicgames.com/catalog/api/shared/namespace/%1/bulk/items").arg(ns));
    QUrlQuery q;
    for (const EpicLibraryItem& it : items) {
        q.addQueryItem(QStringLiteral("id"), it.catalogItemId);
    }
    q.addQueryItem(QStringLiteral("includeDLCDetails"), QStringLiteral("true"));
    q.addQueryItem(QStringLiteral("includeMainGameDetails"), QStringLiteral("true"));
    q.addQueryItem(QStringLiteral("country"), QStringLiteral("US"));
    q.addQueryItem(QStringLiteral("locale"), QStringLiteral("en"));
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, items]() {
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const QByteArray payload = ok ? safeReadReply(reply) : QByteArray();
        reply->deleteLater();

        if (ok) {
            const QJsonObject root = QJsonDocument::fromJson(payload).object();
            for (const EpicLibraryItem& base : items) {
                if (!root.contains(base.catalogItemId)) continue;
                const QJsonObject catObj = root.value(base.catalogItemId).toObject();

                // Capture owned DLC items linked to a parent mainGameItem
                if (catObj.contains(QStringLiteral("mainGameItem")) && catObj.value(QStringLiteral("mainGameItem")).isObject()) {
                    const QJsonObject mainObj = catObj.value(QStringLiteral("mainGameItem")).toObject();
                    QString parentAppName;
                    const QJsonArray relInfo = mainObj.value(QStringLiteral("releaseInfo")).toArray();
                    if (!relInfo.isEmpty()) {
                        parentAppName = relInfo.first().toObject().value(QStringLiteral("appId")).toString().trimmed();
                    }
                    if (!parentAppName.isEmpty()) {
                        EpicDlcItem dlc;
                        dlc.appName = base.appName;
                        dlc.parentAppName = parentAppName;
                        dlc.namespaceId = base.namespaceId;
                        dlc.catalogItemId = base.catalogItemId;
                        dlc.title = catObj.value(QStringLiteral("title")).toString().trimmed();
                        if (dlc.title.isEmpty()) dlc.title = base.title.isEmpty() ? base.appName : base.title;
                        dlc.description = catObj.value(QStringLiteral("description")).toString().trimmed();
                        m_syncedDlcs.append(dlc);
                    }
                    continue;
                }

                if (!isCatalogItemPlayableGame(catObj, base.appName)) continue;

                EpicLibraryItem resolved = base;
                const QString catTitle = catObj.value(QStringLiteral("title")).toString().trimmed();
                if (!catTitle.isEmpty()) resolved.title = catTitle;
                if (resolved.title.isEmpty()) continue;

                resolved.developer = catObj.value(QStringLiteral("developer")).toString().trimmed();
                if (resolved.developer.isEmpty()) {
                    resolved.developer = catObj.value(QStringLiteral("seller")).toString().trimmed();
                }
                resolved.description = catObj.value(QStringLiteral("description")).toString().trimmed();
                extractKeyImages(catObj, resolved.coverUrl, resolved.bannerUrl, resolved.logoUrl);

                // Extract Cloud Save folder and include/exclude patterns from customAttributes
                const QJsonObject attrs = catObj.value(QStringLiteral("customAttributes")).toObject();
                const QString cloudFolder = attrs.value(QStringLiteral("CloudSaveFolder")).toObject()
                                                .value(QStringLiteral("value")).toString().trimmed();
                if (!cloudFolder.isEmpty()) {
                    resolved.cloudSaveFolder = cloudFolder;
                }
                const QString incStr = attrs.value(QStringLiteral("CloudIncludeList")).toObject()
                                           .value(QStringLiteral("value")).toString().trimmed();
                if (!incStr.isEmpty()) {
                    for (const QString& p : incStr.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
                        if (!p.trimmed().isEmpty()) resolved.cloudIncludeList.append(p.trimmed());
                    }
                }
                const QString excStr = attrs.value(QStringLiteral("CloudExcludeList")).toObject()
                                           .value(QStringLiteral("value")).toString().trimmed();
                if (!excStr.isEmpty()) {
                    for (const QString& p : excStr.split(QLatin1Char(','), Qt::SkipEmptyParts)) {
                        if (!p.trimmed().isEmpty()) resolved.cloudExcludeList.append(p.trimmed());
                    }
                }

                // Also capture dlcItemList metadata if embedded by Epic
                const QJsonArray dlcList = catObj.value(QStringLiteral("dlcItemList")).toArray();
                for (const QJsonValue& dv : dlcList) {
                    const QJsonObject dObj = dv.toObject();
                    const QString dCatId = dObj.value(QStringLiteral("id")).toString().trimmed();
                    const QString dNs = dObj.value(QStringLiteral("namespace")).toString().trimmed();
                    const QJsonArray dRel = dObj.value(QStringLiteral("releaseInfo")).toArray();
                    const QString dApp = dRel.isEmpty() ? QString() : dRel.first().toObject().value(QStringLiteral("appId")).toString().trimmed();
                    if (dApp.isEmpty() || dCatId.isEmpty()) continue;
                    // Only include DLCs that appeared in the user's owned entitlements
                    bool owned = false;
                    for (const EpicLibraryItem& ent : m_pendingEntitlements) {
                        if (ent.appName == dApp || ent.catalogItemId == dCatId) {
                            owned = true;
                            break;
                        }
                    }
                    if (!owned) continue;
                    EpicDlcItem dlc;
                    dlc.appName = dApp;
                    dlc.parentAppName = base.appName;
                    dlc.namespaceId = dNs.isEmpty() ? base.namespaceId : dNs;
                    dlc.catalogItemId = dCatId;
                    dlc.title = dObj.value(QStringLiteral("title")).toString().trimmed();
                    if (dlc.title.isEmpty()) dlc.title = dApp;
                    dlc.description = dObj.value(QStringLiteral("description")).toString().trimmed();
                    m_syncedDlcs.append(dlc);
                }

                m_syncedCatalogItems.append(resolved);
            }
        } else {
            // Keep minimal entitlement fallback if catalog query fails transiently
            for (const EpicLibraryItem& base : items) {
                if (!base.title.isEmpty()) m_syncedCatalogItems.append(base);
            }
        }

        processNextCatalogBatch();
    });
}

void EpicService::finishLibrarySync() {
    m_isSyncing = false;
    if (!m_syncedCatalogItems.isEmpty()) {
        m_db->saveEpicLibraryItems(m_syncedCatalogItems);
    }
    if (!m_syncedDlcs.isEmpty()) {
        m_db->saveEpicDlcs(m_syncedDlcs);
    }
    const QList<EpicLibraryItem> cached = m_db->getAllEpicLibraryItems();
    queueArtworkForItems(cached);

    m_model->reload();
    emit syncingChanged();
    emit libraryUpdated();
    checkForUpdates();
}

void EpicService::queueArtworkForItems(const QList<EpicLibraryItem>& items) {
    for (const EpicLibraryItem& item : items) {
        const QString artDir = AppSettings::artworkDir() + QStringLiteral("/epic_") + sanitizeFolderName(item.appName);
        auto maybeQueue = [&](const QString& type, const QString& urlStr, const QString& existingPath) {
            if (urlStr.isEmpty()) return;
            if (!existingPath.isEmpty() && QFileInfo::exists(existingPath)) return;
            const QString key = item.appName + QLatin1Char(':') + type;
            if (m_queuedArtKeys.contains(key)) return;
            m_queuedArtKeys.insert(key);

            const QString dest = artDir + QStringLiteral("/") + type + QStringLiteral(".jpg");
            if (QFileInfo::exists(dest) && QFileInfo(dest).size() > 256) {
                m_db->updateEpicLibraryArtwork(
                    item.appName,
                    type == QLatin1String("cover") ? dest : QString(),
                    type == QLatin1String("banner") ? dest : QString(),
                    type == QLatin1String("logo") ? dest : QString());
                return;
            }
            m_artworkQueue.enqueue({item.appName, type, urlStr, dest});
        };

        maybeQueue(QStringLiteral("cover"), item.coverUrl, item.coverPath);
        maybeQueue(QStringLiteral("banner"), item.bannerUrl, item.bannerPath);
        maybeQueue(QStringLiteral("logo"), item.logoUrl, item.logoPath);
    }
    pumpArtworkQueue();
}

void EpicService::pumpArtworkQueue() {
    while (m_activeArtworkDownloads < kMaxConcurrentArtwork && !m_artworkQueue.isEmpty()) {
        const ArtworkTask task = m_artworkQueue.dequeue();
        QDir().mkpath(QFileInfo(task.destPath).absolutePath());
        ++m_activeArtworkDownloads;

        QNetworkRequest req(QUrl(task.url));
        req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0"));

        QNetworkReply* reply = m_nam.get(req);
        connect(reply, &QNetworkReply::finished, this, [this, reply, task]() {
            --m_activeArtworkDownloads;
            if (reply->error() == QNetworkReply::NoError) {
                const QByteArray bytes = reply->readAll();
                if (bytes.size() > 256) {
                    QFile f(task.destPath);
                    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                        f.write(bytes);
                        f.close();
                        m_db->updateEpicLibraryArtwork(
                            task.appName,
                            task.type == QLatin1String("cover") ? task.destPath : QString(),
                            task.type == QLatin1String("banner") ? task.destPath : QString(),
                            task.type == QLatin1String("logo") ? task.destPath : QString());
                        m_model->notifyAppChanged(task.appName);
                    }
                }
            }
            reply->deleteLater();
            pumpArtworkQueue();
        });
    }
}

void EpicService::fetchInstallInfo(const QString& appName) {
    auto itemOpt = m_db->getEpicLibraryItem(appName);
    if (!itemOpt.has_value()) return;
    const EpicLibraryItem item = *itemOpt;

    const QVariantList cachedTags = getInstallTagsForGame(appName);
    const QVariantList dlcs = getDlcsForGame(appName);
    if (item.downloadSize > 0 && item.installSize > 0 && QFileInfo::exists(manifestCachePath(appName))) {
        emit installInfoReady(appName, item.downloadSize, item.installSize);
        emit installDetailsReady(appName, cachedTags, dlcs);
        return;
    }

    fetchAssetManifest(item, [this, appName](bool ok,
                                             const EpicManifest& manifest,
                                             const QList<MirrorEndpoint>&,
                                             const QByteArray& rawManifest,
                                             const QString&) {
        if (!ok) return;
        QFile mf(manifestCachePath(appName));
        if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            mf.write(rawManifest);
            mf.close();
        }
        m_db->updateEpicLibrarySizes(appName, manifest.totalDownloadSize, manifest.totalInstallSize, manifest.buildVersion);
        m_model->notifyAppChanged(appName);
        emit installInfoReady(appName, manifest.totalDownloadSize, manifest.totalInstallSize);
        emit installDetailsReady(appName, getInstallTagsForGame(appName), getDlcsForGame(appName));
    });
}

QVariantList EpicService::getDlcsForGame(const QString& appName) const {
    QVariantList out;
    if (!m_db || appName.isEmpty()) return out;
    for (const EpicDlcItem& d : m_db->getEpicDlcsForGame(appName)) {
        out.append(d.toVariantMap());
    }
    return out;
}

QVariantList EpicService::getInstallTagsForGame(const QString& appName) const {
    QVariantList out;
    if (appName.isEmpty()) return out;
    QFile mf(manifestCachePath(appName));
    if (!mf.exists() || !mf.open(QIODevice::ReadOnly)) return out;
    EpicManifest parsed;
    if (!EpicManifestParser::parse(mf.readAll(), parsed)) return out;
    for (const EpicInstallTagInfo& info : parsed.computeInstallTags()) {
        QVariantMap m;
        m[QStringLiteral("tag")] = info.tag;
        m[QStringLiteral("downloadSize")] = info.downloadSize;
        m[QStringLiteral("installSize")] = info.installSize;
        m[QStringLiteral("downloadSizeFormatted")] = DownloadManager::formatBytes(info.downloadSize);
        m[QStringLiteral("installSizeFormatted")] = DownloadManager::formatBytes(info.installSize);
        m[QStringLiteral("fileCount")] = info.fileCount;
        out.append(m);
    }
    return out;
}

void EpicService::checkForUpdates() {
    if (!m_isSignedIn || !m_db) return;
    const QList<GameRecord> games = m_db->getAllGames();
    QList<GameRecord> epicGames;
    for (const GameRecord& g : games) {
        if (g.isEpic() && !g.epicNamespace.isEmpty() && !g.epicCatalogItemId.isEmpty()) {
            epicGames.append(g);
        }
    }
    if (epicGames.isEmpty()) return;

    ensureValidToken([this, epicGames](bool ok) {
        if (!ok) return;
        for (const GameRecord& g : epicGames) {
            const QString assetUrl = QStringLiteral(
                "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/public/assets/v2/platform/Windows/"
                "namespace/%1/catalogItem/%2/app/%3/label/Live")
                .arg(g.epicNamespace, g.epicCatalogItemId, g.epicAppName);
            QNetworkRequest req{QUrl(assetUrl)};
            req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
            req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

            QNetworkReply* reply = m_nam.get(req);
            const QString appName = g.epicAppName;
            const QString installedBuild = g.epicBuildVersion.trimmed();
            connect(reply, &QNetworkReply::finished, this, [this, reply, appName, installedBuild]() {
                const bool netOk = (reply->error() == QNetworkReply::NoError);
                const QByteArray body = netOk ? safeReadReply(reply) : QByteArray();
                reply->deleteLater();
                if (!netOk) return;

                const QJsonArray elements = QJsonDocument::fromJson(body).object().value(QStringLiteral("elements")).toArray();
                if (elements.isEmpty()) return;
                const QString latestBuild = elements.first().toObject().value(QStringLiteral("buildVersion")).toString().trimmed();
                if (latestBuild.isEmpty()) return;

                m_latestBuildVersions.insert(appName, latestBuild);
                const bool hasUpd = !installedBuild.isEmpty() && (latestBuild != installedBuild);
                const bool prev = m_appsWithUpdates.contains(appName);
                if (hasUpd) m_appsWithUpdates.insert(appName);
                else m_appsWithUpdates.remove(appName);

                if (hasUpd != prev) {
                    emit updatesChanged();
                }
            });
        }
    });
}

void EpicService::fetchAssetManifest(const EpicLibraryItem& item,
                                     std::function<void(bool,
                                                        const EpicManifest&,
                                                        const QList<MirrorEndpoint>&,
                                                        const QByteArray&,
                                                        const QString&)> callback) {
    ensureValidToken([this, item, callback](bool ok) {
        if (!ok) {
            if (callback) callback(false, EpicManifest{}, {}, {}, QStringLiteral("Please sign in to Epic Games."));
            return;
        }
        fetchAssetManifestWithToken(item, m_accessToken, callback);
    });
}

void EpicService::fetchAssetManifestWithToken(const EpicLibraryItem& item,
                                              const QString& bearerToken,
                                              std::function<void(bool,
                                                                 const EpicManifest&,
                                                                 const QList<MirrorEndpoint>&,
                                                                 const QByteArray&,
                                                                 const QString&)> callback) {
    if (bearerToken.isEmpty()) {
        if (callback) callback(false, EpicManifest{}, {}, {}, QStringLiteral("Missing Epic authorization token."));
        return;
    }

    const QString assetUrl = QStringLiteral(
        "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/public/assets/v2/platform/Windows/"
        "namespace/%1/catalogItem/%2/app/%3/label/Live")
        .arg(item.namespaceId, item.catalogItemId, item.appName);

    QNetworkRequest req{QUrl(assetUrl)};
    req.setRawHeader("Authorization", QByteArray("Bearer ") + bearerToken.toUtf8());
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, callback]() {
        const bool netOk = (reply->error() == QNetworkReply::NoError);
        const QByteArray body = netOk ? safeReadReply(reply) : QByteArray();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (!netOk) {
            if (callback) callback(false, EpicManifest{}, {}, {}, errStr);
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(body).object();
        const QJsonArray elements = root.value(QStringLiteral("elements")).toArray();
        if (elements.isEmpty()) {
            if (callback) callback(false, EpicManifest{}, {}, {}, QStringLiteral("No Windows build manifest available for this title."));
            return;
        }

        const QJsonArray manifests = elements.first().toObject().value(QStringLiteral("manifests")).toArray();
        if (manifests.isEmpty()) {
            if (callback) callback(false, EpicManifest{}, {}, {}, QStringLiteral("Epic returned an empty manifest list."));
            return;
        }

        QList<MirrorEndpoint> mirrors;
        QUrl manifestUrl;
        for (const QJsonValue& mv : manifests) {
            const QJsonObject mo = mv.toObject();
            const QString uri = mo.value(QStringLiteral("uri")).toString().trimmed();
            if (uri.isEmpty()) continue;

            QList<QPair<QString, QString>> qParams;
            const QJsonArray qArr = mo.value(QStringLiteral("queryParams")).toArray();
            for (const QJsonValue& qv : qArr) {
                const QJsonObject qo = qv.toObject();
                const QString name = qo.value(QStringLiteral("name")).toString();
                const QString val = qo.value(QStringLiteral("value")).toString();
                if (!name.isEmpty()) qParams.append({name, val});
            }

            QUrl u(uri);
            const int lastSlash = u.path().lastIndexOf(QLatin1Char('/'));
            QUrl baseU = u;
            if (lastSlash >= 0) {
                baseU.setPath(u.path().left(lastSlash));
            }
            mirrors.append({baseU.toString(), qParams});

            if (!manifestUrl.isValid()) {
                QUrlQuery mq(u);
                for (const auto& qp : qParams) {
                    mq.addQueryItem(qp.first, qp.second);
                }
                u.setQuery(mq);
                manifestUrl = u;
            }
        }

        if (!manifestUrl.isValid() || mirrors.isEmpty()) {
            if (callback) callback(false, EpicManifest{}, {}, {}, QStringLiteral("Invalid CDN manifest URL."));
            return;
        }

        QNetworkRequest mReq(manifestUrl);
        mReq.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        mReq.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

        QNetworkReply* mReply = m_nam.get(mReq);
        connect(mReply, &QNetworkReply::finished, this, [mReply, mirrors, callback]() {
            const bool mOk = (mReply->error() == QNetworkReply::NoError);
            const QByteArray rawManifest = mOk ? safeReadReply(mReply) : QByteArray();
            const QString mErr = mReply->errorString();
            mReply->deleteLater();

            if (!mOk) {
                if (callback) callback(false, EpicManifest{}, {}, {}, mErr);
                return;
            }

            EpicManifest parsed;
            QString parseErr;
            if (!EpicManifestParser::parse(rawManifest, parsed, &parseErr)) {
                if (callback) callback(false, EpicManifest{}, {}, {}, parseErr);
                return;
            }
            if (callback) callback(true, parsed, mirrors, rawManifest, QString());
        });
    });
}

QVariantMap EpicService::getEpicGameMap(const QString& appName) const {
    auto opt = m_db->getEpicLibraryItem(appName);
    if (!opt.has_value()) return QVariantMap();

    QString installedId;
    if (auto gOpt = m_db->getGameByEpicAppName(appName); gOpt.has_value()) {
        installedId = gOpt->id;
    }

    QVariantMap m = opt->toVariantMap(!installedId.isEmpty(), installedId, hasUpdate(appName));
    m[QStringLiteral("latestBuildVersion")] = latestBuildVersion(appName);
    const QVariantMap dl = getDownloadState(appName);
    for (auto it = dl.constBegin(); it != dl.constEnd(); ++it) {
        m.insert(it.key(), it.value());
    }
    return m;
}

QVariantMap EpicService::getDownloadState(const QString& appName) const {
    QVariantMap m;
    auto s = m_downloads.value(appName);
    if (!s) {
        m[QStringLiteral("isDownloading")] = false;
        m[QStringLiteral("isPaused")] = false;
        m[QStringLiteral("isQueued")] = false;
        m[QStringLiteral("isVerifying")] = false;
        m[QStringLiteral("isImporting")] = false;
        m[QStringLiteral("progress")] = 0.0;
        m[QStringLiteral("downloadedBytes")] = 0;
        m[QStringLiteral("totalBytes")] = 0;
        m[QStringLiteral("downloadedSizeStr")] = QStringLiteral("0 B");
        m[QStringLiteral("totalSizeStr")] = QString();
        m[QStringLiteral("speedText")] = QString();
        m[QStringLiteral("eta")] = QString();
        m[QStringLiteral("stage")] = QString();
        return m;
    }
    m[QStringLiteral("isDownloading")] = true;
    m[QStringLiteral("isPaused")] = s->isPaused;
    m[QStringLiteral("isQueued")] = s->isQueued;
    m[QStringLiteral("isVerifying")] = s->isVerifying;
    m[QStringLiteral("isImporting")] = s->isImporting;
    m[QStringLiteral("progress")] = s->progress;
    m[QStringLiteral("downloadedBytes")] = s->downloadedBytes;
    m[QStringLiteral("totalBytes")] = s->totalDownloadBytes;
    m[QStringLiteral("downloadedSizeStr")] = DownloadManager::formatBytes(s->downloadedBytes);
    m[QStringLiteral("totalSizeStr")] = s->totalDownloadBytes > 0 ? DownloadManager::formatBytes(s->totalDownloadBytes) : QString();
    m[QStringLiteral("speedText")] = s->speedText;
    m[QStringLiteral("eta")] = s->isQueued ? QStringLiteral("Queued") : s->etaText;
    m[QStringLiteral("stage")] = s->isQueued ? QStringLiteral("Queued") : s->stageText;
    return m;
}

void EpicService::notifyDownloadManagerProgress(const std::shared_ptr<DownloadSession>& session) {
    if (!m_dlMgr || !session || session->queueId.isEmpty()) return;
    m_dlMgr->updateExternalTask(
        session->queueId,
        session->progress,
        session->downloadedBytes,
        session->totalDownloadBytes,
        session->speedBps,
        session->speedText,
        session->etaText,
        session->stageText,
        session->isPaused,
        session->isQueued);
}

void EpicService::beginSessionExecution(const std::shared_ptr<DownloadSession>& session) {
    if (!session || session->isCancelled || !m_downloads.contains(session->appName)) return;
    session->isQueued = false;
    session->stageText = QStringLiteral("Fetching manifest…");
    session->speedTimer.restart();
    session->uiEmitTimer.restart();
    emit downloadStateChanged(session->appName);
    notifyDownloadManagerProgress(session);

    EpicLibraryItem item;
    item.appName = session->appName;
    item.namespaceId = session->namespaceId;
    item.catalogItemId = session->catalogItemId;
    item.title = session->title;

    fetchAssetManifest(item, [this, session](bool ok,
                                             const EpicManifest& manifest,
                                             const QList<MirrorEndpoint>& mirrors,
                                             const QByteArray& rawManifest,
                                             const QString& error) {
        if (session->isCancelled || !m_downloads.contains(session->appName)) return;
        if (!ok) {
            failDownloadSession(session, error.isEmpty() ? QStringLiteral("Failed to fetch Epic build manifest.") : error);
            return;
        }

        // Preserve previous manifest for delta-update file diffing before overwriting cache
        if (session->isUpdate) {
            QFile oldMf(manifestCachePath(session->appName));
            if (oldMf.exists() && oldMf.open(QIODevice::ReadOnly)) {
                session->hasPreviousManifest = EpicManifestParser::parse(oldMf.readAll(), session->previousManifest);
                oldMf.close();
            }
        }

        QFile mf(manifestCachePath(session->appName));
        if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            mf.write(rawManifest);
            mf.close();
        }
        if (!session->isDlc) {
            m_db->updateEpicLibrarySizes(session->appName, manifest.totalDownloadSize, manifest.totalInstallSize, manifest.buildVersion);
        }

        session->manifest = manifest;
        session->mirrors = mirrors;
        prepareAndStartSession(session);
    });
}

void EpicService::startDownload(const QString& appName,
                                const QString& installBaseDir,
                                const QString& runnerId,
                                const QString& prefixMode,
                                const QString& customPrefixName,
                                const QString& customPrefixLocation,
                                const QString& prefixArch,
                                const QStringList& selectedInstallTags,
                                const QStringList& selectedDlcAppNames) {
    if (appName.isEmpty() || m_downloads.contains(appName)) return;
    auto itemOpt = m_db->getEpicLibraryItem(appName);
    if (!itemOpt.has_value()) return;

    const EpicLibraryItem item = *itemOpt;
    QString cleanBase = installBaseDir.trimmed();
    if (cleanBase.startsWith(QStringLiteral("file://"))) {
        cleanBase = QUrl(cleanBase).toLocalFile();
    }
    if (cleanBase.isEmpty()) {
        cleanBase = m_settings->defaultEpicInstallLocation();
    }
    const QString targetDir = suggestInstallDirectory(cleanBase, item.title);
    QDir().mkpath(targetDir);

    auto session = std::make_shared<DownloadSession>();
    session->queueId = QStringLiteral("epic-dl-") + item.appName;
    session->appName = item.appName;
    session->namespaceId = item.namespaceId;
    session->catalogItemId = item.catalogItemId;
    session->title = item.title;
    session->coverPath = GameRecord::toFileUrlOrOriginal(!item.coverPath.isEmpty() ? item.coverPath : item.coverUrl);
    session->installDir = targetDir;
    session->runnerId = runnerId;
    session->prefixMode = prefixMode.isEmpty() ? QStringLiteral("default-prefix") : prefixMode;
    session->customPrefixName = customPrefixName;
    session->customPrefixLocation = customPrefixLocation;
    session->prefixArch = prefixArch.isEmpty() ? QStringLiteral("win64") : prefixArch;
    session->selectedInstallTags = selectedInstallTags;
    session->selectedDlcs = selectedDlcAppNames;
    session->stageText = QStringLiteral("Queued");
    session->speedTimer.start();
    session->uiEmitTimer.start();

    m_downloads.insert(appName, session);
    persistDownloadQueueItem(session);
    emit activeDownloadsChanged();

    if (m_dlMgr) {
        QPointer<EpicService> self(this);
        DownloadManager::ExternalAdapter adapter;
        adapter.startFn = [self, session]() {
            if (self) self->beginSessionExecution(session);
        };
        adapter.pauseFn = [self, appName]() {
            if (self) self->pauseDownload(appName);
        };
        adapter.resumeFn = [self, appName]() {
            if (self) self->resumeDownload(appName);
        };
        adapter.cancelFn = [self, appName](bool delPartial) {
            if (self) self->cancelDownload(appName, delPartial);
        };
        const bool startedImmediately = m_dlMgr->registerExternalTask(
            session->queueId,
            session->title,
            QStringLiteral("epic_install"),
            session->appName,
            session->coverPath,
            true,
            std::move(adapter),
            true);
        session->isQueued = !startedImmediately;
        emit downloadStateChanged(appName);
        return;
    }

    beginSessionExecution(session);
}

void EpicService::updateGame(const QString& gameId) {
    auto gOpt = m_db->getGame(gameId);
    if (!gOpt.has_value() || !gOpt->isEpic()) return;
    const GameRecord g = *gOpt;
    if (m_downloads.contains(g.epicAppName)) return;

    const QString targetDir = !g.epicInstallDir.isEmpty() ? g.epicInstallDir : g.workingDirectory;
    if (targetDir.isEmpty() || !QDir(targetDir).exists()) {
        emit operationStatus(QStringLiteral("Install directory does not exist for '%1'.").arg(g.title), true);
        return;
    }

    auto session = std::make_shared<DownloadSession>();
    session->queueId = QStringLiteral("epic-upd-") + g.epicAppName;
    session->appName = g.epicAppName;
    session->namespaceId = g.epicNamespace;
    session->catalogItemId = g.epicCatalogItemId;
    session->title = g.title + QStringLiteral(" (Update)");
    session->coverPath = GameRecord::toFileUrlOrOriginal(g.coverPath);
    session->installDir = targetDir;
    session->runnerId = g.runnerId;
    session->prefixMode = g.prefixId;
    session->existingGameId = g.id;
    session->isUpdate = true;
    session->selectedInstallTags = g.epicSelectedInstallTags;
    session->stageText = QStringLiteral("Queued update…");
    session->speedTimer.start();
    session->uiEmitTimer.start();

    m_downloads.insert(g.epicAppName, session);
    persistDownloadQueueItem(session);
    emit activeDownloadsChanged();

    if (m_dlMgr) {
        QPointer<EpicService> self(this);
        DownloadManager::ExternalAdapter adapter;
        adapter.startFn = [self, session]() { if (self) self->beginSessionExecution(session); };
        adapter.pauseFn = [self, app = g.epicAppName]() { if (self) self->pauseDownload(app); };
        adapter.resumeFn = [self, app = g.epicAppName]() { if (self) self->resumeDownload(app); };
        adapter.cancelFn = [self, app = g.epicAppName](bool) { if (self) self->cancelDownload(app, false); };
        const bool started = m_dlMgr->registerExternalTask(
            session->queueId, session->title, QStringLiteral("epic_update"),
            g.epicAppName, session->coverPath, true, std::move(adapter), true);
        session->isQueued = !started;
        emit downloadStateChanged(g.epicAppName);
        return;
    }

    beginSessionExecution(session);
}

void EpicService::installDlc(const QString& parentGameId, const QString& dlcAppName) {
    auto gOpt = m_db->getGame(parentGameId);
    if (!gOpt.has_value() || !gOpt->isEpic() || dlcAppName.isEmpty()) return;
    if (m_downloads.contains(dlcAppName)) return;

    const QList<EpicDlcItem> dlcs = m_db->getEpicDlcsForGame(gOpt->epicAppName);
    std::optional<EpicDlcItem> found;
    for (const EpicDlcItem& d : dlcs) {
        if (d.appName == dlcAppName) { found = d; break; }
    }
    if (!found.has_value()) {
        emit operationStatus(QStringLiteral("DLC '%1' not found in owned Epic DLCs.").arg(dlcAppName), true);
        return;
    }

    const QString targetDir = !gOpt->epicInstallDir.isEmpty() ? gOpt->epicInstallDir : gOpt->workingDirectory;
    QDir().mkpath(targetDir);

    auto session = std::make_shared<DownloadSession>();
    session->queueId = QStringLiteral("epic-dlc-") + dlcAppName;
    session->appName = found->appName;
    session->parentAppName = gOpt->epicAppName;
    session->namespaceId = found->namespaceId;
    session->catalogItemId = found->catalogItemId;
    session->title = QStringLiteral("%1 — %2").arg(gOpt->title, found->title);
    session->coverPath = GameRecord::toFileUrlOrOriginal(gOpt->coverPath);
    session->installDir = targetDir;
    session->existingGameId = gOpt->id;
    session->isDlc = true;
    session->stageText = QStringLiteral("Queued DLC…");
    session->speedTimer.start();
    session->uiEmitTimer.start();

    m_downloads.insert(dlcAppName, session);
    persistDownloadQueueItem(session);
    emit activeDownloadsChanged();

    if (m_dlMgr) {
        QPointer<EpicService> self(this);
        DownloadManager::ExternalAdapter adapter;
        adapter.startFn = [self, session]() { if (self) self->beginSessionExecution(session); };
        adapter.pauseFn = [self, dlcAppName]() { if (self) self->pauseDownload(dlcAppName); };
        adapter.resumeFn = [self, dlcAppName]() { if (self) self->resumeDownload(dlcAppName); };
        adapter.cancelFn = [self, dlcAppName](bool) { if (self) self->cancelDownload(dlcAppName, false); };
        const bool started = m_dlMgr->registerExternalTask(
            session->queueId, session->title, QStringLiteral("epic_dlc"),
            dlcAppName, session->coverPath, true, std::move(adapter), true);
        session->isQueued = !started;
        emit downloadStateChanged(dlcAppName);
        return;
    }
    beginSessionExecution(session);
}

void EpicService::runGamePrerequisites(const QString& gameId, bool force) {
    auto gOpt = m_db->getGame(gameId);
    if (!gOpt.has_value() || !gOpt->isEpic()) return;
    const GameRecord g = *gOpt;
    if (g.epicPrereqPath.trimmed().isEmpty()) {
        if (force) {
            emit operationStatus(QStringLiteral("No Epic prerequisites declared for '%1'.").arg(g.title), false);
        }
        return;
    }

    const QString installDir = !g.epicInstallDir.isEmpty() ? g.epicInstallDir : g.workingDirectory;
    const QString prereqExe = resolveExistingRelativePath(installDir, g.epicPrereqPath);
    if (!QFileInfo::exists(prereqExe)) {
        if (force) {
            emit operationStatus(QStringLiteral("Prerequisite installer not found: %1").arg(g.epicPrereqPath), true);
        }
        return;
    }

    const QString prefixId = g.prefixId.isEmpty() ? QStringLiteral("default-prefix") : g.prefixId;
    if (!force && m_prefixMgr && !g.epicPrereqIds.isEmpty() &&
        m_prefixMgr->arePrereqsInstalled(prefixId, g.epicPrereqIds)) {
        return;
    }

    auto runnerOpt = m_runnerMgr->resolveRunner(g.runnerId);
    if (!runnerOpt.has_value()) return;
    auto pfxOpt = m_db->getPrefix(prefixId);
    const QString prefixPath = pfxOpt.has_value()
                                   ? pfxOpt->path
                                   : (m_settings->defaultPrefixLocation() + QStringLiteral("/Default"));
    PrefixManager::ensureProtonSymlink(prefixPath);

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WINEPREFIX"), prefixPath);
    env.insert(QStringLiteral("WINEARCH"), pfxOpt.has_value() ? pfxOpt->arch : QStringLiteral("win64"));
    env.insert(QStringLiteral("WINEDEBUG"), QStringLiteral("-all"));
    env.insert(QStringLiteral("WINEDLLOVERRIDES"), QStringLiteral("mscoree,mshtml="));

    QString program;
    QStringList args;
    const QString umuBin = RunnerManager::resolveUmuRunPath();
    const bool useUmu = runnerOpt->isProton() && m_settings->umuDefault() && !umuBin.isEmpty();
    if (useUmu) {
        env.insert(QStringLiteral("PROTONPATH"), runnerOpt->path);
        env.insert(QStringLiteral("GAMEID"), m_umuResolver ? m_umuResolver->resolveGameIdSync(g) : QStringLiteral("umu-default"));
        env.insert(QStringLiteral("STORE"), QStringLiteral("egs"));
        env.insert(QStringLiteral("PROTON_VERB"), QStringLiteral("waitforexitandrun"));
        program = umuBin;
        args << prereqExe;
    } else if (runnerOpt->isProton()) {
        env.insert(QStringLiteral("STEAM_COMPAT_DATA_PATH"), prefixPath);
        env.insert(QStringLiteral("STEAM_COMPAT_CLIENT_INSTALL_PATH"), AppSettings::dataDir());
        program = runnerOpt->binaryPath;
        args << QStringLiteral("waitforexitandrun") << prereqExe;
    } else {
        program = runnerOpt->binaryPath;
        args << prereqExe;
    }
    if (!g.epicPrereqArgs.trimmed().isEmpty()) {
        args.append(QProcess::splitCommand(g.epicPrereqArgs.trimmed()));
    }

    emit operationStatus(
        QStringLiteral("Installing prerequisite '%1' for %2…")
            .arg(g.epicPrereqName.isEmpty() ? QFileInfo(prereqExe).fileName() : g.epicPrereqName, g.title),
        false);

    auto* proc = new QProcess(this);
    proc->setProcessEnvironment(env);
    proc->setWorkingDirectory(QFileInfo(prereqExe).absolutePath());
    connect(proc, &QProcess::finished, this, [this, proc, gameId, prefixId, g](int exitCode, QProcess::ExitStatus) {
        proc->deleteLater();
        // Exit code 0 or 3010 (ERROR_SUCCESS_REBOOT_REQUIRED) indicates success on Windows installers
        const bool ok = (exitCode == 0 || exitCode == 3010);
        if (ok) {
            if (m_prefixMgr && !g.epicPrereqIds.isEmpty()) {
                m_prefixMgr->markPrereqsInstalled(prefixId, g.epicPrereqIds);
            }
            if (auto fresh = m_db->getGame(gameId); fresh.has_value()) {
                GameRecord upd = *fresh;
                upd.epicPrereqCompleted = true;
                m_db->saveGame(upd);
            }
        }
        const QString msg = ok
                                ? QStringLiteral("Prerequisites installed for '%1'.").arg(g.title)
                                : QStringLiteral("Prerequisite installer for '%1' exited with code %2.").arg(g.title).arg(exitCode);
        emit prerequisitesFinished(gameId, ok, msg);
        emit operationStatus(msg, !ok);
    });
    proc->start(program, args);
}

void EpicService::prepareAndStartSession(const std::shared_ptr<DownloadSession>& session) {
    session->stageText = QStringLiteral("Checking files…");
    emit downloadStateChanged(session->appName);
    notifyDownloadManagerProgress(session);

    const QSet<QString> savedCompleted = loadResumeState(session->installDir, session->manifest.buildVersion);

    // Filter files by selectedInstallTags & handle delta-update diffing
    session->activeFiles.clear();
    session->filesToRemoveOnFinalize.clear();
    if (session->isUpdate && session->hasPreviousManifest) {
        const EpicManifestDiff diff = EpicManifestParser::diffManifests(
            session->previousManifest, session->manifest, session->selectedInstallTags);
        session->filesToRemoveOnFinalize = diff.removedFiles;
        // Include modified/new files plus any "unchanged" file that is missing or wrong size on disk
        for (const EpicFileManifest& fm : diff.modifiedOrNewFiles) {
            session->activeFiles.append(fm);
        }
        for (const EpicFileManifest& fm : diff.unchangedFiles) {
            if (!fm.symlinkTarget.isEmpty()) continue;
            const QFileInfo fi(QDir(session->installDir).filePath(fm.filename));
            if (!fi.exists() || fi.size() != fm.fileSize) {
                session->activeFiles.append(fm);
            }
        }
    } else {
        for (const EpicFileManifest& fm : session->manifest.files) {
            if (EpicManifest::fileMatchesTags(fm, session->selectedInstallTags)) {
                session->activeFiles.append(fm);
            }
        }
    }

    // Build unique chunk work list & pre-check completed chunks / directories
    session->chunkJobs.clear();
    session->pendingChunks.clear();
    session->completedChunks.clear();
    session->fileMutexes.clear();
    session->totalDownloadBytes = 0;
    session->downloadedBytes = 0;
    session->totalInstallBytes = 0;

    for (int fIdx = 0; fIdx < session->activeFiles.size(); ++fIdx) {
        const EpicFileManifest& fm = session->activeFiles.at(fIdx);
        session->fileMutexes.insert(fIdx, std::make_shared<QMutex>());
        session->totalInstallBytes += fm.fileSize;

        const QString fullPath = QDir(session->installDir).filePath(fm.filename);
        QDir().mkpath(QFileInfo(fullPath).absolutePath());

        if (!fm.symlinkTarget.isEmpty()) continue;

        qint64 currentOffset = 0;
        for (const EpicChunkPart& part : fm.chunkParts) {
            const EpicChunkInfo* cInfo = session->manifest.findChunk(part.chunkGuid);
            if (!cInfo) {
                currentOffset += part.size;
                continue;
            }
            if (!session->chunkJobs.contains(part.chunkGuid)) {
                ChunkJob job;
                job.guid = part.chunkGuid;
                job.info = *cInfo;
                session->chunkJobs.insert(part.chunkGuid, job);
            }
            session->chunkJobs[part.chunkGuid].targets.append({fIdx, currentOffset, part.offset, part.size});
            currentOffset += part.size;
        }
    }

    for (auto it = session->chunkJobs.constBegin(); it != session->chunkJobs.constEnd(); ++it) {
        const qint64 cSize = qMax<qint64>(1, it.value().info.fileSize);
        session->totalDownloadBytes += cSize;
        if (savedCompleted.contains(it.key()) && !session->verifyOnly && !session->isUpdate) {
            session->completedChunks.insert(it.key());
            session->downloadedBytes += cSize;
        } else {
            session->pendingChunks.enqueue(it.key());
        }
    }

    if (session->verifyOnly) {
        session->isVerifying = true;
        session->stageText = QStringLiteral("Verifying existing files…");
        emit downloadStateChanged(session->appName);
        notifyDownloadManagerProgress(session);

        // Background pass: verify existing files via SHA-1 and skip chunks for intact files
        auto* watcher = new QFutureWatcher<QSet<QString>>(this);
        const QString installDir = session->installDir;
        const QList<EpicFileManifest> verifyFiles = session->activeFiles;
        connect(watcher, &QFutureWatcher<QSet<QString>>::finished, this, [this, watcher, session]() {
            const QSet<QString> badChunks = watcher->result();
            watcher->deleteLater();
            if (session->isCancelled || !m_downloads.contains(session->appName)) return;

            session->isVerifying = false;
            session->pendingChunks.clear();
            session->completedChunks.clear();
            session->downloadedBytes = 0;

            for (auto it = session->chunkJobs.constBegin(); it != session->chunkJobs.constEnd(); ++it) {
                const qint64 cSize = qMax<qint64>(1, it.value().info.fileSize);
                if (badChunks.contains(it.key())) {
                    session->pendingChunks.enqueue(it.key());
                } else {
                    session->completedChunks.insert(it.key());
                    session->downloadedBytes += cSize;
                }
            }

            if (session->pendingChunks.isEmpty()) {
                finalizeDownloadSession(session);
            } else {
                session->stageText = QStringLiteral("Repairing %1 chunks…").arg(session->pendingChunks.size());
                emit downloadStateChanged(session->appName);
                notifyDownloadManagerProgress(session);
                pumpDownloadChunks(session);
            }
        });

        watcher->setFuture(QtConcurrent::run([installDir, verifyFiles]() -> QSet<QString> {
            QSet<QString> bad;
            for (const EpicFileManifest& fm : verifyFiles) {
                if (!fm.symlinkTarget.isEmpty()) continue;
                const QString path = QDir(installDir).filePath(fm.filename);
                QFile f(path);
                bool intact = false;
                if (f.exists() && f.size() == fm.fileSize && f.open(QIODevice::ReadOnly)) {
                    QCryptographicHash hash(QCryptographicHash::Sha1);
                    if (hash.addData(&f)) {
                        intact = (fm.shaHash.isEmpty() || hash.result() == fm.shaHash);
                    }
                    f.close();
                }
                if (!intact) {
                    for (const EpicChunkPart& part : fm.chunkParts) {
                        bad.insert(part.chunkGuid);
                    }
                }
            }
            return bad;
        }));
        return;
    }

    if (session->pendingChunks.isEmpty()) {
        finalizeDownloadSession(session);
        return;
    }

    session->stageText = session->isUpdate ? QStringLiteral("Updating…") : QStringLiteral("Downloading…");
    session->progress = session->totalDownloadBytes > 0
                            ? (static_cast<double>(session->downloadedBytes) * 100.0 / static_cast<double>(session->totalDownloadBytes))
                            : 0.0;
    emit downloadStateChanged(session->appName);
    notifyDownloadManagerProgress(session);
    pumpDownloadChunks(session);
}

void EpicService::pumpDownloadChunks(const std::shared_ptr<DownloadSession>& session) {
    if (!session || session->isCancelled || session->isPaused || session->isQueued) return;
    if (session->pendingChunks.isEmpty() && session->inFlightChunks.isEmpty() && session->activeWorkers == 0) {
        finalizeDownloadSession(session);
        return;
    }
    const int maxWorkers = m_dlMgr ? m_dlMgr->maxConcurrentChunkWorkers() : kMaxConcurrentChunks;
    while (!session->isPaused && !session->isCancelled &&
           session->inFlightChunks.size() < maxWorkers &&
           !session->pendingChunks.isEmpty()) {
        const QString nextGuid = session->pendingChunks.head();
        const qint64 estBytes = qMax<qint64>(16384, session->chunkJobs.value(nextGuid).info.fileSize);
        if (m_dlMgr && m_dlMgr->speedLimitKBps() > 0 && !m_dlMgr->tryConsumeBandwidthBytes(estBytes)) {
            const qint64 waitMs = m_dlMgr->msUntilBandwidthAvailable(estBytes);
            QPointer<EpicService> self(this);
            QTimer::singleShot(static_cast<int>(waitMs), this, [self, session]() {
                if (self) self->pumpDownloadChunks(session);
            });
            break;
        }
        const QString guid = session->pendingChunks.dequeue();
        startChunkRequest(session, guid);
    }
}

void EpicService::startChunkRequest(const std::shared_ptr<DownloadSession>& session, const QString& chunkGuid) {
    if (!session || session->isCancelled || session->isPaused) return;
    if (session->mirrors.isEmpty()) {
        failDownloadSession(session, QStringLiteral("No CDN mirrors available for download."));
        return;
    }

    const ChunkJob& job = session->chunkJobs[chunkGuid];
    const MirrorEndpoint& mirror = session->mirrors.at(job.mirrorIndex % session->mirrors.size());
    const QString relChunk = job.info.relativeChunkPath(session->manifest.chunksSubdir());

    QUrl url(mirror.baseUrl + QLatin1Char('/') + relChunk);
    if (!mirror.queryParams.isEmpty()) {
        QUrlQuery q(url);
        for (const auto& qp : mirror.queryParams) {
            q.addQueryItem(qp.first, qp.second);
        }
        url.setQuery(q);
    }

    QNetworkRequest req(url);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));

    session->inFlightChunks.insert(chunkGuid);
    QNetworkReply* reply = m_nam.get(req);
    if (m_dlMgr && m_dlMgr->speedLimitKBps() > 0) {
        reply->setReadBufferSize(m_dlMgr->recommendedReadBufferSize(m_dlMgr->maxConcurrentChunkWorkers()));
    }
    session->activeReplies.append(reply);

    connect(reply, &QNetworkReply::finished, this, [this, session, chunkGuid, reply]() {
        session->activeReplies.removeAll(reply);
        const QNetworkReply::NetworkError netErr = reply->error();
        const QString errStr = reply->errorString();
        const QByteArray rawChunk = (netErr == QNetworkReply::NoError) ? safeReadReply(reply) : QByteArray();
        reply->deleteLater();

        if (session->isCancelled || !m_downloads.contains(session->appName)) {
            session->inFlightChunks.remove(chunkGuid);
            return;
        }
        if (session->isPaused) {
            session->inFlightChunks.remove(chunkGuid);
            session->pendingChunks.prepend(chunkGuid);
            return;
        }

        if (netErr != QNetworkReply::NoError || rawChunk.isEmpty()) {
            session->inFlightChunks.remove(chunkGuid);
            ChunkJob& jobRef = session->chunkJobs[chunkGuid];
            if (jobRef.retries < kMaxChunkRetries) {
                ++jobRef.retries;
                ++jobRef.mirrorIndex;
                session->pendingChunks.enqueue(chunkGuid);
                pumpDownloadChunks(session);
            } else {
                failDownloadSession(session, QStringLiteral("Chunk download failed: %1").arg(errStr));
            }
            return;
        }

        const ChunkJob jobCopy = session->chunkJobs.value(chunkGuid);
        const QString installDir = session->installDir;
        const auto files = session->activeFiles;
        const auto fileMutexes = session->fileMutexes;
        ++session->activeWorkers;

        QPointer<EpicService> self(this);
        QThreadPool::globalInstance()->start([self, session, chunkGuid, rawChunk, jobCopy, installDir, files, fileMutexes]() {
            QByteArray uncompressed;
            QString err;
            bool ok = EpicManifestParser::decompressChunk(rawChunk, jobCopy.info.shaHash, uncompressed, &err);
            if (ok) {
                for (const ChunkTargetSlice& slice : jobCopy.targets) {
                    if (slice.fileIndex < 0 || slice.fileIndex >= files.size()) continue;
                    if (static_cast<qint64>(slice.chunkOffset) + static_cast<qint64>(slice.size) > uncompressed.size()) {
                        ok = false;
                        err = QStringLiteral("Chunk slice out of bounds");
                        break;
                    }
                    const QString targetPath = QDir(installDir).filePath(files.at(slice.fileIndex).filename);
                    auto mtx = fileMutexes.value(slice.fileIndex);
                    QMutexLocker lock(mtx.get());
                    QFile f(targetPath);
                    if (!f.open(QIODevice::ReadWrite)) {
                        ok = false;
                        err = QStringLiteral("Cannot open %1 for writing").arg(targetPath);
                        break;
                    }
                    if (!f.seek(slice.fileOffset) ||
                        f.write(uncompressed.constData() + slice.chunkOffset, slice.size) != static_cast<qint64>(slice.size)) {
                        ok = false;
                        err = QStringLiteral("Disk write failed for %1").arg(targetPath);
                        f.close();
                        break;
                    }
                    f.close();
                }
            }

            if (self) {
                QMetaObject::invokeMethod(self, [self, session, chunkGuid, ok, err]() {
                    if (self) self->onChunkWriteFinished(session, chunkGuid, ok, err);
                }, Qt::QueuedConnection);
            }
        });
    });
}

void EpicService::onChunkWriteFinished(const std::shared_ptr<DownloadSession>& session,
                                       const QString& chunkGuid,
                                       bool ok,
                                       const QString& error) {
    --session->activeWorkers;
    session->inFlightChunks.remove(chunkGuid);

    if (session->isCancelled || !m_downloads.contains(session->appName)) return;

    if (!ok) {
        ChunkJob& jobRef = session->chunkJobs[chunkGuid];
        if (jobRef.retries < kMaxChunkRetries) {
            ++jobRef.retries;
            ++jobRef.mirrorIndex;
            session->pendingChunks.enqueue(chunkGuid);
            pumpDownloadChunks(session);
            return;
        }
        failDownloadSession(session, error);
        return;
    }

    const qint64 cSize = qMax<qint64>(1, session->chunkJobs.value(chunkGuid).info.fileSize);
    session->completedChunks.insert(chunkGuid);
    session->downloadedBytes += cSize;
    session->sessionBytes += cSize;
    ++session->chunksSinceSave;

    if (session->chunksSinceSave >= 25) {
        session->chunksSinceSave = 0;
        saveResumeState(session);
    }

    const qint64 elapsedMs = qMax<qint64>(1, session->speedTimer.elapsed());
    const double speedBps = (static_cast<double>(session->sessionBytes) * 1000.0) / static_cast<double>(elapsedMs);
    session->speedBps = speedBps;
    session->speedText = QStringLiteral("%1/s").arg(DownloadManager::formatBytes(static_cast<qint64>(speedBps)));

    const qint64 remBytes = qMax<qint64>(0, session->totalDownloadBytes - session->downloadedBytes);
    if (speedBps > 1024.0 && remBytes > 0) {
        const qint64 remSecs = static_cast<qint64>(remBytes / speedBps);
        if (remSecs < 60) session->etaText = QStringLiteral("%1s left").arg(remSecs);
        else if (remSecs < 3600) session->etaText = QStringLiteral("%1m %2s left").arg(remSecs / 60).arg(remSecs % 60);
        else session->etaText = QStringLiteral("%1h %2m left").arg(remSecs / 3600).arg((remSecs % 3600) / 60);
    } else {
        session->etaText = session->speedText;
    }

    session->progress = session->totalDownloadBytes > 0
                            ? qBound(0.0, static_cast<double>(session->downloadedBytes) * 100.0 / static_cast<double>(session->totalDownloadBytes), 99.5)
                            : 0.0;
    session->stageText = session->isUpdate ? QStringLiteral("Updating…") : QStringLiteral("Downloading…");

    if (session->uiEmitTimer.elapsed() >= 150 || session->pendingChunks.isEmpty()) {
        session->uiEmitTimer.restart();
        emit downloadStateChanged(session->appName);
        notifyDownloadManagerProgress(session);
        if (session->isEosOverlay) {
            emit eosOverlayChanged();
        }
    }

    pumpDownloadChunks(session);
}

void EpicService::finalizeDownloadSession(const std::shared_ptr<DownloadSession>& session) {
    if (session->isCancelled || !m_downloads.contains(session->appName)) return;

    session->stageText = QStringLiteral("Finalizing installation…");
    session->progress = 99.8;
    emit downloadStateChanged(session->appName);
    notifyDownloadManagerProgress(session);

    // Apply symlinks & executable permissions for active files
    for (const EpicFileManifest& fm : session->activeFiles) {
        const QString targetPath = QDir(session->installDir).filePath(fm.filename);
        if (!fm.symlinkTarget.isEmpty()) {
            QFile::remove(targetPath);
            QFile::link(fm.symlinkTarget, targetPath);
            continue;
        }
        if (fm.isExecutable() && QFileInfo::exists(targetPath)) {
            const QFileDevice::Permissions perms = QFile::permissions(targetPath);
            QFile::setPermissions(targetPath, perms | QFileDevice::ExeUser | QFileDevice::ExeGroup | QFileDevice::ExeOther);
        }
    }

    // Prune obsolete files removed between old & new manifest during delta update
    for (const QString& relRemove : session->filesToRemoveOnFinalize) {
        const QString absRemove = QDir(session->installDir).filePath(relRemove);
        if (QFileInfo::exists(absRemove)) {
            QFile::remove(absRemove);
        }
    }

    cleanupSessionFiles(session);

    // Resolve executable path (with case-insensitive fallback for Linux filesystems)
    QString exePath;
    if (!session->manifest.launchExe.isEmpty()) {
        exePath = resolveExistingRelativePath(session->installDir, session->manifest.launchExe);
    }
    if (exePath.isEmpty()) {
        QDirIterator it(session->installDir, {QStringLiteral("*.exe")}, QDir::Files, QDirIterator::Subdirectories);
        if (it.hasNext()) {
            exePath = it.next();
        }
    }

    const QString appName = session->appName;
    const QString queueId = session->queueId;
    const QString gameId = session->existingGameId;
    const QString buildVer = session->manifest.buildVersion;
    const QString launchArgs = session->manifest.launchCommand;
    const QString installDir = session->installDir;
    const QString runnerId = session->runnerId;
    const QString prefixMode = session->prefixMode;
    const QString customPfxName = session->customPrefixName;
    const QString customPfxLoc = session->customPrefixLocation;
    const QString pfxArch = session->prefixArch;
    const QStringList selectedTags = session->selectedInstallTags;
    const QStringList selectedDlcs = session->selectedDlcs;

    m_downloads.remove(appName);
    removePersistedDownloadQueueItem(queueId);
    emit activeDownloadsChanged();

    if (session->isEosOverlay) {
        QFile vf(installDir + QStringLiteral("/.tsuki_eos_version"));
        if (vf.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            vf.write(buildVer.toUtf8());
            vf.close();
        }
        if (m_dlMgr && !queueId.isEmpty()) {
            m_dlMgr->finishExternalTask(queueId, true, QStringLiteral("Installed (%1)").arg(buildVer), QString(), installDir);
        }
        emit downloadStateChanged(appName);
        emit eosOverlayChanged();
        emit operationStatus(QStringLiteral("Epic Online Services Overlay installed (%1).").arg(buildVer), false);
        return;
    }

    if (session->isDlc) {
        m_db->setEpicDlcInstalled(appName, true);
        if (m_dlMgr && !queueId.isEmpty()) {
            m_dlMgr->finishExternalTask(queueId, true, QStringLiteral("DLC Installed"), gameId, installDir);
        }
        emit downloadStateChanged(appName);
        emit downloadFinished(appName, gameId);
        emit operationStatus(QStringLiteral("Installed DLC '%1'.").arg(session->title), false);
        return;
    }

    QString registeredId = gameId;
    if (m_gameMgr) {
        if ((session->verifyOnly || session->isUpdate) && !gameId.isEmpty()) {
            if (auto gOpt = m_db->getGame(gameId); gOpt.has_value()) {
                GameRecord updated = *gOpt;
                updated.epicBuildVersion = buildVer;
                if (!session->manifest.prereqPath.isEmpty()) {
                    updated.epicPrereqName = session->manifest.prereqName;
                    updated.epicPrereqPath = session->manifest.prereqPath;
                    updated.epicPrereqArgs = session->manifest.prereqArgs;
                    updated.epicPrereqIds = session->manifest.prereqIds;
                }
                if ((updated.executablePath.isEmpty() || session->isUpdate) && !exePath.isEmpty() && QFileInfo::exists(exePath)) {
                    updated.executablePath = exePath;
                    updated.workingDirectory = QFileInfo(exePath).absolutePath();
                }
                m_db->saveGame(updated);
                m_gameMgr->model()->reload();
                emit m_gameMgr->gamesChanged();
            }
            if (session->isUpdate) {
                m_appsWithUpdates.remove(appName);
                m_latestBuildVersions.insert(appName, buildVer);
                emit updatesChanged();
            }
        } else {
            auto libItem = m_db->getEpicLibraryItem(appName);
            registeredId = m_gameMgr->registerEpicGame(
                appName,
                session->namespaceId,
                session->catalogItemId,
                libItem.has_value() ? libItem->title : session->title,
                exePath,
                installDir,
                launchArgs,
                buildVer,
                runnerId,
                prefixMode,
                customPfxName,
                customPfxLoc,
                pfxArch,
                libItem.has_value() ? libItem->coverPath : QString(),
                libItem.has_value() ? libItem->bannerPath : QString(),
                libItem.has_value() ? libItem->logoPath : QString(),
                session->importedInPlace);

            // Persist prereq metadata, selected install tags/DLCs & cloud save metadata on GameRecord
            if (!registeredId.isEmpty()) {
                if (auto gOpt = m_db->getGame(registeredId); gOpt.has_value()) {
                    GameRecord updated = *gOpt;
                    updated.epicPrereqName = session->manifest.prereqName;
                    updated.epicPrereqPath = session->manifest.prereqPath;
                    updated.epicPrereqArgs = session->manifest.prereqArgs;
                    updated.epicPrereqIds = session->manifest.prereqIds;
                    updated.epicSelectedInstallTags = selectedTags;
                    updated.epicSelectedDlcs = selectedDlcs;
                    if (libItem.has_value()) {
                        if (updated.epicCloudSaveFolder.isEmpty()) updated.epicCloudSaveFolder = libItem->cloudSaveFolder;
                        if (updated.epicCloudIncludeList.isEmpty()) updated.epicCloudIncludeList = libItem->cloudIncludeList;
                        if (updated.epicCloudExcludeList.isEmpty()) updated.epicCloudExcludeList = libItem->cloudExcludeList;
                    }
                    m_db->saveGame(updated);
                }
                if (m_umuResolver) {
                    m_umuResolver->lookupAndCache(QStringLiteral("egs"), appName);
                }
            }
        }
    }

    const QString doneMsg = session->verifyOnly
                                ? QStringLiteral("Verified '%1' files successfully.").arg(session->title)
                                : (session->isUpdate
                                       ? QStringLiteral("Updated '%1' to build %2.").arg(session->title, buildVer)
                                       : QStringLiteral("Downloaded '%1' and added to Library.").arg(session->title));
    if (m_dlMgr && !queueId.isEmpty()) {
        m_dlMgr->finishExternalTask(queueId, true, doneMsg, registeredId, installDir);
    }

    m_model->reload();
    emit downloadStateChanged(appName);
    emit downloadFinished(appName, registeredId);
    emit operationStatus(doneMsg, false);

    // Auto-run declared Epic prerequisites for fresh installs / updates
    if (!session->verifyOnly && !registeredId.isEmpty() && !session->manifest.prereqPath.isEmpty()) {
        runGamePrerequisites(registeredId, false);
    }

    // Queue any user-selected DLCs to install right after the base game
    if (!registeredId.isEmpty() && !selectedDlcs.isEmpty()) {
        for (const QString& dlcApp : selectedDlcs) {
            installDlc(registeredId, dlcApp);
        }
    }
}

QVariantMap EpicService::inspectImportSource(const QString& appName,
                                             const QString& sourceDir,
                                             const QString& targetBaseDir) const {
    QVariantMap res;
    const QString cleanSrc = normalizeLocalPath(sourceDir);
    res[QStringLiteral("valid")] = false;
    res[QStringLiteral("exists")] = false;
    res[QStringLiteral("fileCount")] = 0;
    res[QStringLiteral("totalBytes")] = 0.0;
    res[QStringLiteral("totalSizeFormatted")] = QStringLiteral("0 B");
    res[QStringLiteral("suggestedExe")] = QString();
    res[QStringLiteral("hasEpicMetadata")] = false;
    res[QStringLiteral("sameFilesystem")] = false;
    res[QStringLiteral("sameDestination")] = false;

    if (cleanSrc.isEmpty() || !QDir(cleanSrc).exists()) {
        res[QStringLiteral("error")] = cleanSrc.isEmpty() ? QStringLiteral("Select an existing game folder.") : QStringLiteral("Folder does not exist.");
        return res;
    }

    res[QStringLiteral("exists")] = true;
    qint64 totalBytes = 0;
    int fileCount = 0;
    bool hasEgstore = QDir(cleanSrc + QStringLiteral("/.egstore")).exists();

    QDirIterator it(cleanSrc, QDir::Files | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        ++fileCount;
        totalBytes += it.fileInfo().size();
    }

    QString manifestLaunchExe;
    if (!appName.isEmpty()) {
        QFile mf(manifestCachePath(appName));
        if (mf.exists() && mf.open(QIODevice::ReadOnly)) {
            EpicManifest parsed;
            if (EpicManifestParser::parse(mf.readAll(), parsed)) {
                manifestLaunchExe = parsed.launchExe;
            }
        }
    }

    const QString suggestedExe = resolveImportedExecutable(cleanSrc, manifestLaunchExe, QString(), cleanSrc);
    auto itemOpt = m_db->getEpicLibraryItem(appName);
    const QString title = itemOpt.has_value() ? itemOpt->title : appName;
    const QString destDir = suggestInstallDirectory(targetBaseDir, title);

    QString destCheckDir = QFileInfo(destDir).absolutePath();
    QDir dCheck(destCheckDir);
    while (!dCheck.exists() && !dCheck.isRoot()) {
        if (!dCheck.cdUp()) break;
    }
    const QStorageInfo srcVol(cleanSrc);
    const QStorageInfo dstVol(dCheck.exists() ? dCheck.absolutePath() : QDir::homePath());
    const bool sameFs = srcVol.isValid() && dstVol.isValid() && !srcVol.device().isEmpty() && srcVol.device() == dstVol.device();
    const bool sameDest = (QDir::cleanPath(destDir) == cleanSrc);

    res[QStringLiteral("fileCount")] = fileCount;
    res[QStringLiteral("totalBytes")] = static_cast<double>(totalBytes);
    res[QStringLiteral("totalSizeFormatted")] = DownloadManager::formatBytes(totalBytes);
    res[QStringLiteral("suggestedExe")] = suggestedExe;
    res[QStringLiteral("hasEpicMetadata")] = hasEgstore;
    res[QStringLiteral("sameFilesystem")] = sameFs;
    res[QStringLiteral("sameDestination")] = sameDest;
    res[QStringLiteral("resolvedDestination")] = destDir;
    res[QStringLiteral("valid")] = (fileCount > 0 && !suggestedExe.isEmpty());
    if (fileCount == 0) {
        res[QStringLiteral("error")] = QStringLiteral("Folder contains no files.");
    } else if (suggestedExe.isEmpty()) {
        res[QStringLiteral("error")] = QStringLiteral("No Windows .exe executable detected. You can select one manually below.");
    } else {
        res[QStringLiteral("error")] = QString();
    }
    return res;
}

void EpicService::importGame(const QString& appName,
                             const QString& sourceDir,
                             const QString& transferMode,
                             const QString& targetBaseDir,
                             const QString& runnerId,
                             const QString& prefixMode,
                             const QString& customPrefixName,
                             const QString& customPrefixLocation,
                             const QString& prefixArch,
                             bool verifyAfterImport,
                             const QString& customExecutable) {
    if (appName.isEmpty() || m_downloads.contains(appName)) return;
    auto itemOpt = m_db->getEpicLibraryItem(appName);
    if (!itemOpt.has_value()) {
        emit operationStatus(QStringLiteral("Game metadata not found in Epic library cache."), true);
        return;
    }
    const EpicLibraryItem item = *itemOpt;

    const QString cleanSrc = normalizeLocalPath(sourceDir);
    if (cleanSrc.isEmpty() || !QDir(cleanSrc).exists()) {
        emit operationStatus(QStringLiteral("Source folder does not exist: %1").arg(sourceDir), true);
        return;
    }

    QString mode = transferMode.trimmed().toLower();
    if (mode != QLatin1String("move") && mode != QLatin1String("in_place")) {
        mode = QStringLiteral("copy");
    }

    QString targetDir = cleanSrc;
    bool inPlace = (mode == QLatin1String("in_place"));
    if (!inPlace) {
        targetDir = suggestInstallDirectory(targetBaseDir, item.title);
        if (QDir::cleanPath(targetDir) == cleanSrc) {
            // Source folder is already in the chosen destination directory; register without duplicating/deleting self.
            mode = QStringLiteral("in_place");
            inPlace = false;
        }
    }

    auto session = std::make_shared<DownloadSession>();
    session->appName = item.appName;
    session->namespaceId = item.namespaceId;
    session->catalogItemId = item.catalogItemId;
    session->title = item.title;
    session->installDir = targetDir;
    session->runnerId = runnerId;
    session->prefixMode = prefixMode.isEmpty() ? QStringLiteral("default-prefix") : prefixMode;
    session->customPrefixName = customPrefixName;
    session->customPrefixLocation = customPrefixLocation;
    session->prefixArch = prefixArch.isEmpty() ? QStringLiteral("win64") : prefixArch;
    session->isImporting = true;
    session->verifyAfterImport = verifyAfterImport;
    session->importedInPlace = inPlace;
    session->transferMode = mode;
    session->importSourceDir = cleanSrc;
    session->explicitExecutable = normalizeLocalPath(customExecutable);
    session->stageText = (mode == QLatin1String("move"))
                             ? QStringLiteral("Moving files…")
                             : (mode == QLatin1String("copy") ? QStringLiteral("Copying files…")
                                                              : QStringLiteral("Preparing import…"));
    session->speedTimer.start();
    session->uiEmitTimer.start();

    m_downloads.insert(appName, session);
    persistDownloadQueueItem(session);
    emit activeDownloadsChanged();
    emit downloadStateChanged(appName);

    if (mode == QLatin1String("in_place")) {
        session->progress = 100.0;
        completeImportSession(session);
        return;
    }

    QPointer<EpicService> self(this);
    QThreadPool::globalInstance()->start([self, session, cleanSrc, targetDir, mode]() {
        // Fast path: same-filesystem atomic directory move when destination does not already exist
        if (mode == QLatin1String("move") && !QFileInfo::exists(targetDir)) {
            const QString destParent = QFileInfo(targetDir).absolutePath();
            QDir().mkpath(destParent);
            const QStorageInfo srcVol(cleanSrc);
            const QStorageInfo dstVol(destParent);
            const bool sameFs = srcVol.isValid() && dstVol.isValid() && !srcVol.device().isEmpty() && srcVol.device() == dstVol.device();
            if (sameFs && QDir().rename(cleanSrc, targetDir)) {
                QMetaObject::invokeMethod(qApp, [self, session]() {
                    if (!self) return;
                    if (session->isCancelled || !self->m_downloads.contains(session->appName)) return;
                    session->progress = 100.0;
                    self->completeImportSession(session);
                }, Qt::QueuedConnection);
                return;
            }
        }

        // Enumerate source files and symlinks
        struct EntryItem {
            QString relPath;
            QString absPath;
            bool isSymlink = false;
            QString symTarget;
            qint64 size = 0;
            QFileDevice::Permissions perms;
        };

        QList<EntryItem> entries;
        qint64 totalBytes = 0;

        QDirIterator dirIt(cleanSrc, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        QStringList subDirs;
        while (dirIt.hasNext()) {
            subDirs.append(QDir(cleanSrc).relativeFilePath(dirIt.next()));
        }

        QDirIterator fileIt(cleanSrc, QDir::Files | QDir::System | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (fileIt.hasNext()) {
            if (session->isCancelled) break;
            fileIt.next();
            const QFileInfo fi = fileIt.fileInfo();
            EntryItem e;
            e.absPath = fi.absoluteFilePath();
            e.relPath = QDir(cleanSrc).relativeFilePath(e.absPath);
            e.isSymlink = fi.isSymLink();
            if (e.isSymlink) {
                e.symTarget = fi.symLinkTarget();
            } else {
                e.size = fi.size();
                e.perms = fi.permissions();
                totalBytes += e.size;
            }
            entries.append(e);
        }

        if (session->isCancelled) {
            if (session->deleteOnCancel && targetDir != cleanSrc) {
                QDir(targetDir).removeRecursively();
            }
            return;
        }

        QString errMsg;
        if (!QDir().mkpath(targetDir)) {
            errMsg = QStringLiteral("Failed to create destination folder: %1").arg(targetDir);
        } else {
            // Check free space at destination
            const qint64 freeBytes = QStorageInfo(targetDir).bytesAvailable();
            if (freeBytes >= 0 && totalBytes > freeBytes) {
                errMsg = QStringLiteral("Insufficient free disk space (%1 required, %2 available).")
                             .arg(DownloadManager::formatBytes(totalBytes), DownloadManager::formatBytes(freeBytes));
            }
        }

        if (errMsg.isEmpty()) {
            for (const QString& sd : subDirs) {
                QDir(targetDir).mkpath(sd);
            }
            session->totalDownloadBytes = totalBytes;
            session->totalInstallBytes = totalBytes;
            QMetaObject::invokeMethod(qApp, [self, session]() {
                if (!self || session->isCancelled) return;
                emit self->downloadStateChanged(session->appName);
            }, Qt::QueuedConnection);

            qint64 copiedBytes = 0;
            QElapsedTimer emitTimer;
            emitTimer.start();
            constexpr qint64 kCopyBufSize = 1024 * 1024;
            QByteArray buffer;
            buffer.resize(kCopyBufSize);

            for (const EntryItem& e : entries) {
                if (session->isCancelled) break;
                const QString dstPath = QDir(targetDir).filePath(e.relPath);
                QDir().mkpath(QFileInfo(dstPath).absolutePath());

                if (e.isSymlink) {
                    QFile::remove(dstPath);
                    QFile::link(e.symTarget, dstPath);
                    continue;
                }

                QFile srcFile(e.absPath);
                if (!srcFile.open(QIODevice::ReadOnly)) {
                    errMsg = QStringLiteral("Cannot read source file: %1").arg(e.relPath);
                    break;
                }
                QFile dstFile(dstPath);
                if (!dstFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                    errMsg = QStringLiteral("Cannot write destination file: %1").arg(e.relPath);
                    break;
                }

                while (!srcFile.atEnd()) {
                    if (session->isCancelled) break;
                    const qint64 readLen = srcFile.read(buffer.data(), kCopyBufSize);
                    if (readLen < 0) {
                        errMsg = QStringLiteral("Read error copying %1").arg(e.relPath);
                        break;
                    }
                    if (readLen == 0) break;

                    qint64 writtenTotal = 0;
                    while (writtenTotal < readLen) {
                        const qint64 w = dstFile.write(buffer.constData() + writtenTotal, readLen - writtenTotal);
                        if (w <= 0) {
                            errMsg = QStringLiteral("Write error copying %1").arg(e.relPath);
                            break;
                        }
                        writtenTotal += w;
                    }
                    if (!errMsg.isEmpty()) break;

                    copiedBytes += readLen;
                    if (emitTimer.elapsed() >= 150) {
                        emitTimer.restart();
                        const double pct = totalBytes > 0
                                               ? (100.0 * static_cast<double>(copiedBytes) / static_cast<double>(totalBytes))
                                               : 100.0;
                        const qint64 elapsedMs = qMax<qint64>(1, session->speedTimer.elapsed());
                        const double bps = (static_cast<double>(copiedBytes) * 1000.0) / static_cast<double>(elapsedMs);
                        const QString speedStr = QStringLiteral("%1/s").arg(DownloadManager::formatBytes(static_cast<qint64>(bps)));
                        QString etaStr;
                        if (bps > 1024.0 && totalBytes > copiedBytes) {
                            const qint64 remSecs = static_cast<qint64>((totalBytes - copiedBytes) / bps);
                            etaStr = (remSecs < 60)
                                         ? QStringLiteral("%1s left").arg(remSecs)
                                         : QStringLiteral("%1m %2s left").arg(remSecs / 60).arg(remSecs % 60);
                        }
                        QMetaObject::invokeMethod(qApp, [self, session, copiedBytes, pct, speedStr, etaStr]() {
                            if (!self || session->isCancelled) return;
                            session->downloadedBytes = copiedBytes;
                            session->progress = qBound(0.0, pct, 99.9);
                            session->speedText = speedStr;
                            session->etaText = etaStr;
                            emit self->downloadStateChanged(session->appName);
                        }, Qt::QueuedConnection);
                    }
                }
                dstFile.close();
                srcFile.close();
                if (!errMsg.isEmpty() || session->isCancelled) break;
                QFile::setPermissions(dstPath, e.perms);
            }
        }

        if (session->isCancelled) {
            if (session->deleteOnCancel && targetDir != cleanSrc) {
                QDir(targetDir).removeRecursively();
            }
            return;
        }

        if (errMsg.isEmpty() && mode == QLatin1String("move") && targetDir != cleanSrc) {
            const QString homeClean = QDir::cleanPath(QDir::homePath());
            if (cleanSrc != QStringLiteral("/") && cleanSrc != homeClean) {
                QDir(cleanSrc).removeRecursively();
            }
        }

        QMetaObject::invokeMethod(qApp, [self, session, errMsg, totalBytes]() {
            if (!self) return;
            if (session->isCancelled || !self->m_downloads.contains(session->appName)) return;
            if (!errMsg.isEmpty()) {
                if (session->installDir != session->importSourceDir) {
                    QDir(session->installDir).removeRecursively();
                }
                self->failDownloadSession(session, errMsg);
                return;
            }
            session->downloadedBytes = totalBytes;
            session->progress = 100.0;
            self->completeImportSession(session);
        }, Qt::QueuedConnection);
    });
}

void EpicService::completeImportSession(const std::shared_ptr<DownloadSession>& session) {
    if (!session || session->isCancelled || !m_downloads.contains(session->appName)) return;

    session->stageText = QStringLiteral("Fetching manifest…");
    session->etaText.clear();
    emit downloadStateChanged(session->appName);

    auto finishRegistration = [this, session](const EpicManifest& manifest, bool hasManifest) {
        if (session->isCancelled || !m_downloads.contains(session->appName)) return;

        if (session->verifyAfterImport && hasManifest) {
            session->isImporting = false;
            session->verifyOnly = true;
            session->manifest = manifest;
            // Clear mirrors unless provided; verifyGame/prepareAndStartSession uses mirrors for missing files
            prepareAndStartSession(session);
            return;
        }

        const QString exePath = resolveImportedExecutable(
            session->installDir,
            hasManifest ? manifest.launchExe : QString(),
            session->explicitExecutable,
            session->importSourceDir);

        const QString appName = session->appName;
        const QString title = session->title;
        const bool inPlace = session->importedInPlace;
        const QString nsId = session->namespaceId;
        const QString catId = session->catalogItemId;
        const QString installDir = session->installDir;
        const QString launchArgs = hasManifest ? manifest.launchCommand : QString();
        const QString buildVer = hasManifest ? manifest.buildVersion : QString();
        const QString runnerId = session->runnerId;
        const QString prefixMode = session->prefixMode;
        const QString customPfxName = session->customPrefixName;
        const QString customPfxLoc = session->customPrefixLocation;
        const QString pfxArch = session->prefixArch;

        m_downloads.remove(appName);
        emit activeDownloadsChanged();

        QString registeredId;
        if (m_gameMgr) {
            auto libItem = m_db->getEpicLibraryItem(appName);
            registeredId = m_gameMgr->registerEpicGame(
                appName,
                nsId,
                catId,
                libItem.has_value() ? libItem->title : title,
                exePath,
                installDir,
                launchArgs,
                buildVer,
                runnerId,
                prefixMode,
                customPfxName,
                customPfxLoc,
                pfxArch,
                libItem.has_value() ? libItem->coverPath : QString(),
                libItem.has_value() ? libItem->bannerPath : QString(),
                libItem.has_value() ? libItem->logoPath : QString(),
                inPlace);
            if (!registeredId.isEmpty()) {
                if (auto gOpt = m_db->getGame(registeredId); gOpt.has_value()) {
                    GameRecord updated = *gOpt;
                    if (hasManifest && !manifest.prereqPath.isEmpty()) {
                        updated.epicPrereqName = manifest.prereqName;
                        updated.epicPrereqPath = manifest.prereqPath;
                        updated.epicPrereqArgs = manifest.prereqArgs;
                        updated.epicPrereqIds = manifest.prereqIds;
                    }
                    if (libItem.has_value()) {
                        if (updated.epicCloudSaveFolder.isEmpty()) updated.epicCloudSaveFolder = libItem->cloudSaveFolder;
                        if (updated.epicCloudIncludeList.isEmpty()) updated.epicCloudIncludeList = libItem->cloudIncludeList;
                        if (updated.epicCloudExcludeList.isEmpty()) updated.epicCloudExcludeList = libItem->cloudExcludeList;
                    }
                    m_db->saveGame(updated);
                }
                if (m_umuResolver) {
                    m_umuResolver->lookupAndCache(QStringLiteral("egs"), appName);
                }
            }
        }

        m_model->reload();
        emit downloadStateChanged(appName);
        emit downloadFinished(appName, registeredId);
        emit operationStatus(QStringLiteral("Imported '%1' to Library.").arg(title), false);
    };

    auto itemOpt = m_db->getEpicLibraryItem(session->appName);
    if (!itemOpt.has_value() || !m_isSignedIn) {
        QFile mf(manifestCachePath(session->appName));
        EpicManifest cached;
        bool hasCached = false;
        if (mf.exists() && mf.open(QIODevice::ReadOnly)) {
            hasCached = EpicManifestParser::parse(mf.readAll(), cached);
        }
        finishRegistration(cached, hasCached);
        return;
    }

    fetchAssetManifest(*itemOpt, [this, session, finishRegistration](bool ok,
                                                                     const EpicManifest& manifest,
                                                                     const QList<MirrorEndpoint>& mirrors,
                                                                     const QByteArray& rawManifest,
                                                                     const QString&) {
        if (session->isCancelled || !m_downloads.contains(session->appName)) return;
        if (ok) {
            QFile mf(manifestCachePath(session->appName));
            if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                mf.write(rawManifest);
                mf.close();
            }
            m_db->updateEpicLibrarySizes(session->appName, manifest.totalDownloadSize, manifest.totalInstallSize, manifest.buildVersion);
            session->mirrors = mirrors;
            finishRegistration(manifest, true);
            return;
        }

        QFile mf(manifestCachePath(session->appName));
        EpicManifest cached;
        bool hasCached = false;
        if (mf.exists() && mf.open(QIODevice::ReadOnly)) {
            hasCached = EpicManifestParser::parse(mf.readAll(), cached);
        }
        finishRegistration(cached, hasCached);
    });
}

void EpicService::failDownloadSession(const std::shared_ptr<DownloadSession>& session, const QString& error) {
    const QString appName = session->appName;
    const QString queueId = session->queueId;
    const QString title = session->title;
    session->isCancelled = true;
    for (QNetworkReply* r : session->activeReplies) {
        if (r) {
            r->disconnect(this);
            r->abort();
            r->deleteLater();
        }
    }
    session->activeReplies.clear();
    saveResumeState(session);

    m_downloads.remove(appName);
    if (m_dlMgr && !queueId.isEmpty()) {
        m_dlMgr->finishExternalTask(queueId, false, error, session->existingGameId, QString());
    }
    emit activeDownloadsChanged();
    emit downloadStateChanged(appName);
    if (session->isEosOverlay) {
        emit eosOverlayChanged();
    }
    emit downloadFailed(appName, error);
    emit operationStatus(QStringLiteral("%1 download failed: %2").arg(title, error), true);
}

void EpicService::pauseDownload(const QString& appName) {
    auto session = m_downloads.value(appName);
    if (!session || session->isPaused || session->isVerifying || session->isImporting) return;

    session->isPaused = true;
    session->speedBps = 0.0;
    session->speedText.clear();
    session->stageText = QStringLiteral("Paused");
    session->etaText = QStringLiteral("Paused");

    const QList<QNetworkReply*> replies = session->activeReplies;
    session->activeReplies.clear();
    for (QNetworkReply* r : replies) {
        if (r) {
            r->abort();
        }
    }
    saveResumeState(session);
    persistDownloadQueueItem(session);
    emit downloadStateChanged(appName);
    notifyDownloadManagerProgress(session);
}

void EpicService::resumeDownload(const QString& appName) {
    auto session = m_downloads.value(appName);
    if (!session || !session->isPaused) return;

    session->isPaused = false;
    session->isQueued = false;
    session->sessionBytes = 0;
    session->speedTimer.restart();
    session->stageText = QStringLiteral("Resuming…");
    persistDownloadQueueItem(session);
    emit downloadStateChanged(appName);
    notifyDownloadManagerProgress(session);

    // Restored downloads after app restart need fresh signed manifest & CDN mirrors first
    if (!session->manifest.isValid || session->mirrors.isEmpty() || session->chunkJobs.isEmpty()) {
        beginSessionExecution(session);
        return;
    }
    pumpDownloadChunks(session);
}

void EpicService::cancelDownload(const QString& appName, bool deletePartialFiles) {
    auto session = m_downloads.take(appName);
    if (!session) return;

    const QString queueId = session->queueId;
    removePersistedDownloadQueueItem(queueId);
    session->isCancelled = true;
    session->deleteOnCancel = deletePartialFiles;
    const QList<QNetworkReply*> replies = session->activeReplies;
    session->activeReplies.clear();
    for (QNetworkReply* r : replies) {
        if (r) {
            r->disconnect(this);
            r->abort();
            r->deleteLater();
        }
    }

    if (deletePartialFiles && !session->verifyOnly && !session->isUpdate && !session->isDlc && !session->isImporting && !session->installDir.isEmpty()) {
        QDir(session->installDir).removeRecursively();
    } else if (!session->isImporting) {
        saveResumeState(session);
    }

    const QString cancelMsg = session->isImporting ? QStringLiteral("Import cancelled") : QStringLiteral("Download cancelled");
    if (m_dlMgr && !queueId.isEmpty()) {
        m_dlMgr->finishExternalTask(queueId, false, cancelMsg, session->existingGameId, QString());
    }

    emit activeDownloadsChanged();
    emit downloadStateChanged(appName);
    if (session->isEosOverlay) {
        emit eosOverlayChanged();
    }
    emit downloadFailed(appName, cancelMsg);
}

void EpicService::verifyGame(const QString& gameId) {
    auto gOpt = m_db->getGame(gameId);
    if (!gOpt.has_value() || !gOpt->isEpic()) return;
    const GameRecord g = *gOpt;
    if (m_downloads.contains(g.epicAppName)) return;

    auto itemOpt = m_db->getEpicLibraryItem(g.epicAppName);
    EpicLibraryItem item;
    if (itemOpt.has_value()) {
        item = *itemOpt;
    } else {
        item.appName = g.epicAppName;
        item.namespaceId = g.epicNamespace;
        item.catalogItemId = g.epicCatalogItemId;
        item.title = g.title;
    }

    const QString targetDir = !g.epicInstallDir.isEmpty() ? g.epicInstallDir : g.workingDirectory;
    if (targetDir.isEmpty() || !QDir(targetDir).exists()) {
        emit operationStatus(QStringLiteral("Install directory does not exist for '%1'.").arg(g.title), true);
        return;
    }

    auto session = std::make_shared<DownloadSession>();
    session->queueId = QStringLiteral("epic-verify-") + g.epicAppName;
    session->appName = g.epicAppName;
    session->namespaceId = g.epicNamespace;
    session->catalogItemId = g.epicCatalogItemId;
    session->title = g.title + QStringLiteral(" (Verify)");
    session->coverPath = GameRecord::toFileUrlOrOriginal(g.coverPath);
    session->installDir = targetDir;
    session->runnerId = g.runnerId;
    session->prefixMode = g.prefixId;
    session->verifyOnly = true;
    session->existingGameId = g.id;
    session->selectedInstallTags = g.epicSelectedInstallTags;
    session->stageText = QStringLiteral("Fetching manifest…");
    session->speedTimer.start();
    session->uiEmitTimer.start();

    m_downloads.insert(g.epicAppName, session);
    persistDownloadQueueItem(session);
    emit activeDownloadsChanged();
    emit downloadStateChanged(g.epicAppName);
    if (m_dlMgr) {
        QPointer<EpicService> self(this);
        DownloadManager::ExternalAdapter adapter;
        adapter.cancelFn = [self, app = g.epicAppName](bool) { if (self) self->cancelDownload(app, false); };
        m_dlMgr->registerExternalTask(session->queueId, session->title, QStringLiteral("epic_verify"),
                                      g.epicAppName, session->coverPath, false, std::move(adapter), false);
    }

    fetchAssetManifest(item, [this, session](bool ok,
                                               const EpicManifest& manifest,
                                               const QList<MirrorEndpoint>& mirrors,
                                               const QByteArray& rawManifest,
                                               const QString& error) {
        if (session->isCancelled || !m_downloads.contains(session->appName)) return;
        if (!ok) {
            failDownloadSession(session, error.isEmpty() ? QStringLiteral("Failed to fetch manifest for verification.") : error);
            return;
        }
        QFile mf(manifestCachePath(session->appName));
        if (mf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            mf.write(rawManifest);
            mf.close();
        }
        session->manifest = manifest;
        session->mirrors = mirrors;
        prepareAndStartSession(session);
    });
}

void EpicService::saveResumeState(const std::shared_ptr<DownloadSession>& session) {
    if (!session || session->installDir.isEmpty() || session->verifyOnly) return;
    QDir().mkpath(session->installDir);
    QJsonObject obj;
    obj[QStringLiteral("appName")] = session->appName;
    obj[QStringLiteral("buildVersion")] = session->manifest.buildVersion;
    QJsonArray completed;
    for (const QString& g : session->completedChunks) {
        completed.append(g);
    }
    obj[QStringLiteral("completedChunks")] = completed;

    QFile f(session->installDir + QStringLiteral("/.tsuki_epic_state.json"));
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
        f.close();
    }
    persistDownloadQueueItem(session);
}

QSet<QString> EpicService::loadResumeState(const QString& installDir, const QString& buildVersion) const {
    QSet<QString> set;
    QFile f(installDir + QStringLiteral("/.tsuki_epic_state.json"));
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) return set;
    const QJsonObject obj = QJsonDocument::fromJson(f.readAll()).object();
    f.close();
    if (!buildVersion.isEmpty() && obj.value(QStringLiteral("buildVersion")).toString() != buildVersion) {
        return set;
    }
    const QJsonArray arr = obj.value(QStringLiteral("completedChunks")).toArray();
    for (const QJsonValue& v : arr) {
        set.insert(v.toString());
    }
    return set;
}

void EpicService::cleanupSessionFiles(const std::shared_ptr<DownloadSession>& session) {
    if (!session || session->installDir.isEmpty()) return;
    QFile::remove(session->installDir + QStringLiteral("/.tsuki_epic_state.json"));
}

qint64 EpicService::getFreeDiskSpace(const QString& path) const {
    QString clean = path.trimmed();
    if (clean.startsWith(QStringLiteral("file://"))) {
        clean = QUrl(clean).toLocalFile();
    }
    if (clean.isEmpty()) clean = m_settings->defaultEpicInstallLocation();
    QDir d(clean);
    while (!d.exists() && !d.isRoot()) {
        if (!d.cdUp()) break;
    }
    QStorageInfo info(d.exists() ? d.absolutePath() : QDir::homePath());
    return info.isValid() ? info.bytesAvailable() : -1;
}

QString EpicService::getFreeDiskSpaceFormatted(const QString& path) const {
    const qint64 bytes = getFreeDiskSpace(path);
    return bytes >= 0 ? DownloadManager::formatBytes(bytes) : QStringLiteral("Unknown");
}

QString EpicService::formatBytes(qint64 bytes) const {
    return DownloadManager::formatBytes(bytes);
}

QString EpicService::sanitizeFolderName(const QString& title) {
    QString clean = title.trimmed();
    clean.replace(QRegularExpression(QStringLiteral("[\\\\/:*?\"<>|]+")), QStringLiteral(" "));
    clean = clean.simplified();
    if (clean.isEmpty()) return QStringLiteral("EpicGame");
    return clean;
}

QString EpicService::suggestInstallDirectory(const QString& baseDir, const QString& gameTitle) const {
    QString cleanBase = baseDir.trimmed();
    if (cleanBase.startsWith(QStringLiteral("file://"))) {
        cleanBase = QUrl(cleanBase).toLocalFile();
    }
    if (cleanBase.isEmpty()) {
        cleanBase = m_settings->defaultEpicInstallLocation();
    }
    const QString folder = sanitizeFolderName(gameTitle);
    const QString cleanNormalized = QDir::cleanPath(cleanBase);
    if (QFileInfo(cleanNormalized).fileName().compare(folder, Qt::CaseInsensitive) == 0) {
        return cleanNormalized;
    }
    return QDir(cleanNormalized).filePath(folder);
}

QString EpicService::resolveExistingRelativePath(const QString& baseDir, const QString& relativePath) {
    QString cleanRel = relativePath;
    cleanRel.replace(QLatin1Char('\\'), QLatin1Char('/'));
    while (cleanRel.startsWith(QLatin1Char('/'))) cleanRel.remove(0, 1);

    const QString direct = QDir(baseDir).filePath(cleanRel);
    if (QFileInfo::exists(direct)) return QFileInfo(direct).absoluteFilePath();

    const QStringList parts = cleanRel.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QDir cur(baseDir);
    for (int i = 0; i < parts.size(); ++i) {
        const QString target = parts.at(i);
        const bool isLast = (i == parts.size() - 1);
        const QFileInfoList entries = cur.entryInfoList(isLast ? QDir::Files : QDir::Dirs | QDir::NoDotAndDotDot);
        bool found = false;
        for (const QFileInfo& fi : entries) {
            if (fi.fileName().compare(target, Qt::CaseInsensitive) == 0) {
                if (isLast) return fi.absoluteFilePath();
                cur.setPath(fi.absoluteFilePath());
                found = true;
                break;
            }
        }
        if (!found) break;
    }
    return direct;
}

QString EpicService::eosOverlayPath() const {
    const QString tsukiOverlay = AppSettings::toolsDir() + QStringLiteral("/eos_overlay");
    auto hasOverlayFiles = [](const QString& dir) {
        return QFileInfo::exists(dir + QStringLiteral("/EOSOverlayRenderer-Win64-Shipping.exe")) ||
               QFileInfo::exists(dir + QStringLiteral("/EOSOverlayRenderer-Win32-Shipping.exe")) ||
               QFileInfo::exists(dir + QStringLiteral("/EOSOverlayVkLayer-Win64.json")) ||
               QFileInfo::exists(dir + QStringLiteral("/.tsuki_eos_version"));
    };
    if (hasOverlayFiles(tsukiOverlay)) return tsukiOverlay;

    const QStringList heroicCandidates = {
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/eos_overlay"),
        QDir::homePath() + QStringLiteral("/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/eos_overlay")
    };
    for (const QString& hc : heroicCandidates) {
        if (hasOverlayFiles(hc)) return hc;
    }
    return tsukiOverlay;
}

bool EpicService::isEosOverlayInstalled() const {
    const QString path = eosOverlayPath();
    return QFileInfo::exists(path + QStringLiteral("/EOSOverlayRenderer-Win64-Shipping.exe")) ||
           QFileInfo::exists(path + QStringLiteral("/EOSOverlayRenderer-Win32-Shipping.exe")) ||
           QFileInfo::exists(path + QStringLiteral("/EOSOverlayVkLayer-Win64.json"));
}

QString EpicService::eosOverlayVersion() const {
    const QString verFile = eosOverlayPath() + QStringLiteral("/.tsuki_eos_version");
    QFile f(verFile);
    if (f.exists() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString::fromUtf8(f.readAll()).trimmed();
    }
    return isEosOverlayInstalled() ? QStringLiteral("Installed") : QString();
}

bool EpicService::isInstallingEosOverlay() const {
    return m_downloads.contains(QLatin1String(kEosOverlayAppName));
}

double EpicService::eosOverlayProgress() const {
    auto s = m_downloads.value(QLatin1String(kEosOverlayAppName));
    return s ? s->progress : 0.0;
}

void EpicService::installEosOverlay() {
    const QString appName = QLatin1String(kEosOverlayAppName);
    if (m_downloads.contains(appName)) return;

    const QString targetDir = AppSettings::toolsDir() + QStringLiteral("/eos_overlay");
    QDir().mkpath(targetDir);

    auto session = std::make_shared<DownloadSession>();
    session->appName = appName;
    session->namespaceId = QLatin1String(kEosOverlayNamespace);
    session->catalogItemId = QLatin1String(kEosOverlayCatalogId);
    session->title = QStringLiteral("Epic Online Services Overlay");
    session->installDir = targetDir;
    session->isEosOverlay = true;
    session->stageText = QStringLiteral("Fetching EOS Overlay manifest…");
    session->speedTimer.start();
    session->uiEmitTimer.start();

    m_downloads.insert(appName, session);
    persistDownloadQueueItem(session);
    emit activeDownloadsChanged();
    emit eosOverlayChanged();

    EpicLibraryItem item;
    item.appName = appName;
    item.namespaceId = QLatin1String(kEosOverlayNamespace);
    item.catalogItemId = QLatin1String(kEosOverlayCatalogId);
    item.title = session->title;

    auto startWithToken = [this, session, item](const QString& bearerToken) {
        if (session->isCancelled || !m_downloads.contains(session->appName)) return;
        fetchAssetManifestWithToken(item, bearerToken, [this, session](bool ok,
                                                                        const EpicManifest& manifest,
                                                                        const QList<MirrorEndpoint>& mirrors,
                                                                        const QByteArray&,
                                                                        const QString& err) {
            if (session->isCancelled || !m_downloads.contains(session->appName)) return;
            if (!ok) {
                failDownloadSession(session, err.isEmpty() ? QStringLiteral("Failed to fetch EOS Overlay manifest.") : err);
                return;
            }
            session->manifest = manifest;
            session->mirrors = mirrors;
            prepareAndStartSession(session);
        });
    };

    if (m_isSignedIn) {
        ensureValidToken([this, session, startWithToken](bool ok) {
            if (!ok) {
                failDownloadSession(session, QStringLiteral("Please sign in to Epic Games or check network connectivity."));
                return;
            }
            startWithToken(m_accessToken);
        });
        return;
    }

    // Anonymous client_credentials flow so EOS Overlay can install even before sign-in
    QNetworkRequest req(QUrl(QStringLiteral("https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token")));
    req.setRawHeader("Authorization", basicAuthHeader());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/x-www-form-urlencoded"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kEpicLauncherUserAgent));
    QNetworkReply* reply = m_nam.post(req, QByteArray("grant_type=client_credentials&token_type=eg1"));
    connect(reply, &QNetworkReply::finished, this, [this, session, reply, startWithToken]() {
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const QByteArray payload = ok ? safeReadReply(reply) : QByteArray();
        const QString err = reply->errorString();
        reply->deleteLater();
        if (!ok) {
            failDownloadSession(session, err.isEmpty() ? QStringLiteral("Failed to obtain Epic client token.") : err);
            return;
        }
        const QString token = QJsonDocument::fromJson(payload).object().value(QStringLiteral("access_token")).toString();
        startWithToken(token);
    });
}

void EpicService::removeEosOverlay() {
    const QString tsukiOverlay = AppSettings::toolsDir() + QStringLiteral("/eos_overlay");
    const QString appName = QLatin1String(kEosOverlayAppName);
    if (m_downloads.contains(appName)) {
        cancelDownload(appName, true);
    }
    if (QDir(tsukiOverlay).exists()) {
        QDir(tsukiOverlay).removeRecursively();
        emit eosOverlayChanged();
        emit operationStatus(QStringLiteral("Removed EOS Overlay."), false);
    }
}

} // namespace Tsuki

