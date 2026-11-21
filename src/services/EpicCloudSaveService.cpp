#include "EpicCloudSaveService.h"
#include "EpicService.h"

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
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QProcess>
#include <QRegularExpression>
#include <QUrl>
#include <QUuid>
#include <algorithm>
#include <memory>

namespace Tsuki {

namespace {

constexpr const char* kCloudStorageBaseUrl =
    "https://datastorage-public-service-liveegs.live.use1a.on.epicgames.com/api/v1/access/egstore/savesync";
constexpr const char* kCloudUserAgent =
    "UELauncher/16.12.1-33490172+++Portal+Release-Live Windows/10.0.19041.1.256.64bit";

QString detectPrefixUserProfileDir(const QString& prefixPath) {
    const QString usersDir = prefixPath + QStringLiteral("/drive_c/users");
    const QString steamUser = usersDir + QStringLiteral("/steamuser");
    if (QDir(steamUser).exists()) return steamUser;

    const QString envUser = qEnvironmentVariable("USER");
    if (!envUser.isEmpty() && QDir(usersDir + QLatin1Char('/') + envUser).exists()) {
        return usersDir + QLatin1Char('/') + envUser;
    }

    QDir d(usersDir);
    if (d.exists()) {
        for (const QFileInfo& fi : d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (fi.fileName().compare(QStringLiteral("Public"), Qt::CaseInsensitive) != 0) {
                return fi.absoluteFilePath();
            }
        }
    }
    return steamUser;
}

bool matchesGlobPattern(const QString& relPath, const QString& pattern) {
    QString p = pattern.trimmed();
    p.replace(QLatin1Char('\\'), QLatin1Char('/'));
    if (p.isEmpty()) return false;
    const QRegularExpression re = QRegularExpression::fromWildcard(p, Qt::CaseInsensitive);
    return re.match(relPath).hasMatch() || re.match(QFileInfo(relPath).fileName()).hasMatch();
}

qint64 parseIsoEpoch(const QString& s) {
    if (s.isEmpty()) return 0;
    QDateTime dt = QDateTime::fromString(s, Qt::ISODateWithMs);
    if (!dt.isValid()) dt = QDateTime::fromString(s, Qt::ISODate);
    return dt.isValid() ? dt.toSecsSinceEpoch() : 0;
}

} // namespace

EpicCloudSaveService::EpicCloudSaveService(DatabaseManager* db,
                                           AppSettings* settings,
                                           PrefixManager* prefixMgr,
                                           EpicService* epicService,
                                           QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_prefixMgr(prefixMgr)
    , m_epicSvc(epicService)
{
}

QString EpicCloudSaveService::resolveSaveFolderPath(const QString& rawTemplate,
                                                    const QString& prefixPath,
                                                    const QString& installDir,
                                                    const QString& epicAccountId) {
    QString tpl = rawTemplate.trimmed();
    if (tpl.isEmpty()) return QString();

    tpl.replace(QLatin1Char('\\'), QLatin1Char('/'));

    // Already an absolute Linux path (user custom override)
    if (tpl.startsWith(QLatin1Char('/')) && !tpl.contains(QLatin1Char('{')) && !tpl.contains(QLatin1Char('%'))) {
        return QDir::cleanPath(tpl);
    }

    const QString userProfile = detectPrefixUserProfileDir(prefixPath);
    const QString appDataLocal = userProfile + QStringLiteral("/AppData/Local");
    const QString appDataLocalLow = userProfile + QStringLiteral("/AppData/LocalLow");
    const QString appDataRoaming = userProfile + QStringLiteral("/AppData/Roaming");
    const QString documentsDir = userProfile + QStringLiteral("/Documents");
    const QString savedGamesDir = userProfile + QStringLiteral("/Saved Games");
    const QString publicDocs = prefixPath + QStringLiteral("/drive_c/users/Public/Documents");
    const QString programData = prefixPath + QStringLiteral("/drive_c/ProgramData");

    const QList<QPair<QString, QString>> replacements = {
        {QStringLiteral("{InstallDir}"), installDir},
        {QStringLiteral("{AppData}"), appDataLocal},
        {QStringLiteral("{LocalAppData}"), appDataLocal},
        {QStringLiteral("{LocalLow}"), appDataLocalLow},
        {QStringLiteral("{RoamingAppData}"), appDataRoaming},
        {QStringLiteral("{UserDir}"), documentsDir},
        {QStringLiteral("{MyDocuments}"), documentsDir},
        {QStringLiteral("{UserSavedGames}"), savedGamesDir},
        {QStringLiteral("{PublicDocuments}"), publicDocs},
        {QStringLiteral("{ProgramData}"), programData},
        {QStringLiteral("{EpicID}"), epicAccountId},
        {QStringLiteral("%LOCALAPPDATA%"), appDataLocal},
        {QStringLiteral("%APPDATA%"), appDataRoaming},
        {QStringLiteral("%USERPROFILE%"), userProfile},
        {QStringLiteral("%DOCUMENTS%"), documentsDir},
        {QStringLiteral("%PROGRAMDATA%"), programData}
    };

    for (const auto& pair : replacements) {
        if (!pair.second.isEmpty()) {
            tpl.replace(pair.first, pair.second, Qt::CaseInsensitive);
        }
    }

    // Handle Windows drive letter prefix like C:/...
    if (tpl.size() >= 2 && tpl.at(1) == QLatin1Char(':')) {
        const QChar drive = tpl.at(0).toLower();
        if (drive == QLatin1Char('c')) {
            tpl = prefixPath + QStringLiteral("/drive_c") + tpl.mid(2);
        }
    }

    // Handle trailing "/../" or relative segments cleanly
    return QDir::cleanPath(tpl);
}

QString EpicCloudSaveService::resolveLocalSaveDirForGame(const QString& gameId) const {
    if (!m_db || gameId.isEmpty()) return QString();
    auto gOpt = m_db->getGame(gameId);
    if (!gOpt.has_value()) return QString();
    const GameRecord g = *gOpt;

    QString saveTpl = g.epicCloudSaveFolder.trimmed();
    if (saveTpl.isEmpty() && g.isEpic()) {
        if (auto libOpt = m_db->getEpicLibraryItem(g.epicAppName); libOpt.has_value()) {
            saveTpl = libOpt->cloudSaveFolder.trimmed();
        }
    }
    if (saveTpl.isEmpty()) return QString();

    QString prefixPath;
    if (!g.prefixId.isEmpty()) {
        if (auto pOpt = m_db->getPrefix(g.prefixId); pOpt.has_value()) {
            prefixPath = pOpt->path;
        }
    }
    if (prefixPath.isEmpty()) {
        if (auto defOpt = m_db->getPrefix(QStringLiteral("default-prefix")); defOpt.has_value()) {
            prefixPath = defOpt->path;
        } else if (m_settings) {
            prefixPath = m_settings->defaultPrefixLocation() + QStringLiteral("/Default");
        }
    }

    const QString installDir = !g.epicInstallDir.isEmpty() ? g.epicInstallDir : g.workingDirectory;
    const QString accountId = m_epicSvc ? m_epicSvc->accountId() : QString();
    return resolveSaveFolderPath(saveTpl, prefixPath, installDir, accountId);
}

QList<EpicCloudSaveService::LocalFileEntry> EpicCloudSaveService::scanLocalSaveFiles(
    const QString& saveDir,
    const QStringList& includePatterns,
    const QStringList& excludePatterns)
{
    QList<LocalFileEntry> out;
    if (saveDir.isEmpty() || !QDir(saveDir).exists()) return out;

    const QDir base(saveDir);
    QDirIterator it(saveDir, QDir::Files | QDir::NoSymLinks, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        const QString absPath = it.next();
        QString relPath = base.relativeFilePath(absPath);
        relPath.replace(QLatin1Char('\\'), QLatin1Char('/'));

        if (!includePatterns.isEmpty()) {
            bool matched = false;
            for (const QString& inc : includePatterns) {
                if (matchesGlobPattern(relPath, inc)) {
                    matched = true;
                    break;
                }
            }
            if (!matched) continue;
        }
        bool excluded = false;
        for (const QString& exc : excludePatterns) {
            if (matchesGlobPattern(relPath, exc)) {
                excluded = true;
                break;
            }
        }
        if (excluded) continue;

        QFileInfo fi(absPath);
        QFile f(absPath);
        QByteArray sha1;
        if (f.open(QIODevice::ReadOnly)) {
            QCryptographicHash h(QCryptographicHash::Sha1);
            if (h.addData(&f)) sha1 = h.result();
            f.close();
        }
        LocalFileEntry entry;
        entry.relativePath = relPath;
        entry.absolutePath = absPath;
        entry.sha1 = sha1;
        entry.size = fi.size();
        entry.mtimeEpoch = fi.lastModified().toSecsSinceEpoch();
        out.append(entry);
    }

    std::sort(out.begin(), out.end(), [](const LocalFileEntry& a, const LocalFileEntry& b) {
        return a.relativePath < b.relativePath;
    });
    return out;
}

EpicCloudSaveService::SyncDecision EpicCloudSaveService::evaluateSyncState(
    const QList<LocalFileEntry>& localFiles,
    qint64 localLatestMtime,
    bool hasRemoteManifest,
    qint64 remoteMtimeEpoch,
    const QString& remoteManifestHash,
    const std::optional<DatabaseManager::CloudSaveState>& prevState)
{
    const bool hasLocal = !localFiles.isEmpty();
    if (!hasLocal && !hasRemoteManifest) {
        return SyncDecision::UpToDate;
    }
    if (!hasLocal && hasRemoteManifest) {
        return SyncDecision::DownloadRecommended;
    }
    if (hasLocal && !hasRemoteManifest) {
        return SyncDecision::UploadRecommended;
    }

    // Both local and remote exist
    if (prevState.has_value() && prevState->lastSyncEpoch > 0) {
        bool localChangedSinceSync = (localFiles.size() != prevState->trackedFiles.size());
        if (!localChangedSinceSync) {
            for (const LocalFileEntry& lf : localFiles) {
                const QVariantMap prevEntry = prevState->trackedFiles.value(lf.relativePath).toMap();
                const QString prevHash = prevEntry.value(QStringLiteral("sha1")).toString();
                if (prevHash.isEmpty() || prevHash != QString::fromLatin1(lf.sha1.toHex())) {
                    localChangedSinceSync = true;
                    break;
                }
            }
        }
        const bool remoteChangedSinceSync =
            (!remoteManifestHash.isEmpty() && !prevState->lastManifestHash.isEmpty() &&
             remoteManifestHash != prevState->lastManifestHash) ||
            (remoteMtimeEpoch > prevState->lastSyncEpoch + 2);

        if (!localChangedSinceSync && !remoteChangedSinceSync) {
            return SyncDecision::UpToDate;
        }
        if (localChangedSinceSync && !remoteChangedSinceSync) {
            return SyncDecision::UploadRecommended;
        }
        if (!localChangedSinceSync && remoteChangedSinceSync) {
            return SyncDecision::DownloadRecommended;
        }
        return SyncDecision::Conflict;
    }

    // First-time sync with both local and remote saves present:
    // If timestamps diverge significantly, flag as Conflict so user chooses safely.
    if (qAbs(localLatestMtime - remoteMtimeEpoch) <= 5) {
        return SyncDecision::UpToDate;
    }
    return SyncDecision::Conflict;
}

QString EpicCloudSaveService::createLocalSafetySnapshot(const QString& gameId,
                                                        const QString& localSaveDir,
                                                        const QString& backupsBaseDir,
                                                        int keepMax)
{
    if (gameId.isEmpty() || localSaveDir.isEmpty() || !QDir(localSaveDir).exists()) {
        return QString();
    }
    QDir srcDir(localSaveDir);
    if (srcDir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot).isEmpty()) {
        return QString();
    }

    const QString base = backupsBaseDir.isEmpty()
                             ? (AppSettings::backupsDir() + QStringLiteral("/saves"))
                             : backupsBaseDir;
    const QString gameSnapDir = base + QLatin1Char('/') + gameId;
    QDir().mkpath(gameSnapDir);

    const QString ts = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss_zzz"));
    const QString archivePath = gameSnapDir + QStringLiteral("/save_%1.tar.gz").arg(ts);

    QProcess tar;
    tar.start(QStringLiteral("tar"),
              {QStringLiteral("-czf"), archivePath, QStringLiteral("-C"), localSaveDir, QStringLiteral(".")});
    if (!tar.waitForFinished(15000) || tar.exitCode() != 0 || !QFileInfo::exists(archivePath)) {
        QFile::remove(archivePath);
        return QString();
    }

    // Prune older snapshots beyond keepMax
    if (keepMax > 0) {
        QDir snapDir(gameSnapDir);
        const QFileInfoList allSnaps = snapDir.entryInfoList(
            {QStringLiteral("save_*.tar.gz")}, QDir::Files, QDir::Name | QDir::Reversed);
        for (int i = keepMax; i < allSnaps.size(); ++i) {
            QFile::remove(allSnaps.at(i).absoluteFilePath());
        }
    }
    return archivePath;
}

QVariantList EpicCloudSaveService::listLocalSnapshots(const QString& gameId) const {
    QVariantList out;
    if (gameId.isEmpty()) return out;
    const QString gameSnapDir = AppSettings::backupsDir() + QStringLiteral("/saves/") + gameId;
    QDir d(gameSnapDir);
    if (!d.exists()) return out;
    const QFileInfoList snaps = d.entryInfoList({QStringLiteral("save_*.tar.gz")}, QDir::Files, QDir::Name | QDir::Reversed);
    for (const QFileInfo& fi : snaps) {
        QVariantMap m;
        m[QStringLiteral("path")] = fi.absoluteFilePath();
        m[QStringLiteral("fileName")] = fi.fileName();
        m[QStringLiteral("sizeFormatted")] = EpicLibraryItem::formatSize(fi.size());
        m[QStringLiteral("createdFormatted")] = fi.lastModified().toString(QStringLiteral("MMM d, yyyy HH:mm"));
        out.append(m);
    }
    return out;
}

bool EpicCloudSaveService::restoreLocalSnapshot(const QString& gameId, const QString& snapshotPath) {
    const QString localDir = resolveLocalSaveDirForGame(gameId);
    if (localDir.isEmpty() || !QFileInfo::exists(snapshotPath)) {
        emit operationStatus(QStringLiteral("Cannot restore save snapshot: folder or archive missing."), true);
        return false;
    }
    QDir().mkpath(localDir);
    QProcess tar;
    tar.start(QStringLiteral("tar"), {QStringLiteral("-xzf"), snapshotPath, QStringLiteral("-C"), localDir});
    const bool ok = tar.waitForFinished(15000) && tar.exitCode() == 0;
    emit operationStatus(
        ok ? QStringLiteral("Restored save snapshot cleanly.")
           : QStringLiteral("Failed to extract save snapshot."),
        !ok);
    if (ok) emit cloudSaveStatusChanged(gameId);
    return ok;
}

void EpicCloudSaveService::openSaveFolder(const QString& gameId) const {
    const QString dir = resolveLocalSaveDirForGame(gameId);
    if (dir.isEmpty()) return;
    QDir().mkpath(dir);
    QDesktopServices::openUrl(QUrl::fromLocalFile(dir));
}

QVariantMap EpicCloudSaveService::getCloudSaveStatus(const QString& gameId) const {
    QVariantMap m;
    const QString localDir = resolveLocalSaveDirForGame(gameId);
    m[QStringLiteral("configured")] = !localDir.isEmpty();
    m[QStringLiteral("localSaveDir")] = localDir;
    m[QStringLiteral("isSyncing")] = m_syncingGames.contains(gameId);
    m[QStringLiteral("snapshots")] = listLocalSnapshots(gameId);

    int localFileCount = 0;
    if (!localDir.isEmpty() && QDir(localDir).exists()) {
        QStringList includes;
        QStringList excludes;
        if (m_db) {
            if (auto gOpt = m_db->getGame(gameId); gOpt.has_value()) {
                includes = gOpt->epicCloudIncludeList;
                excludes = gOpt->epicCloudExcludeList;
            }
        }
        localFileCount = scanLocalSaveFiles(localDir, includes, excludes).size();
    }
    m[QStringLiteral("localFileCount")] = localFileCount;

    if (m_db) {
        if (auto st = m_db->getCloudSaveState(gameId); st.has_value() && st->lastSyncEpoch > 0) {
            m[QStringLiteral("lastSyncEpoch")] = st->lastSyncEpoch;
            m[QStringLiteral("lastSyncFormatted")] =
                QDateTime::fromSecsSinceEpoch(st->lastSyncEpoch).toString(QStringLiteral("MMM d, yyyy HH:mm"));
        } else {
            m[QStringLiteral("lastSyncEpoch")] = 0;
            m[QStringLiteral("lastSyncFormatted")] = QStringLiteral("Never synced");
        }
    }
    return m;
}

void EpicCloudSaveService::resolveConflict(const QString& gameId, const QString& resolution) {
    if (gameId.trimmed().isEmpty()) return;
    const QString res = resolution.trimmed().toLower();
    if (res == QLatin1String("download")) {
        syncGameSaves(gameId, QStringLiteral("download"));
    } else if (res == QLatin1String("upload")) {
        syncGameSaves(gameId, QStringLiteral("upload"));
    }
}

void EpicCloudSaveService::saveStateSnapshot(const QString& gameId,
                                             const QList<LocalFileEntry>& files,
                                             const QString& manifestHash)
{
    if (!m_db) return;
    DatabaseManager::CloudSaveState st;
    st.gameId = gameId;
    st.lastSyncEpoch = QDateTime::currentSecsSinceEpoch();
    st.lastManifestHash = manifestHash;
    for (const LocalFileEntry& lf : files) {
        QVariantMap fm;
        fm[QStringLiteral("sha1")] = QString::fromLatin1(lf.sha1.toHex());
        fm[QStringLiteral("size")] = lf.size;
        fm[QStringLiteral("mtime")] = lf.mtimeEpoch;
        st.trackedFiles.insert(lf.relativePath, fm);
    }
    m_db->saveCloudSaveState(st);
}

void EpicCloudSaveService::finishSync(const QString& gameId,
                                      bool ok,
                                      const QString& outcome,
                                      const QVariantMap& details,
                                      const QString& statusMsg,
                                      bool isError,
                                      std::function<void(bool, const QString&, const QVariantMap&)> callback)
{
    m_syncingGames.remove(gameId);
    emit syncingChanged();
    emit cloudSaveStatusChanged(gameId);
    if (!statusMsg.isEmpty()) {
        emit operationStatus(statusMsg, isError);
    }
    if (callback) {
        callback(ok, outcome, details);
    }
}

void EpicCloudSaveService::syncGameSaves(const QString& gameId,
                                         const QString& mode,
                                         std::function<void(bool, const QString&, const QVariantMap&)> callback)
{
    if (!m_db || !m_epicSvc || !m_epicSvc->isSignedIn()) {
        if (callback) callback(false, QStringLiteral("not_signed_in"), {});
        return;
    }
    if (m_syncingGames.contains(gameId)) {
        if (callback) callback(false, QStringLiteral("busy"), {});
        return;
    }

    auto gOpt = m_db->getGame(gameId);
    if (!gOpt.has_value() || !gOpt->isEpic()) {
        if (callback) callback(false, QStringLiteral("not_epic"), {});
        return;
    }
    const GameRecord game = *gOpt;
    const QString localDir = resolveLocalSaveDirForGame(gameId);
    if (localDir.isEmpty()) {
        if (callback) callback(true, QStringLiteral("not_configured"), {});
        return;
    }

    m_syncingGames.insert(gameId);
    emit syncingChanged();
    emit cloudSaveStatusChanged(gameId);

    m_epicSvc->ensureValidToken([this, game, localDir, mode, callback](bool tokenOk) {
        if (!tokenOk) {
            finishSync(game.id, false, QStringLiteral("auth_failed"), {},
                       QStringLiteral("Cloud save sync skipped: Epic session expired."), true, callback);
            return;
        }
        const QString accountId = m_epicSvc->accountId();
        const QString token = m_epicSvc->accessToken();

        fetchRemoteSaveIndex(game, accountId, token,
            [this, game, accountId, token, localDir, mode, callback](
                bool idxOk,
                const QList<RemoteManifestEntry>& manifests,
                const QHash<QString, QString>& chunkReadLinks,
                const QString& error) {
                if (!idxOk) {
                    finishSync(game.id, false, QStringLiteral("network_error"), {},
                               QStringLiteral("Cloud save query failed: %1").arg(error), true, callback);
                    return;
                }

                QStringList inc = game.epicCloudIncludeList;
                QStringList exc = game.epicCloudExcludeList;
                if (inc.isEmpty() && exc.isEmpty()) {
                    if (auto libOpt = m_db->getEpicLibraryItem(game.epicAppName); libOpt.has_value()) {
                        inc = libOpt->cloudIncludeList;
                        exc = libOpt->cloudExcludeList;
                    }
                }

                const QList<LocalFileEntry> localFiles = scanLocalSaveFiles(localDir, inc, exc);
                qint64 localLatest = 0;
                for (const LocalFileEntry& lf : localFiles) {
                    localLatest = qMax(localLatest, lf.mtimeEpoch);
                }

                const bool hasRemote = !manifests.isEmpty();
                const RemoteManifestEntry latestRemote = hasRemote ? manifests.first() : RemoteManifestEntry{};
                const auto prevState = m_db->getCloudSaveState(game.id);

                const QString cleanMode = mode.trimmed().toLower();
                if (cleanMode == QLatin1String("download")) {
                    if (!hasRemote) {
                        finishSync(game.id, true, QStringLiteral("up_to_date"), {},
                                   QStringLiteral("No cloud saves found on Epic servers for '%1'.").arg(game.title), false, callback);
                        return;
                    }
                    performDownloadSync(game, localDir, latestRemote, chunkReadLinks, callback);
                    return;
                }
                if (cleanMode == QLatin1String("upload")) {
                    if (localFiles.isEmpty()) {
                        finishSync(game.id, true, QStringLiteral("up_to_date"), {},
                                   QStringLiteral("No local save files to upload for '%1'.").arg(game.title), false, callback);
                        return;
                    }
                    performUploadSync(game, accountId, token, localDir, localFiles, callback);
                    return;
                }

                // Auto sync
                const SyncDecision decision = evaluateSyncState(
                    localFiles, localLatest, hasRemote, latestRemote.lastModifiedEpoch, latestRemote.hash, prevState);
                switch (decision) {
                case SyncDecision::UpToDate:
                case SyncDecision::NotConfigured:
                    finishSync(game.id, true, QStringLiteral("up_to_date"), {}, QString(), false, callback);
                    break;
                case SyncDecision::DownloadRecommended:
                    performDownloadSync(game, localDir, latestRemote, chunkReadLinks, callback);
                    break;
                case SyncDecision::UploadRecommended:
                    performUploadSync(game, accountId, token, localDir, localFiles, callback);
                    break;
                case SyncDecision::Conflict: {
                    QVariantMap conflict;
                    conflict[QStringLiteral("gameId")] = game.id;
                    conflict[QStringLiteral("gameTitle")] = game.title;
                    conflict[QStringLiteral("localSaveDir")] = localDir;
                    conflict[QStringLiteral("localFileCount")] = localFiles.size();
                    conflict[QStringLiteral("localTimestamp")] = localLatest;
                    conflict[QStringLiteral("localLatestEpoch")] = localLatest;
                    conflict[QStringLiteral("localTimeFormatted")] =
                        localLatest > 0 ? QDateTime::fromSecsSinceEpoch(localLatest).toString(QStringLiteral("MMM d, yyyy HH:mm:ss"))
                                        : QStringLiteral("Unknown");
                    conflict[QStringLiteral("cloudTimestamp")] = latestRemote.lastModifiedEpoch;
                    conflict[QStringLiteral("remoteLatestEpoch")] = latestRemote.lastModifiedEpoch;
                    conflict[QStringLiteral("cloudTimeFormatted")] =
                        latestRemote.lastModifiedEpoch > 0
                            ? QDateTime::fromSecsSinceEpoch(latestRemote.lastModifiedEpoch).toString(QStringLiteral("MMM d, yyyy HH:mm:ss"))
                            : QStringLiteral("Unknown");
                    conflict[QStringLiteral("triggeredByLaunch")] = static_cast<bool>(callback);
                    emit syncConflictDetected(game.id, conflict);
                    finishSync(game.id, false, QStringLiteral("conflict"), conflict, QString(), false, callback);
                    break;
                }
                }
            });
    });
}

void EpicCloudSaveService::fetchRemoteSaveIndex(
    const GameRecord& game,
    const QString& accountId,
    const QString& accessToken,
    std::function<void(bool, const QList<RemoteManifestEntry>&, const QHash<QString, QString>&, const QString&)> callback)
{
    const QString urlStr = QStringLiteral("%1/%2/%3/")
                               .arg(QLatin1String(kCloudStorageBaseUrl), accountId, game.epicAppName);
    QNetworkRequest req{QUrl(urlStr)};
    req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken.toUtf8());
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kCloudUserAgent));

    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [reply, callback]() {
        const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const QByteArray body = reply->readAll();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        // 404 means no cloud saves have ever been uploaded for this game yet
        if (httpStatus == 404) {
            if (callback) callback(true, {}, {}, QString());
            return;
        }
        if (!ok) {
            if (callback) callback(false, {}, {}, errStr);
            return;
        }

        const QJsonObject root = QJsonDocument::fromJson(body).object();
        const QJsonObject filesObj = root.value(QStringLiteral("files")).toObject();

        QList<RemoteManifestEntry> manifests;
        QHash<QString, QString> chunkLinks;
        for (auto it = filesObj.constBegin(); it != filesObj.constEnd(); ++it) {
            const QString key = it.key();
            const QJsonObject fo = it.value().toObject();
            const QString readLink = fo.value(QStringLiteral("readLink")).toString().trimmed();
            if (readLink.isEmpty()) continue;

            if (key.contains(QStringLiteral(".manifest"), Qt::CaseInsensitive)) {
                RemoteManifestEntry m;
                m.manifestPath = key;
                m.readLink = readLink;
                m.hash = fo.value(QStringLiteral("hash")).toString();
                m.lastModifiedEpoch = parseIsoEpoch(fo.value(QStringLiteral("lastModified")).toString());
                manifests.append(m);
            } else {
                chunkLinks.insert(key, readLink);
                chunkLinks.insert(QFileInfo(key).fileName(), readLink);
            }
        }

        std::sort(manifests.begin(), manifests.end(), [](const RemoteManifestEntry& a, const RemoteManifestEntry& b) {
            if (a.lastModifiedEpoch != b.lastModifiedEpoch) return a.lastModifiedEpoch > b.lastModifiedEpoch;
            return a.manifestPath > b.manifestPath;
        });

        if (callback) callback(true, manifests, chunkLinks, QString());
    });
}

