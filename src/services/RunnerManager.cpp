#include "RunnerManager.h"
#include <QProcess>
#include <QStandardPaths>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QUuid>
#include <QFile>
#include <QSet>
#include <QRegularExpression>

namespace Tsuki {

RunnerManager::RunnerManager(DatabaseManager* db, AppSettings* settings, DownloadManager* dl, QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_dl(dl)
{
    detectInstalledRunners();
    populateFallbackReleases(QStringLiteral("proton-ge"));
}

QList<RunnerRecord> RunnerManager::installedRunners() const {
    return m_db->getAllRunners();
}

QVariantList RunnerManager::installedRunnersVariant() const {
    QVariantList list;
    const QList<RunnerRecord> all = m_db->getAllRunners();
    const QString defId = m_settings->defaultRunnerId();
    for (const RunnerRecord& r : all) {
        QVariantMap m = r.toVariantMap();
        m["isDefault"] = (r.id == defId);
        list.append(m);
    }
    return list;
}

QVariantMap RunnerManager::getRunnerMap(const QString& runnerId) const {
    auto r = m_db->getRunner(runnerId);
    if (!r.has_value()) return QVariantMap();
    QVariantMap m = r->toVariantMap();
    m["isDefault"] = (r->id == m_settings->defaultRunnerId());
    return m;
}

std::optional<RunnerRecord> RunnerManager::resolveRunner(const QString& preferredRunnerId) const {
    if (!preferredRunnerId.isEmpty()) {
        auto r = m_db->getRunner(preferredRunnerId);
        if (r.has_value() && QFileInfo::exists(r->binaryPath)) {
            return r;
        }
    }
    const QString defId = m_settings->defaultRunnerId();
    if (!defId.isEmpty()) {
        auto r = m_db->getRunner(defId);
        if (r.has_value() && QFileInfo::exists(r->binaryPath)) {
            return r;
        }
    }
    const QList<RunnerRecord> all = m_db->getAllRunners();
    for (const RunnerRecord& r : all) {
        if (QFileInfo::exists(r.binaryPath)) {
            return r;
        }
    }
    return std::nullopt;
}

QString RunnerManager::runnerTagForId(const QString& runnerId) const {
    auto r = resolveRunner(runnerId);
    if (!r.has_value()) return QStringLiteral("WINE");
    if (r->type == QStringLiteral("proton-cachyos")) return QStringLiteral("CACHYOS");
    if (r->type == QStringLiteral("proton-ge")) return QStringLiteral("PROTON-GE");
    if (r->type == QStringLiteral("proton")) return QStringLiteral("PROTON");
    if (r->type == QStringLiteral("wine-staging")) return QStringLiteral("STAGING");
    if (r->type == QStringLiteral("custom")) return QStringLiteral("CUSTOM");
    return QStringLiteral("WINE");
}

QString RunnerManager::findWineBinaryForRunner(const RunnerRecord& runner) const {
    if (!runner.isProton()) {
        return runner.binaryPath;
    }
    // Proton directories keep wine inside files/bin/wine or dist/bin/wine
    const QStringList candidates = {
        runner.path + QStringLiteral("/files/bin/wine"),
        runner.path + QStringLiteral("/files/bin/wine64"),
        runner.path + QStringLiteral("/dist/bin/wine"),
        runner.path + QStringLiteral("/dist/bin/wine64")
    };
    for (const QString& c : candidates) {
        if (QFileInfo::exists(c)) return c;
    }
    const QString sysWine = QStandardPaths::findExecutable(QStringLiteral("wine"));
    return sysWine.isEmpty() ? runner.binaryPath : sysWine;
}

QString RunnerManager::findWineserverBinaryForRunner(const RunnerRecord& runner) const {
    if (!runner.isProton()) {
        QFileInfo fi(runner.binaryPath);
        const QString sibling = fi.absolutePath() + QStringLiteral("/wineserver");
        if (QFileInfo::exists(sibling)) return sibling;
    } else {
        const QStringList candidates = {
            runner.path + QStringLiteral("/files/bin/wineserver"),
            runner.path + QStringLiteral("/dist/bin/wineserver")
        };
        for (const QString& c : candidates) {
            if (QFileInfo::exists(c)) return c;
        }
    }
    return QStandardPaths::findExecutable(QStringLiteral("wineserver"));
}

QStringList RunnerManager::findDxvkDirectories() const {
    QStringList dirs;
    const QStringList searchRoots = {
        AppSettings::toolsDir() + QStringLiteral("/dxvk"),
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/dxvk"),
        QStringLiteral("/usr/share/dxvk")
    };
    for (const QString& root : searchRoots) {
        QDir d(root);
        if (!d.exists()) continue;
        if (QFileInfo::exists(root + QStringLiteral("/x64/d3d11.dll")) ||
            QFileInfo::exists(root + QStringLiteral("/x32/d3d11.dll"))) {
            dirs.append(root);
        }
        const QFileInfoList sub = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed);
        for (const QFileInfo& fi : sub) {
            if (QFileInfo::exists(fi.absoluteFilePath() + QStringLiteral("/x64/d3d11.dll"))) {
                dirs.append(fi.absoluteFilePath());
            }
        }
    }
    // Also check Proton-GE embedded dxvk
    for (const RunnerRecord& r : m_db->getAllRunners()) {
        const QString pDxvk = r.path + QStringLiteral("/files/lib/wine/dxvk");
        if (QDir(pDxvk).exists()) dirs.append(pDxvk);
    }
    return dirs;
}

QStringList RunnerManager::findVkd3dDirectories() const {
    QStringList dirs;
    const QStringList searchRoots = {
        AppSettings::toolsDir() + QStringLiteral("/vkd3d"),
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/vkd3d"),
        QStringLiteral("/usr/share/vkd3d-proton")
    };
    for (const QString& root : searchRoots) {
        QDir d(root);
        if (!d.exists()) continue;
        if (QFileInfo::exists(root + QStringLiteral("/x64/d3d12.dll"))) {
            dirs.append(root);
        }
        const QFileInfoList sub = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed);
        for (const QFileInfo& fi : sub) {
            if (QFileInfo::exists(fi.absoluteFilePath() + QStringLiteral("/x64/d3d12.dll"))) {
                dirs.append(fi.absoluteFilePath());
            }
        }
    }
    for (const RunnerRecord& r : m_db->getAllRunners()) {
        const QString pVkd3d = r.path + QStringLiteral("/files/lib/wine/vkd3d-proton");
        if (QDir(pVkd3d).exists()) dirs.append(pVkd3d);
    }
    return dirs;
}