void EpicCloudSaveService::performDownloadSync(
    const GameRecord& game,
    const QString& localDir,
    const RemoteManifestEntry& latestManifest,
    const QHash<QString, QString>& chunkReadLinks,
    std::function<void(bool, const QString&, const QVariantMap&)> callback)
{
    // Always create a local safety snapshot before overwriting saves!
    createLocalSafetySnapshot(game.id, localDir);
    QDir().mkpath(localDir);

    QNetworkRequest req{QUrl(latestManifest.readLink)};
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, game, localDir, latestManifest, chunkReadLinks, callback]() {
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const QByteArray rawManifest = ok ? reply->readAll() : QByteArray();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (!ok || rawManifest.isEmpty()) {
            finishSync(game.id, false, QStringLiteral("download_failed"), {},
                       QStringLiteral("Failed to download cloud save manifest: %1").arg(errStr), true, callback);
            return;
        }

        EpicManifest parsed;
        QString parseErr;
        if (!EpicManifestParser::parse(rawManifest, parsed, &parseErr)) {
            finishSync(game.id, false, QStringLiteral("parse_failed"), {},
                       QStringLiteral("Invalid cloud save manifest: %1").arg(parseErr), true, callback);
            return;
        }

        // Collect unique chunk GUIDs needed
        QStringList neededGuids;
        QSet<QString> seen;
        for (const EpicFileManifest& fm : parsed.files) {
            for (const EpicChunkPart& p : fm.chunkParts) {
                if (!seen.contains(p.chunkGuid)) {
                    seen.insert(p.chunkGuid);
                    neededGuids.append(p.chunkGuid);
                }
            }
        }

        struct DlState {
            EpicManifest manifest;
            QHash<QString, QByteArray> uncompressedChunks;
            int remaining = 0;
            bool failed = false;
        };
        auto st = std::make_shared<DlState>();
        st->manifest = parsed;
        st->remaining = neededGuids.size();

        auto assembleFiles = [this, game, localDir, latestManifest, st, callback]() {
            if (st->failed) return;
            for (const EpicFileManifest& fm : st->manifest.files) {
                QString rel = fm.filename;
                rel.replace(QLatin1Char('\\'), QLatin1Char('/'));
                while (rel.startsWith(QLatin1Char('/'))) rel.remove(0, 1);
                const QString dstPath = QDir(localDir).filePath(rel);
                QDir().mkpath(QFileInfo(dstPath).absolutePath());
                QFile out(dstPath);
                if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) continue;
                for (const EpicChunkPart& part : fm.chunkParts) {
                    const QByteArray buf = st->uncompressedChunks.value(part.chunkGuid);
                    if (static_cast<qint64>(part.offset) + static_cast<qint64>(part.size) <= buf.size()) {
                        out.write(buf.constData() + part.offset, part.size);
                    }
                }
                out.close();
            }

            const auto freshLocal = scanLocalSaveFiles(localDir);
            saveStateSnapshot(game.id, freshLocal, latestManifest.hash);
            finishSync(game.id, true, QStringLiteral("downloaded"), {},
                       QStringLiteral("Downloaded cloud saves for '%1'.").arg(game.title), false, callback);
        };

        if (neededGuids.isEmpty()) {
            assembleFiles();
            return;
        }

        for (const QString& guid : neededGuids) {
            const EpicChunkInfo* ci = st->manifest.findChunk(guid);
            QString readUrl;
            if (ci) {
                const QString relPath = ci->relativeChunkPath(st->manifest.chunksSubdir());
                readUrl = chunkReadLinks.value(relPath);
                if (readUrl.isEmpty()) {
                    readUrl = chunkReadLinks.value(QFileInfo(relPath).fileName());
                }
            }
            if (readUrl.isEmpty()) {
                // Fallback match by GUID substring
                for (auto it = chunkReadLinks.constBegin(); it != chunkReadLinks.constEnd(); ++it) {
                    if (it.key().contains(guid, Qt::CaseInsensitive)) {
                        readUrl = it.value();
                        break;
                    }
                }
            }
            if (readUrl.isEmpty()) {
                st->failed = true;
                finishSync(game.id, false, QStringLiteral("missing_chunk"), {},
                           QStringLiteral("Cloud save chunk missing on server."), true, callback);
                return;
            }

            QNetworkRequest cReq{QUrl(readUrl)};
            cReq.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
            QNetworkReply* cReply = m_nam.get(cReq);
            const QByteArray expectedSha = ci ? ci->shaHash : QByteArray();
            connect(cReply, &QNetworkReply::finished, this, [this, cReply, game, guid, expectedSha, st, assembleFiles, callback]() {
                const bool cOk = (cReply->error() == QNetworkReply::NoError);
                const QByteArray raw = cOk ? cReply->readAll() : QByteArray();
                cReply->deleteLater();
                if (st->failed) return;

                QByteArray uncomp;
                if (!cOk || !EpicManifestParser::decompressChunk(raw, expectedSha, uncomp)) {
                    st->failed = true;
                    finishSync(game.id, false, QStringLiteral("chunk_failed"), {},
                               QStringLiteral("Failed to download cloud save chunk."), true, callback);
                    return;
                }
                st->uncompressedChunks.insert(guid, uncomp);
                if (--st->remaining == 0) {
                    assembleFiles();
                }
            });
        }
    });
}

void EpicCloudSaveService::performUploadSync(
    const GameRecord& game,
    const QString& accountId,
    const QString& accessToken,
    const QString& localDir,
    const QList<LocalFileEntry>& localFiles,
    std::function<void(bool, const QString&, const QVariantMap&)> callback)
{
    // Package local files into 1 MiB Epic chunks + JSON manifest
    constexpr qint64 kChunkWindow = 1024 * 1024;
    QList<EpicChunkInfo> chunks;
    QList<EpicFileManifest> fileManifests;
    QHash<QString, QByteArray> payloadsByRemotePath;

    QByteArray currentBuf;
    currentBuf.reserve(kChunkWindow);
    QString currentGuid = QUuid::createUuid().toString(QUuid::Id128).toUpper();

    auto flushCurrentChunk = [&]() {
        if (currentBuf.isEmpty()) return;
        quint64 rolling = 0;
        QByteArray sha1;
        const QByteArray rawChunk = EpicManifestParser::buildChunk(currentGuid, currentBuf, &rolling, &sha1);

        EpicChunkInfo info;
        info.guid = currentGuid;
        info.hash = rolling;
        info.shaHash = sha1;
        info.groupNum = static_cast<quint8>(rolling % 100ULL);
        info.windowSize = static_cast<quint32>(currentBuf.size());
        info.fileSize = rawChunk.size();
        chunks.append(info);

        const QString remoteChunkPath = info.relativeChunkPath(QStringLiteral("ChunksV4"));
        payloadsByRemotePath.insert(remoteChunkPath, rawChunk);

        currentBuf.clear();
        currentGuid = QUuid::createUuid().toString(QUuid::Id128).toUpper();
    };

    for (const LocalFileEntry& lf : localFiles) {
        QFile f(lf.absolutePath);
        if (!f.open(QIODevice::ReadOnly)) continue;
        const QByteArray content = f.readAll();
        f.close();

        EpicFileManifest fm;
        fm.filename = lf.relativePath;
        fm.shaHash = lf.sha1;
        fm.fileSize = content.size();

        qint64 pos = 0;
        while (pos < content.size()) {
            const qint64 space = kChunkWindow - currentBuf.size();
            const qint64 take = qMin(space, content.size() - pos);
            EpicChunkPart part;
            part.chunkGuid = currentGuid;
            part.offset = static_cast<quint32>(currentBuf.size());
            part.size = static_cast<quint32>(take);
            currentBuf.append(content.constData() + pos, take);
            fm.chunkParts.append(part);
            pos += take;
            if (currentBuf.size() >= kChunkWindow) {
                flushCurrentChunk();
            }
        }
        fileManifests.append(fm);
    }
    flushCurrentChunk();

    const QString tsStamp = QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy.MM.dd-HH.mm.ss"));
    const QByteArray manifestBytes = EpicManifestParser::buildJsonManifest(game.epicAppName, tsStamp, fileManifests, chunks);
    const QString manifestRemotePath = QStringLiteral("manifests/%1.manifest").arg(tsStamp);
    const QString manifestHash = QString::fromLatin1(QCryptographicHash::hash(manifestBytes, QCryptographicHash::Sha1).toHex());
    payloadsByRemotePath.insert(manifestRemotePath, manifestBytes);

    // Request signed writeLinks from Epic Data Storage API
    QJsonArray reqFiles;
    for (auto it = payloadsByRemotePath.constBegin(); it != payloadsByRemotePath.constEnd(); ++it) {
        reqFiles.append(it.key());
    }
    QJsonObject reqBody;
    reqBody[QStringLiteral("files")] = reqFiles;

    const QString urlStr = QStringLiteral("%1/%2/%3/")
                               .arg(QLatin1String(kCloudStorageBaseUrl), accountId, game.epicAppName);
    QNetworkRequest req{QUrl(urlStr)};
    req.setRawHeader("Authorization", QByteArray("Bearer ") + accessToken.toUtf8());
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    req.setHeader(QNetworkRequest::UserAgentHeader, QLatin1String(kCloudUserAgent));

    QNetworkReply* reply = m_nam.post(req, QJsonDocument(reqBody).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, game, localDir, localFiles, payloadsByRemotePath, manifestHash, callback]() {
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const QByteArray body = ok ? reply->readAll() : QByteArray();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        if (!ok) {
            finishSync(game.id, false, QStringLiteral("upload_links_failed"), {},
                       QStringLiteral("Failed to request cloud save upload links: %1").arg(errStr), true, callback);
            return;
        }

        const QJsonObject filesObj = QJsonDocument::fromJson(body).object().value(QStringLiteral("files")).toObject();
        struct UploadTracker {
            int remaining = 0;
            bool failed = false;
        };
        auto tracker = std::make_shared<UploadTracker>();
        QList<QPair<QString, QByteArray>> toPut;
        for (auto it = payloadsByRemotePath.constBegin(); it != payloadsByRemotePath.constEnd(); ++it) {
            const QString writeLink = filesObj.value(it.key()).toObject().value(QStringLiteral("writeLink")).toString().trimmed();
            if (!writeLink.isEmpty()) {
                toPut.append({writeLink, it.value()});
            }
        }
        if (toPut.isEmpty()) {
            finishSync(game.id, false, QStringLiteral("no_write_links"), {},
                       QStringLiteral("Epic returned no upload links for cloud saves."), true, callback);
            return;
        }

        tracker->remaining = toPut.size();
        for (const auto& item : toPut) {
            QNetworkRequest putReq{QUrl(item.first)};
            putReq.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/octet-stream"));
            QNetworkReply* putReply = m_nam.put(putReq, item.second);
            connect(putReply, &QNetworkReply::finished, this, [this, putReply, game, localFiles, manifestHash, tracker, callback]() {
                const bool pOk = (putReply->error() == QNetworkReply::NoError);
                const QString pErr = putReply->errorString();
                putReply->deleteLater();
                if (tracker->failed) return;
                if (!pOk) {
                    tracker->failed = true;
                    finishSync(game.id, false, QStringLiteral("upload_failed"), {},
                               QStringLiteral("Cloud save upload failed: %1").arg(pErr), true, callback);
                    return;
                }
                if (--tracker->remaining == 0) {
                    saveStateSnapshot(game.id, localFiles, manifestHash);
                    finishSync(game.id, true, QStringLiteral("uploaded"), {},
                               QStringLiteral("Uploaded cloud saves for '%1'.").arg(game.title), false, callback);
                }
            });
        }
    });
}

} // namespace Tsuki