bool RunnerManager::isReleaseInstalled(const QString& tagName, const QString& name) const {
    const auto all = m_db->getAllRunners();
    for (const auto& r : all) {
        if (!tagName.isEmpty() && (r.version.contains(tagName, Qt::CaseInsensitive) ||
                                   r.name.contains(tagName, Qt::CaseInsensitive) ||
                                   r.path.contains(tagName, Qt::CaseInsensitive))) {
            return true;
        }
        if (!name.isEmpty() && (r.name.contains(name, Qt::CaseInsensitive) ||
                                r.version.contains(name, Qt::CaseInsensitive) ||
                                r.path.contains(name, Qt::CaseInsensitive))) {
            return true;
        }
    }
    return false;
}

void RunnerManager::scanSteamRunners() {
    QSet<QString> steamLibraries;

    const QStringList steamRoots = {
        QDir::homePath() + QStringLiteral("/.local/share/Steam"),
        QDir::homePath() + QStringLiteral("/.steam/steam"),
        QDir::homePath() + QStringLiteral("/.steam/root"),
        QDir::homePath() + QStringLiteral("/.var/app/com.valvesoftware.Steam/data/Steam"),
        QDir::homePath() + QStringLiteral("/snap/steam/common/.local/share/Steam")
    };

    for (const QString& sRoot : steamRoots) {
        if (!QDir(sRoot).exists()) continue;
        steamLibraries.insert(QDir::cleanPath(sRoot));

        const QStringList vdfCandidates = {
            sRoot + QStringLiteral("/config/libraryfolders.vdf"),
            sRoot + QStringLiteral("/steamapps/libraryfolders.vdf")
        };
        for (const QString& vdfPath : vdfCandidates) {
            QFile vdfFile(vdfPath);
            if (!vdfFile.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
            const QString content = QString::fromUtf8(vdfFile.readAll());
            vdfFile.close();

            static const QRegularExpression pathRegex(QStringLiteral(R"rx("path"\s+"([^"]+)")rx"));
            auto it = pathRegex.globalMatch(content);
            while (it.hasNext()) {
                const auto match = it.next();
                const QString libPath = QDir::cleanPath(match.captured(1).trimmed());
                if (!libPath.isEmpty() && QDir(libPath).exists()) {
                    steamLibraries.insert(libPath);
                }
            }
        }
    }

    for (const QString& libRoot : steamLibraries) {
        const QString commonDir = libRoot + QStringLiteral("/steamapps/common");
        QDir d(commonDir);
        if (!d.exists()) continue;

        const QFileInfoList subDirs = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& fi : subDirs) {
            const QString name = fi.fileName();
            if (name.contains(QStringLiteral("proton"), Qt::CaseInsensitive)) {
                const QString protonBin = fi.absoluteFilePath() + QStringLiteral("/proton");
                if (QFileInfo::exists(protonBin)) {
                    inspectAndRegisterRunnerDir(fi.absoluteFilePath(), true, QStringLiteral("Steam"));
                }
            }
        }
    }
}

void RunnerManager::detectInstalledRunners() {
    // 1. Prune non-existent runners from DB
    for (const RunnerRecord& existing : m_db->getAllRunners()) {
        if (!QFileInfo::exists(existing.binaryPath)) {
            m_db->removeRunner(existing.id);
        }
    }

    // 2. System Wine
    const QString sysWine = QStandardPaths::findExecutable(QStringLiteral("wine"));
    if (!sysWine.isEmpty()) {
        QString versionStr = QStringLiteral("System");
        bool isStaging = false;
        QProcess proc;
        proc.start(sysWine, {QStringLiteral("--version")});
        if (proc.waitForFinished(2500)) {
            versionStr = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
            if (versionStr.contains(QStringLiteral("Staging"), Qt::CaseInsensitive)) {
                isStaging = true;
            }
        }
        RunnerRecord sysRec;
        sysRec.id = QStringLiteral("system-wine");
        sysRec.name = isStaging ? QStringLiteral("System Wine-Staging (%1)").arg(versionStr)
                                : QStringLiteral("System Wine (%1)").arg(versionStr);
        sysRec.type = isStaging ? QStringLiteral("wine-staging") : QStringLiteral("wine");
        sysRec.version = versionStr;
        sysRec.path = QFileInfo(sysWine).absolutePath();
        sysRec.binaryPath = sysWine;
        sysRec.isSystem = true;
        if (auto old = m_db->getRunner(sysRec.id); old.has_value()) {
            sysRec.settings = old->settings;
        }
        m_db->saveRunner(sysRec);
    }

    // 3. Scan Steam Proton installations (steamapps/common/Proton*)
    scanSteamRunners();

    // 4. Scan Tsuki runner dir and common Linux compatibility tool locations
    const QStringList scanRoots = {
        m_settings->defaultRunnerLocation(),
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/proton"),
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/wine"),
        QDir::homePath() + QStringLiteral("/.local/share/Steam/compatibilitytools.d"),
        QDir::homePath() + QStringLiteral("/.steam/root/compatibilitytools.d"),
        QDir::homePath() + QStringLiteral("/.steam/steam/compatibilitytools.d"),
        QDir::homePath() + QStringLiteral("/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d"),
        QDir::homePath() + QStringLiteral("/snap/steam/common/.local/share/Steam/compatibilitytools.d"),
        QDir::homePath() + QStringLiteral("/.local/share/lutris/runners/wine"),
        QStringLiteral("/usr/share/steam/compatibilitytools.d")
    };

    for (const QString& root : scanRoots) {
        QDir d(root);
        if (!d.exists()) continue;
        const bool isExternal = (root != m_settings->defaultRunnerLocation());
        const QFileInfoList subDirs = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& sub : subDirs) {
            inspectAndRegisterRunnerDir(sub.absoluteFilePath(), isExternal);
        }
    }

    // Ensure a default runner is set if none is configured
    if (m_settings->defaultRunnerId().isEmpty()) {
        const QList<RunnerRecord> all = m_db->getAllRunners();
        if (!all.isEmpty()) {
            // Prefer Proton-GE or Proton-CachyOS if present, else any Proton, else first
            QString chosen = all.first().id;
            for (const RunnerRecord& r : all) {
                if (r.type == QStringLiteral("proton-ge") || r.type == QStringLiteral("proton-cachyos") || r.type == QStringLiteral("proton")) {
                    chosen = r.id;
                    break;
                }
            }
            m_settings->setDefaultRunnerId(chosen);
        }
    }

    emit runnersChanged();
}

void RunnerManager::inspectAndRegisterRunnerDir(const QString& dirPath, bool isSystemDir, const QString& sourceLabel) {
    QDir dir(dirPath);
    if (!dir.exists()) return;

    const QString folderName = dir.dirName();
    const QString protonBin = dirPath + QStringLiteral("/proton");
    const QString wineBin = dirPath + QStringLiteral("/bin/wine");
    const QString filesWineBin = dirPath + QStringLiteral("/files/bin/wine");

    RunnerRecord rec;
    if (QFileInfo::exists(protonBin)) {
        rec.binaryPath = protonBin;
        rec.path = dirPath;
        if (folderName.contains(QStringLiteral("CachyOS"), Qt::CaseInsensitive)) {
            rec.type = QStringLiteral("proton-cachyos");
        } else if (folderName.contains(QStringLiteral("GE"), Qt::CaseInsensitive)) {
            rec.type = QStringLiteral("proton-ge");
        } else {
            rec.type = QStringLiteral("proton");
        }
        rec.version = folderName;
        QFile verFile(dirPath + QStringLiteral("/version"));
        if (verFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString line = QString::fromUtf8(verFile.readLine()).trimmed();
            const QStringList parts = line.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            if (parts.size() >= 2) rec.version = parts.last();
        }
        if (!sourceLabel.isEmpty() && sourceLabel == QStringLiteral("Steam")) {
            rec.name = folderName.startsWith(QStringLiteral("Steam"), Qt::CaseInsensitive)
                           ? folderName
                           : QStringLiteral("Steam %1").arg(folderName);
        } else {
            rec.name = folderName;
        }
    } else if (QFileInfo::exists(wineBin) || QFileInfo::exists(filesWineBin)) {
        rec.binaryPath = QFileInfo::exists(wineBin) ? wineBin : filesWineBin;
        rec.path = dirPath;
        rec.type = folderName.contains(QStringLiteral("staging"), Qt::CaseInsensitive)
                       ? QStringLiteral("wine-staging")
                       : QStringLiteral("wine");
        rec.version = folderName;
        rec.name = folderName;
    } else {
        return;
    }

    QString cleanId = folderName.toLower();
    cleanId.replace(QRegularExpression(QStringLiteral("[^a-z0-9_.-]+")), QStringLiteral("_"));
    if (!sourceLabel.isEmpty()) {
        rec.id = sourceLabel.toLower() + QStringLiteral("-") + cleanId;
    } else {
        rec.id = QStringLiteral("runner-") + cleanId;
    }

    rec.isSystem = isSystemDir;
    if (auto existing = m_db->getRunner(rec.id); existing.has_value()) {
        rec.settings = existing->settings;
    }
    m_db->saveRunner(rec);
}

void RunnerManager::populateFallbackReleases(const QString& category) {
    m_availableReleases.clear();
    if (category == QStringLiteral("proton-ge")) {
        const QList<QPair<QString, QString>> items = {
            {QStringLiteral("GE-Proton10-4"), QStringLiteral("https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton10-4/GE-Proton10-4.tar.gz")},
            {QStringLiteral("GE-Proton9-27"), QStringLiteral("https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-27/GE-Proton9-27.tar.gz")},
            {QStringLiteral("GE-Proton9-25"), QStringLiteral("https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-25/GE-Proton9-25.tar.gz")},
            {QStringLiteral("GE-Proton9-20"), QStringLiteral("https://github.com/GloriousEggroll/proton-ge-custom/releases/download/GE-Proton9-20/GE-Proton9-20.tar.gz")}
        };
        for (const auto& pair : items) {
            QVariantMap m;
            m["tagName"] = pair.first;
            m["name"] = pair.first;
            m["category"] = QStringLiteral("proton-ge");
            m["downloadUrl"] = pair.second;
            m["fileName"] = pair.first + QStringLiteral(".tar.gz");
            m["sizeFormatted"] = QStringLiteral("~460 MB");
            m["publishedAt"] = QStringLiteral("Official Release");
            m["isInstalled"] = isReleaseInstalled(pair.first, pair.first);
            m_availableReleases.append(m);
        }
    } else if (category == QStringLiteral("proton-cachyos")) {
        const QList<QPair<QString, QString>> items = {
            {QStringLiteral("cachyos-11.0-20261015-slr"), QStringLiteral("https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20261015-slr/proton-cachyos-11.0-20261015-slr-x86_64.tar.xz")},
            {QStringLiteral("cachyos-11.0-20261014-slr"), QStringLiteral("https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20261014-slr/proton-cachyos-11.0-20261014-slr-x86_64.tar.xz")},
            {QStringLiteral("cachyos-11.0-20261005-slr"), QStringLiteral("https://github.com/CachyOS/proton-cachyos/releases/download/cachyos-11.0-20261005-slr/proton-cachyos-11.0-20261005-slr-x86_64.tar.xz")}
        };
        for (const auto& pair : items) {
            QVariantMap m;
            m["tagName"] = pair.first;
            m["name"] = QStringLiteral("proton-%1").arg(pair.first);
            m["category"] = QStringLiteral("proton-cachyos");
            m["downloadUrl"] = pair.second;
            m["fileName"] = QStringLiteral("proton-%1-x86_64.tar.xz").arg(pair.first);
            m["sizeFormatted"] = QStringLiteral("~800 MB");
            m["publishedAt"] = QStringLiteral("CachyOS Proton Release");
            m["isInstalled"] = isReleaseInstalled(pair.first, m["name"].toString());
            m_availableReleases.append(m);
        }
    } else if (category == QStringLiteral("wine") || category == QStringLiteral("wine-staging")) {
        const QList<QPair<QString, QString>> items = {
            {QStringLiteral("wine-10.2-staging-tkg-amd64"), QStringLiteral("https://github.com/Kron4ek/Wine-Builds/releases/download/10.2/wine-10.2-staging-tkg-amd64.tar.xz")},
            {QStringLiteral("wine-10.2-amd64"), QStringLiteral("https://github.com/Kron4ek/Wine-Builds/releases/download/10.2/wine-10.2-amd64.tar.xz")},
            {QStringLiteral("wine-9.22-staging-tkg-amd64"), QStringLiteral("https://github.com/Kron4ek/Wine-Builds/releases/download/9.22/wine-9.22-staging-tkg-amd64.tar.xz")}
        };
        for (const auto& pair : items) {
            QVariantMap m;
            m["tagName"] = pair.first;
            m["name"] = pair.first;
            m["category"] = category;
            m["downloadUrl"] = pair.second;
            m["fileName"] = pair.first + QStringLiteral(".tar.xz");
            m["sizeFormatted"] = QStringLiteral("~65 MB");
            m["publishedAt"] = QStringLiteral("Kron4ek Wine Builds");
            m["isInstalled"] = isReleaseInstalled(pair.first, pair.first);
            m_availableReleases.append(m);
        }
    } else if (category == QStringLiteral("dxvk")) {
        QVariantMap m;
        m["tagName"] = QStringLiteral("v2.5.3");
        m["name"] = QStringLiteral("DXVK v2.5.3");
        m["category"] = QStringLiteral("dxvk");
        m["downloadUrl"] = QStringLiteral("https://github.com/doitsujin/dxvk/releases/download/v2.5.3/dxvk-2.5.3.tar.gz");
        m["fileName"] = QStringLiteral("dxvk-2.5.3.tar.gz");
        m["sizeFormatted"] = QStringLiteral("~9 MB");
        m["publishedAt"] = QStringLiteral("Vulkan D3D9/10/11");
        m["isInstalled"] = false;
        m_availableReleases.append(m);
    } else if (category == QStringLiteral("vkd3d")) {
        QVariantMap m;
        m["tagName"] = QStringLiteral("v2.14.1");
        m["name"] = QStringLiteral("VKD3D-Proton v2.14.1");
        m["category"] = QStringLiteral("vkd3d");
        m["downloadUrl"] = QStringLiteral("https://github.com/HansKristian-Work/vkd3d-proton/releases/download/v2.14.1/vkd3d-proton-2.14.1.tar.zst");
        m["fileName"] = QStringLiteral("vkd3d-proton-2.14.1.tar.zst");
        m["sizeFormatted"] = QStringLiteral("~4 MB");
        m["publishedAt"] = QStringLiteral("Vulkan D3D12");
        m["isInstalled"] = false;
        m_availableReleases.append(m);
    }
    emit availableReleasesChanged();
}

void RunnerManager::fetchAvailableReleases(const QString& category) {
    populateFallbackReleases(category);

    QString apiUrl;
    if (category == QStringLiteral("proton-ge")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=15");
    } else if (category == QStringLiteral("proton-cachyos")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/CachyOS/proton-cachyos/releases?per_page=15");
    } else if (category == QStringLiteral("wine") || category == QStringLiteral("wine-staging")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=12");
    } else if (category == QStringLiteral("dxvk")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/doitsujin/dxvk/releases?per_page=10");
    } else if (category == QStringLiteral("vkd3d")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/HansKristian-Work/vkd3d-proton/releases?per_page=10");
    } else {
        return;
    }

    m_isFetchingReleases = true;
    emit isFetchingReleasesChanged();

    QNetworkRequest req{QUrl(apiUrl)};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0"));
    QNetworkReply* reply = m_nam.get(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, category]() {
        m_isFetchingReleases = false;
        emit isFetchingReleasesChanged();

        if (reply->error() != QNetworkReply::NoError) {
            reply->deleteLater();
            return; // Keep fallback releases
        }

        const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
        reply->deleteLater();
        if (!doc.isArray()) return;

        QVariantList fetched;
        const QJsonArray arr = doc.array();
        for (const QJsonValue& val : arr) {
            const QJsonObject rel = val.toObject();
            const QString tag = rel["tag_name"].toString();
            const QString pub = rel["published_at"].toString().left(10);
            const QJsonArray assets = rel["assets"].toArray();
            for (const QJsonValue& assetVal : assets) {
                const QJsonObject asset = assetVal.toObject();
                const QString fileName = asset["name"].toString();
                if (!fileName.endsWith(QStringLiteral(".tar.gz")) &&
                    !fileName.endsWith(QStringLiteral(".tar.xz")) &&
                    !fileName.endsWith(QStringLiteral(".tar.zst"))) {
                    continue;
                }
                if (fileName.contains(QStringLiteral("wow64")) || fileName.contains(QStringLiteral("x86.tar"))) {
                    continue;
                }
                if (category == QStringLiteral("proton-cachyos")) {
                    if (fileName.contains(QStringLiteral("arm64"), Qt::CaseInsensitive)) continue;
                    if (!fileName.contains(QStringLiteral("x86_64"), Qt::CaseInsensitive)) continue;
                    if (fileName.contains(QStringLiteral("x86_64_v3"), Qt::CaseInsensitive)) continue;
                }
                if (category == QStringLiteral("wine-staging") && !fileName.contains(QStringLiteral("staging"))) {
                    continue;
                }
                if (category == QStringLiteral("wine") && fileName.contains(QStringLiteral("staging"))) {
                    continue;
                }

                QVariantMap item;
                item["tagName"] = tag;
                item["name"] = fileName.chopped(fileName.endsWith(QStringLiteral(".tar.zst")) ? 8 : 7);
                item["category"] = category;
                item["downloadUrl"] = asset["browser_download_url"].toString();
                item["fileName"] = fileName;
                item["sizeFormatted"] = DownloadManager::formatBytes(asset["size"].toVariant().toLongLong());
                item["publishedAt"] = pub;
                item["isInstalled"] = isReleaseInstalled(tag, item["name"].toString());
                fetched.append(item);
                break;
            }
        }

        if (!fetched.isEmpty()) {
            m_availableReleases = fetched;
            emit availableReleasesChanged();
        }
    });
}

void RunnerManager::downloadRelease(const QString& category,
                                     const QString& tagName,
                                     const QString& downloadUrl,
                                     const QString& fileName)
{
    QString actualFileName = fileName;
    if (actualFileName.isEmpty()) {
        actualFileName = QUrl(downloadUrl).fileName();
        if (actualFileName.isEmpty()) {
            actualFileName = tagName + (category == QStringLiteral("proton-cachyos") ? QStringLiteral(".tar.xz") : QStringLiteral(".tar.gz"));
        }
    }
    downloadAndInstallRunner(tagName, category, downloadUrl, actualFileName);
}

void RunnerManager::downloadAndInstallRunner(const QString& tagName,
                                             const QString& category,
                                             const QString& downloadUrl,
                                             const QString& fileName)
{
    QString extractDir = m_settings->defaultRunnerLocation();
    if (category == QStringLiteral("dxvk")) {
        extractDir = AppSettings::toolsDir() + QStringLiteral("/dxvk");
    } else if (category == QStringLiteral("vkd3d")) {
        extractDir = AppSettings::toolsDir() + QStringLiteral("/vkd3d");
    }

    const QString destArchive = AppSettings::cacheDir() + QStringLiteral("/") + fileName;
    const QString taskId = QStringLiteral("runner-dl-") + tagName;

    emit runnerOperationStatus(QStringLiteral("Starting download of %1…").arg(tagName), false);

    m_dl->enqueueDownload(taskId,
                          QStringLiteral("Runner: %1").arg(tagName),
                          QUrl(downloadUrl),
                          destArchive,
                          extractDir,
                          [this, tagName, extractDir](bool ok, const QString& msg) {
                              if (ok) {
                                  // Enforce executable permissions on extracted binaries
                                  QDirIterator it(extractDir, {QStringLiteral("proton"), QStringLiteral("wine"), QStringLiteral("wineserver")},
                                                  QDir::Files, QDirIterator::Subdirectories);
                                  while (it.hasNext()) {
                                      it.next();
                                      QFile::setPermissions(it.filePath(),
                                                            QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                                                            QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                                                            QFileDevice::ReadOther | QFileDevice::ExeOther);
                                  }
                                  detectInstalledRunners();
                                  fetchAvailableReleases(QStringLiteral("proton-ge"));
                                  emit runnerOperationStatus(QStringLiteral("Installed %1 successfully.").arg(tagName), false);
                              } else {
                                  emit runnerOperationStatus(QStringLiteral("Failed to install %1: %2").arg(tagName, msg), true);
                              }
                          });
}

bool RunnerManager::uninstallRunner(const QString& runnerId) {
    return removeRunner(runnerId, true);
}

bool RunnerManager::removeRunner(const QString& runnerId, bool deleteFiles) {
    auto rec = m_db->getRunner(runnerId);
    if (!rec.has_value()) return false;
    if (rec->isSystem && deleteFiles) {
        deleteFiles = false; // Never delete system or Steam binaries
    }

    if (deleteFiles && !rec->path.isEmpty()) {
        const QString runnerBase = QDir::cleanPath(m_settings->defaultRunnerLocation());
        const QString targetPath = QDir::cleanPath(rec->path);
        if (targetPath.startsWith(runnerBase) && targetPath != runnerBase) {
            QDir(targetPath).removeRecursively();
        }
    }

    const bool ok = m_db->removeRunner(runnerId);
    if (ok) {
        if (m_settings->defaultRunnerId() == runnerId) {
            const auto remaining = m_db->getAllRunners();
            m_settings->setDefaultRunnerId(remaining.isEmpty() ? QString() : remaining.first().id);
        }
        emit runnersChanged();
        emit runnerOperationStatus(QStringLiteral("Runner removed."), false);
    }
    return ok;
}

bool RunnerManager::updateRunnerSettings(const QString& runnerId, const QVariantMap& settings) {
    auto rec = m_db->getRunner(runnerId);
    if (!rec.has_value()) return false;
    rec->settings = settings;
    const bool ok = m_db->saveRunner(*rec);
    if (ok) emit runnersChanged();
    return ok;
}

} // namespace Tsuki

