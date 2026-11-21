#include "RunnerManager.h"
#include "../core/SecretStore.h"
#include <QDateTime>
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

namespace {

QSet<QString> collectSteamLibraryRoots() {
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
    return steamLibraries;
}

bool containsNonEmptyRuntimeFiles(const QString& dirPath) {
    QDir d(dirPath);
    if (!d.exists()) return false;
    if (d.exists(QStringLiteral("v2")) || d.exists(QStringLiteral("v1"))) {
        return true;
    }
    QDirIterator it(dirPath, {QStringLiteral("*.so"), QStringLiteral("*.dll")}, QDir::Files, QDirIterator::Subdirectories);
    return it.hasNext();
}

QString unwrapExtractedRuntimeDir(const QString& candidate) {
    if (!QDir(candidate).exists()) return QString();
    QDir d(candidate);
    if (d.exists(QStringLiteral("v2")) || d.exists(QStringLiteral("v1")) ||
        !d.entryList({QStringLiteral("*.so")}, QDir::Files).isEmpty()) {
        return QDir::cleanPath(candidate);
    }
    const QFileInfoList subDirs = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (subDirs.size() == 1 && containsNonEmptyRuntimeFiles(subDirs.first().absoluteFilePath())) {
        return QDir::cleanPath(subDirs.first().absoluteFilePath());
    }
    return containsNonEmptyRuntimeFiles(candidate) ? QDir::cleanPath(candidate) : QString();
}

} // namespace

RunnerManager::RunnerManager(DatabaseManager* db, AppSettings* settings, DownloadManager* dl, QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_dl(dl)
{
    if (m_settings) {
        connect(m_settings, &AppSettings::runnerDefaultsChanged, this, &RunnerManager::runnersChanged);
    }
    detectInstalledRunners();
    populateFallbackReleases(QStringLiteral("proton-ge"));
}

QList<RunnerRecord> RunnerManager::installedRunners() const {
    return m_db->getAllRunners();
}

bool RunnerManager::canDeleteRunner(const QString& runnerId) const {
    auto r = m_db->getRunner(runnerId);
    if (!r.has_value()) return false;
    if (r->isSystem) return false;
    if (r->isSteam()) {
        return m_settings && m_settings->allowDeleteSteamRunners();
    }
    return true;
}

QVariantList RunnerManager::installedRunnersVariant() const {
    QVariantList list;
    const QList<RunnerRecord> all = m_db->getAllRunners();
    const QString defId = m_settings->defaultRunnerId();
    const bool allowSteamDelete = m_settings && m_settings->allowDeleteSteamRunners();
    for (const RunnerRecord& r : all) {
        QVariantMap m = r.toVariantMap();
        m["isDefault"] = (r.id == defId);
        m["canDelete"] = !r.isSystem && (!r.isSteam() || allowSteamDelete);
        list.append(m);
    }
    return list;
}

QVariantMap RunnerManager::getRunnerMap(const QString& runnerId) const {
    auto r = m_db->getRunner(runnerId);
    if (!r.has_value()) return QVariantMap();
    QVariantMap m = r->toVariantMap();
    m["isDefault"] = (r->id == m_settings->defaultRunnerId());
    m["canDelete"] = !r->isSystem && (!r->isSteam() || (m_settings && m_settings->allowDeleteSteamRunners()));
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
    if (r->type == QStringLiteral("proton-sarek")) return QStringLiteral("SAREK");
    if (r->type == QStringLiteral("proton-em")) return QStringLiteral("PROTON-EM");
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
    const QSet<QString> steamLibraries = collectSteamLibraryRoots();

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
                    inspectAndRegisterRunnerDir(fi.absoluteFilePath(), false, QStringLiteral("Steam"));
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
        const bool isReadOnlySystem = QDir::cleanPath(root).startsWith(QStringLiteral("/usr/"));
        const QFileInfoList subDirs = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& sub : subDirs) {
            inspectAndRegisterRunnerDir(sub.absoluteFilePath(), isReadOnlySystem);
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
        } else if (folderName.contains(QStringLiteral("Sarek"), Qt::CaseInsensitive)) {
            rec.type = QStringLiteral("proton-sarek");
        } else if (folderName.contains(QStringLiteral("Proton-EM"), Qt::CaseInsensitive) ||
                   folderName.contains(QStringLiteral("proton-em"), Qt::CaseInsensitive)) {
            rec.type = QStringLiteral("proton-em");
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
        const bool useV3 = m_settings && m_settings->preferX86_64V3Runners();
        const QString archSuffix = useV3 ? QStringLiteral("x86_64_v3") : QStringLiteral("x86_64");
        const QList<QString> tags = {
            QStringLiteral("cachyos-11.0-20261015-slr"),
            QStringLiteral("cachyos-11.0-20261014-slr"),
            QStringLiteral("cachyos-11.0-20261005-slr")
        };
        for (const QString& tag : tags) {
            QVariantMap m;
            m["tagName"] = tag;
            m["name"] = QStringLiteral("proton-%1-%2").arg(tag, archSuffix);
            m["category"] = QStringLiteral("proton-cachyos");
            m["downloadUrl"] = QStringLiteral("https://github.com/CachyOS/proton-cachyos/releases/download/%1/proton-%1-%2.tar.xz").arg(tag, archSuffix);
            m["fileName"] = QStringLiteral("proton-%1-%2.tar.xz").arg(tag, archSuffix);
            m["sizeFormatted"] = QStringLiteral("~800 MB");
            m["publishedAt"] = useV3 ? QStringLiteral("CachyOS Proton (x86_64_v3)") : QStringLiteral("CachyOS Proton Release");
            m["isInstalled"] = isReleaseInstalled(tag, m["name"].toString());
            m_availableReleases.append(m);
        }
    } else if (category == QStringLiteral("proton-sarek")) {
        const QList<QPair<QString, QString>> items = {
            {QStringLiteral("Proton-Sarek10-29"), QStringLiteral("https://github.com/pythonlover02/Proton-Sarek/releases/download/Proton-Sarek10-29/Proton-Sarek10-29.tar.gz")},
            {QStringLiteral("Proton-Sarek9-27"), QStringLiteral("https://github.com/pythonlover02/Proton-Sarek/releases/download/Proton-Sarek9-27/Proton-Sarek9-27.tar.gz")}
        };
        for (const auto& pair : items) {
            QVariantMap m;
            m["tagName"] = pair.first;
            m["name"] = pair.first;
            m["category"] = QStringLiteral("proton-sarek");
            m["downloadUrl"] = pair.second;
            m["fileName"] = pair.first + QStringLiteral(".tar.gz");
            m["sizeFormatted"] = QStringLiteral("~420 MB");
            m["publishedAt"] = QStringLiteral("Vulkan 1.1/1.2 Legacy GPU");
            m["isInstalled"] = isReleaseInstalled(pair.first, pair.first);
            m_availableReleases.append(m);
        }
    } else if (category == QStringLiteral("proton-em")) {
        const QList<QPair<QString, QString>> items = {
            {QStringLiteral("EM-10.0-30"), QStringLiteral("https://github.com/Etaash-mathamsetty/Proton/releases/download/EM-10.0-30/proton-EM-10.0-30.tar.xz")},
            {QStringLiteral("EM-10.0-25"), QStringLiteral("https://github.com/Etaash-mathamsetty/Proton/releases/download/EM-10.0-25/proton-EM-10.0-25.tar.xz")}
        };
        for (const auto& pair : items) {
            QVariantMap m;
            m["tagName"] = pair.first;
            m["name"] = QStringLiteral("proton-%1").arg(pair.first);
            m["category"] = QStringLiteral("proton-em");
            m["downloadUrl"] = pair.second;
            m["fileName"] = QStringLiteral("proton-%1.tar.xz").arg(pair.first);
            m["sizeFormatted"] = QStringLiteral("~460 MB");
            m["publishedAt"] = QStringLiteral("Proton-EM (Wayland/HDR)");
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

void RunnerManager::fetchAvailableReleases(const QString& category, bool forceRefresh) {
    m_activeReleaseCategory = category;

    constexpr qint64 kReleaseCacheTtlMs = 5 * 60 * 1000;
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (!forceRefresh && m_releaseCache.contains(category) &&
        (nowMs - m_releaseCacheTimeMs.value(category, 0)) < kReleaseCacheTtlMs) {
        QVariantList cached = m_releaseCache.value(category);
        for (QVariant& entryVar : cached) {
            QVariantMap m = entryVar.toMap();
            m["isInstalled"] = isReleaseInstalled(m.value(QStringLiteral("tagName")).toString(),
                                                  m.value(QStringLiteral("name")).toString());
            entryVar = m;
        }
        m_releaseCache[category] = cached;
        m_availableReleases = cached;
        emit availableReleasesChanged();
        return;
    }

    populateFallbackReleases(category);

    QString apiUrl;
    if (category == QStringLiteral("proton-ge")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=15");
    } else if (category == QStringLiteral("proton-cachyos")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/CachyOS/proton-cachyos/releases?per_page=15");
    } else if (category == QStringLiteral("proton-sarek")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/pythonlover02/Proton-Sarek/releases?per_page=15");
    } else if (category == QStringLiteral("proton-em")) {
        apiUrl = QStringLiteral("https://api.github.com/repos/Etaash-mathamsetty/Proton/releases?per_page=15");
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

        const bool preferV3 = m_settings && m_settings->preferX86_64V3Runners();
        QVariantList fetched;
        const QJsonArray arr = doc.array();
        for (const QJsonValue& val : arr) {
            const QJsonObject rel = val.toObject();
            const QString tag = rel["tag_name"].toString();
            const QString pub = rel["published_at"].toString().left(10);
            const QJsonArray assets = rel["assets"].toArray();

            // Index optional .sha512sum sidecar assets for verification
            QHash<QString, QString> sha512ByBase;
            QString releaseSha512Url;
            for (const QJsonValue& av : assets) {
                const QJsonObject ao = av.toObject();
                const QString n = ao["name"].toString();
                if (n.endsWith(QStringLiteral(".sha512sum"), Qt::CaseInsensitive)) {
                    const QString u = ao["browser_download_url"].toString();
                    sha512ByBase.insert(n.chopped(10), u);
                    if (releaseSha512Url.isEmpty()) releaseSha512Url = u;
                }
            }

            // Pick best matching tarball (for CachyOS, prefer x86_64_v3 when enabled, fallback to generic x86_64)
            QJsonObject bestAsset;
            int bestScore = -1;
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
                int score = 10;
                if (category == QStringLiteral("proton-cachyos")) {
                    if (fileName.contains(QStringLiteral("arm64"), Qt::CaseInsensitive)) continue;
                    if (!fileName.contains(QStringLiteral("x86_64"), Qt::CaseInsensitive)) continue;
                    const bool isV3 = fileName.contains(QStringLiteral("x86_64_v3"), Qt::CaseInsensitive);
                    if (isV3) {
                        if (!preferV3) continue;
                        score = 20;
                    } else {
                        score = preferV3 ? 5 : 20;
                    }
                }
                if (category == QStringLiteral("proton-sarek")) {
                    if (fileName.contains(QStringLiteral("async"), Qt::CaseInsensitive)) {
                        score = 8;
                    } else {
                        score = 15;
                    }
                }
                if (category == QStringLiteral("wine-staging") && !fileName.contains(QStringLiteral("staging"))) {
                    continue;
                }
                if (category == QStringLiteral("wine") && fileName.contains(QStringLiteral("staging"))) {
                    continue;
                }
                if (score > bestScore) {
                    bestScore = score;
                    bestAsset = asset;
                }
            }

            if (bestScore >= 0) {
                const QString fileName = bestAsset["name"].toString();
                const QString baseName = fileName.chopped(fileName.endsWith(QStringLiteral(".tar.zst")) ? 8 : 7);
                QVariantMap item;
                item["tagName"] = tag;
                item["name"] = baseName;
                item["category"] = category;
                item["downloadUrl"] = bestAsset["browser_download_url"].toString();
                item["fileName"] = fileName;
                item["sha512Url"] = sha512ByBase.value(baseName, sha512ByBase.value(fileName, releaseSha512Url));
                item["sizeFormatted"] = DownloadManager::formatBytes(bestAsset["size"].toVariant().toLongLong());
                item["publishedAt"] = pub;
                item["isInstalled"] = isReleaseInstalled(tag, baseName);
                fetched.append(item);
            }
        }

        if (!fetched.isEmpty()) {
            m_releaseCache[category] = fetched;
            m_releaseCacheTimeMs[category] = QDateTime::currentMSecsSinceEpoch();
            if (m_activeReleaseCategory == category) {
                m_availableReleases = fetched;
                emit availableReleasesChanged();
            }
        }
    });
}

void RunnerManager::downloadRelease(const QString& category,
                                     const QString& tagName,
                                     const QString& downloadUrl,
                                     const QString& fileName,
                                     const QString& sha512Url)
{
    QString actualFileName = fileName;
    if (actualFileName.isEmpty()) {
        actualFileName = QUrl(downloadUrl).fileName();
        if (actualFileName.isEmpty()) {
            actualFileName = tagName + ((category == QStringLiteral("proton-cachyos") || category == QStringLiteral("proton-em"))
                                            ? QStringLiteral(".tar.xz")
                                            : QStringLiteral(".tar.gz"));
        }
    }
    downloadAndInstallRunner(tagName, category, downloadUrl, actualFileName, sha512Url);
}

void RunnerManager::downloadAndInstallRunner(const QString& tagName,
                                             const QString& category,
                                             const QString& downloadUrl,
                                             const QString& fileName,
                                             const QString& sha512Url)
{
    QString extractDir = m_settings->defaultRunnerLocation();
    if (category == QStringLiteral("dxvk")) {
        extractDir = AppSettings::toolsDir() + QStringLiteral("/dxvk");
    } else if (category == QStringLiteral("vkd3d")) {
        extractDir = AppSettings::toolsDir() + QStringLiteral("/vkd3d");
    }

    const QString destArchive = AppSettings::cacheDir() + QStringLiteral("/") + fileName;
    const QString taskId = QStringLiteral("runner-dl-") + tagName;

    auto startActualDownload = [this, taskId, tagName, category, downloadUrl, destArchive, extractDir](const QString& expectedSha512) {
        emit runnerOperationStatus(QStringLiteral("Starting download of %1…").arg(tagName), false);
        m_dl->enqueueDownload(
            taskId,
            QStringLiteral("Runner: %1").arg(tagName),
            QUrl(downloadUrl),
            destArchive,
            extractDir,
            [this, tagName, category, extractDir](bool ok, const QString& msg) {
                if (ok) {
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
                    fetchAvailableReleases(category, false);
                    emit runnerOperationStatus(QStringLiteral("Installed %1 successfully.").arg(tagName), false);
                } else {
                    emit runnerOperationStatus(QStringLiteral("Failed to install %1: %2").arg(tagName, msg), true);
                }
            },
            expectedSha512,
            QStringLiteral("runner"));
    };

    if (!sha512Url.trimmed().isEmpty()) {
        QNetworkRequest sReq{QUrl(sha512Url.trimmed())};
        sReq.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0"));
        sReq.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
        QNetworkReply* sReply = m_nam.get(sReq);
        connect(sReply, &QNetworkReply::finished, this, [sReply, fileName, startActualDownload]() {
            QString expectedHex;
            if (sReply->error() == QNetworkReply::NoError) {
                const QString body = QString::fromUtf8(sReply->readAll());
                const QStringList lines = body.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
                for (const QString& line : lines) {
                    const QStringList parts = line.trimmed().split(QRegularExpression(QStringLiteral("\\s+")), Qt::SkipEmptyParts);
                    if (!parts.isEmpty() && parts.first().size() == 128) {
                        if (parts.size() < 2 || parts.at(1).contains(fileName, Qt::CaseInsensitive) || lines.size() == 1) {
                            expectedHex = parts.first().toLower();
                            break;
                        }
                    }
                }
            }
            sReply->deleteLater();
            startActualDownload(expectedHex);
        });
        return;
    }

    startActualDownload(QString());
}

bool RunnerManager::uninstallRunner(const QString& runnerId) {
    return removeRunner(runnerId, true);
}

bool RunnerManager::removeRunner(const QString& runnerId, bool deleteFiles) {
    auto rec = m_db->getRunner(runnerId);
    if (!rec.has_value()) return false;
    const bool allowSteamDelete = m_settings && m_settings->allowDeleteSteamRunners();
    if (rec->isSteam() && !allowSteamDelete) {
        emit runnerOperationStatus(QStringLiteral("Deleting Steam runners is disabled in Settings."), true);
        return false;
    }
    if (rec->isSystem && deleteFiles) {
        deleteFiles = false; // Never delete OS/system binaries
    }

    if (deleteFiles && !rec->path.isEmpty()) {
        QStringList allowedBases = {
            QDir::cleanPath(m_settings->defaultRunnerLocation()),
            QDir::cleanPath(QDir::homePath() + QStringLiteral("/.config/heroic/tools/proton")),
            QDir::cleanPath(QDir::homePath() + QStringLiteral("/.config/heroic/tools/wine")),
            QDir::cleanPath(QDir::homePath() + QStringLiteral("/.local/share/lutris/runners/wine"))
        };
        if (allowSteamDelete) {
            allowedBases.append(QDir::cleanPath(QDir::homePath() + QStringLiteral("/.local/share/Steam/compatibilitytools.d")));
            allowedBases.append(QDir::cleanPath(QDir::homePath() + QStringLiteral("/.steam/root/compatibilitytools.d")));
            allowedBases.append(QDir::cleanPath(QDir::homePath() + QStringLiteral("/.steam/steam/compatibilitytools.d")));
            allowedBases.append(QDir::cleanPath(QDir::homePath() + QStringLiteral("/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d")));
            allowedBases.append(QDir::cleanPath(QDir::homePath() + QStringLiteral("/snap/steam/common/.local/share/Steam/compatibilitytools.d")));
            for (const QString& steamLib : collectSteamLibraryRoots()) {
                allowedBases.append(QDir::cleanPath(steamLib + QStringLiteral("/steamapps/common")));
            }
        }

        const QString targetPath = QDir::cleanPath(rec->path);
        bool inSafeBase = false;
        for (const QString& base : allowedBases) {
            if (!base.isEmpty() && targetPath.startsWith(base + QLatin1Char('/')) && targetPath != base) {
                inSafeBase = true;
                break;
            }
        }
        if (!inSafeBase && allowSteamDelete) {
            const QFileInfo targetFi(targetPath);
            const QString parentName = targetFi.dir().dirName();
            if ((parentName == QLatin1String("compatibilitytools.d") ||
                 targetPath.contains(QStringLiteral("/steamapps/common/"))) &&
                targetPath != QDir::homePath() &&
                QFileInfo::exists(targetPath + QStringLiteral("/proton"))) {
                inSafeBase = true;
            }
        }
        if (inSafeBase && QDir(targetPath).exists()) {
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

QString RunnerManager::resolveEacRuntimePath() {
    QStringList candidates = {
        AppSettings::toolsDir() + QStringLiteral("/runtimes/eac_runtime"),
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/runtimes/eac_runtime"),
        QDir::homePath() + QStringLiteral("/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/runtimes/eac_runtime")
    };
    const QSet<QString> steamLibraries = collectSteamLibraryRoots();
    for (const QString& lib : steamLibraries) {
        candidates.append(lib + QStringLiteral("/steamapps/common/Proton EasyAntiCheat Runtime"));
    }

    for (const QString& cand : candidates) {
        const QString resolved = unwrapExtractedRuntimeDir(cand);
        if (!resolved.isEmpty()) return resolved;
    }
    return QString();
}

QString RunnerManager::resolveBattlEyeRuntimePath() {
    QStringList candidates = {
        AppSettings::toolsDir() + QStringLiteral("/runtimes/battleye_runtime"),
        AppSettings::toolsDir() + QStringLiteral("/runtimes/battleeye_runtime"),
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/runtimes/battleye_runtime"),
        QDir::homePath() + QStringLiteral("/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/runtimes/battleye_runtime")
    };
    const QSet<QString> steamLibraries = collectSteamLibraryRoots();
    for (const QString& lib : steamLibraries) {
        candidates.append(lib + QStringLiteral("/steamapps/common/Proton BattlEye Runtime"));
    }

    for (const QString& cand : candidates) {
        const QString resolved = unwrapExtractedRuntimeDir(cand);
        if (!resolved.isEmpty()) return resolved;
    }
    return QString();
}

QString RunnerManager::ensureSpaceSafeRuntimePath(const QString& runtimeDir, const QString& linkName) {
    if (runtimeDir.isEmpty()) return QString();
    if (!runtimeDir.contains(QLatin1Char(' '))) return runtimeDir;

    const QString runtimesBase = AppSettings::toolsDir() + QStringLiteral("/runtimes");
    QDir().mkpath(runtimesBase);
    const QString linkPath = runtimesBase + QStringLiteral("/") + linkName;
    if (linkPath.contains(QLatin1Char(' '))) return runtimeDir;

    QFileInfo linkFi(linkPath);
    if (linkFi.isSymLink()) {
        if (QDir::cleanPath(linkFi.symLinkTarget()) == QDir::cleanPath(runtimeDir)) {
            return linkPath;
        }
        QFile::remove(linkPath);
    } else if (linkFi.exists()) {
        return runtimeDir;
    }

    if (QFile::link(runtimeDir, linkPath)) {
        return linkPath;
    }
    return runtimeDir;
}

void RunnerManager::installAntiCheatRuntime(const QString& runtimeName) {
    const bool isEac = (runtimeName == QLatin1String("eac_runtime"));
    const bool isBe = (runtimeName == QLatin1String("battleye_runtime"));
    if (!isEac && !isBe) return;
    if ((isEac && m_isInstallingEac) || (isBe && m_isInstallingBattleye)) return;

    auto setInstalling = [this, isEac, isBe](bool val) {
        if (isEac) m_isInstallingEac = val;
        if (isBe) m_isInstallingBattleye = val;
        emit antiCheatRuntimesChanged();
    };
    setInstalling(true);

    auto startArchiveDownload = [this, runtimeName, isEac, setInstalling](const QString& url) {
        const QString destDir = AppSettings::toolsDir() + QStringLiteral("/runtimes/") + runtimeName;
        const QString archivePath = AppSettings::cacheDir() + QStringLiteral("/") + runtimeName + QStringLiteral(".tar.xz");
        const QString taskId = QStringLiteral("runtime-") + runtimeName;
        const QString title = isEac ? QStringLiteral("Proton EasyAntiCheat Runtime")
                                    : QStringLiteral("Proton BattlEye Runtime");

        QDir(destDir).removeRecursively();
        QDir().mkpath(destDir);
        emit runnerOperationStatus(QStringLiteral("Downloading %1…").arg(title), false);

        m_dl->enqueueDownload(taskId,
                              title,
                              QUrl(url),
                              archivePath,
                              destDir,
                              [this, title, setInstalling](bool ok, const QString& msg) {
                                  setInstalling(false);
                                  emit antiCheatRuntimesChanged();
                                  if (ok) {
                                      emit runnerOperationStatus(QStringLiteral("%1 installed successfully.").arg(title), false);
                                  } else {
                                      emit runnerOperationStatus(QStringLiteral("Failed to install %1: %2").arg(title, msg), true);
                                  }
                              });
    };

    const QString fallbackUrl = isEac
        ? QStringLiteral("https://github.com/lutris/buildbot/releases/download/2022.06.23/eac_runtime-20240114.tar.xz")
        : QStringLiteral("https://github.com/lutris/buildbot/releases/download/2024-05-21/battleeye_runtime.tar.xz");

    QNetworkRequest req{QUrl(QStringLiteral("https://lutris.net/api/runtimes"))};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0"));
    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [reply, runtimeName, fallbackUrl, startArchiveDownload]() {
        QString url = fallbackUrl;
        if (reply->error() == QNetworkReply::NoError && reply->isOpen()) {
            const QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
            if (doc.isArray()) {
                for (const QJsonValue& v : doc.array()) {
                    const QJsonObject obj = v.toObject();
                    if (obj.value(QStringLiteral("name")).toString() == runtimeName) {
                        const QString u = obj.value(QStringLiteral("url")).toString().trimmed();
                        if (!u.isEmpty()) url = u;
                        break;
                    }
                }
            }
        }
        reply->deleteLater();
        startArchiveDownload(url);
    });
}

bool RunnerManager::removeAntiCheatRuntime(const QString& runtimeName) {
    if (runtimeName != QLatin1String("eac_runtime") && runtimeName != QLatin1String("battleye_runtime")) {
        return false;
    }
    const QString target = AppSettings::toolsDir() + QStringLiteral("/runtimes/") + runtimeName;
    if (!QDir(target).exists()) return false;
    const bool ok = QDir(target).removeRecursively();
    if (ok) {
        emit antiCheatRuntimesChanged();
        emit runnerOperationStatus(QStringLiteral("Removed %1.").arg(runtimeName), false);
    }
    return ok;
}

bool RunnerManager::supportsX86_64V3() {
    return SecretStore::detectCpuX86_64V3();
}

QString RunnerManager::resolveUmuRunPath() {
    const QString tsukiUmu = AppSettings::toolsDir() + QStringLiteral("/umu/umu-run");
    if (QFileInfo::exists(tsukiUmu)) return tsukiUmu;

    const QString tsukiNested = AppSettings::toolsDir() + QStringLiteral("/umu/umu/umu-run");
    if (QFileInfo::exists(tsukiNested)) return tsukiNested;

    const QString sysUmu = QStandardPaths::findExecutable(QStringLiteral("umu-run"));
    if (!sysUmu.isEmpty()) return sysUmu;

    const QStringList externalCandidates = {
        QDir::homePath() + QStringLiteral("/.config/heroic/tools/runtimes/umu/umu_run.py"),
        QDir::homePath() + QStringLiteral("/.var/app/com.heroicgameslauncher.hgl/config/heroic/tools/runtimes/umu/umu_run.py"),
        QDir::homePath() + QStringLiteral("/.local/share/lutris/runtime/umu/umu-run")
    };
    for (const QString& cand : externalCandidates) {
        if (QFileInfo::exists(cand)) return cand;
    }
    return QString();
}

QString RunnerManager::resolveSteamLinuxRuntimePath() {
    const QStringList candidates = {
        QDir::homePath() + QStringLiteral("/.local/share/umu/steamrt3"),
        QDir::homePath() + QStringLiteral("/.local/share/Steam/steamapps/common/SteamLinuxRuntime_sniper"),
        QDir::homePath() + QStringLiteral("/.steam/steam/steamapps/common/SteamLinuxRuntime_sniper"),
        QDir::homePath() + QStringLiteral("/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/common/SteamLinuxRuntime_sniper")
    };
    for (const QString& c : candidates) {
        if (QFileInfo::exists(c + QStringLiteral("/_v2-entry-point")) ||
            QFileInfo::exists(c + QStringLiteral("/run"))) {
            return c;
        }
    }
    for (const QString& lib : collectSteamLibraryRoots()) {
        const QString sniper = lib + QStringLiteral("/steamapps/common/SteamLinuxRuntime_sniper");
        if (QFileInfo::exists(sniper + QStringLiteral("/_v2-entry-point"))) {
            return sniper;
        }
    }
    return QString();
}

QString RunnerManager::umuVersion() const {
    const QString verFile = AppSettings::toolsDir() + QStringLiteral("/umu/.tsuki_umu_version");
    QFile f(verFile);
    if (f.exists() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString::fromUtf8(f.readAll()).trimmed();
    }
    const QString bin = resolveUmuRunPath();
    if (bin.isEmpty()) return QString();
    return bin.startsWith(AppSettings::toolsDir()) ? QStringLiteral("Tsuki Managed") : QStringLiteral("System / Shared");
}

void RunnerManager::installUmuLauncher() {
    if (m_isInstallingUmu) return;
    m_isInstallingUmu = true;
    emit umuRuntimeChanged();

    auto startUmuDownload = [this](const QString& tagName, const QString& url, const QString& fileName) {
        const QString destDir = AppSettings::toolsDir() + QStringLiteral("/umu");
        const QString archivePath = AppSettings::cacheDir() + QStringLiteral("/") + fileName;
        QDir(destDir).removeRecursively();
        QDir().mkpath(destDir);
        emit runnerOperationStatus(QStringLiteral("Downloading umu-launcher (%1)…").arg(tagName), false);

        m_dl->enqueueDownload(
            QStringLiteral("runtime-umu-launcher"),
            QStringLiteral("UMU Launcher (%1)").arg(tagName),
            QUrl(url),
            archivePath,
            destDir,
            [this, tagName, destDir](bool ok, const QString& msg) {
                m_isInstallingUmu = false;
                if (ok) {
                    // Locate umu-run inside extracted folder and ensure executable bit + top-level symlink
                    QString foundBin;
                    QDirIterator it(destDir, {QStringLiteral("umu-run")}, QDir::Files, QDirIterator::Subdirectories);
                    if (it.hasNext()) {
                        foundBin = it.next();
                        QFile::setPermissions(foundBin,
                                              QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                                              QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                                              QFileDevice::ReadOther | QFileDevice::ExeOther);
                        const QString topLink = destDir + QStringLiteral("/umu-run");
                        if (foundBin != topLink && !QFileInfo::exists(topLink)) {
                            QFile::link(foundBin, topLink);
                        }
                    }
                    QFile vf(destDir + QStringLiteral("/.tsuki_umu_version"));
                    if (vf.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
                        vf.write(tagName.toUtf8());
                        vf.close();
                    }
                    emit umuRuntimeChanged();
                    emit runnerOperationStatus(QStringLiteral("Installed umu-launcher %1.").arg(tagName), false);
                } else {
                    emit umuRuntimeChanged();
                    emit runnerOperationStatus(QStringLiteral("Failed to install umu-launcher: %1").arg(msg), true);
                }
            },
            QString(),
            QStringLiteral("runtime"));
    };

    QNetworkRequest req{QUrl(QStringLiteral("https://api.github.com/repos/Open-Wine-Components/umu-launcher/releases/latest"))};
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0"));
    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, startUmuDownload]() {
        QString tag = QStringLiteral("1.2.6");
        QString dlUrl = QStringLiteral("https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.2.6/umu-launcher-1.2.6-zipapp.tar");
        QString fileName = QStringLiteral("umu-launcher-1.2.6-zipapp.tar");

        if (reply->error() == QNetworkReply::NoError && reply->isOpen()) {
            const QJsonObject rel = QJsonDocument::fromJson(reply->readAll()).object();
            const QString t = rel.value(QStringLiteral("tag_name")).toString().trimmed();
            if (!t.isEmpty()) tag = t;
            const QJsonArray assets = rel.value(QStringLiteral("assets")).toArray();
            for (const QJsonValue& av : assets) {
                const QJsonObject ao = av.toObject();
                const QString n = ao.value(QStringLiteral("name")).toString();
                if (n.contains(QStringLiteral("zipapp"), Qt::CaseInsensitive) &&
                    (n.endsWith(QStringLiteral(".tar")) || n.endsWith(QStringLiteral(".tar.gz")) || n.endsWith(QStringLiteral(".tar.xz")))) {
                    dlUrl = ao.value(QStringLiteral("browser_download_url")).toString();
                    fileName = n;
                    break;
                }
            }
        }
        reply->deleteLater();
        startUmuDownload(tag, dlUrl, fileName);
    });
}

bool RunnerManager::removeUmuLauncher() {
    const QString destDir = AppSettings::toolsDir() + QStringLiteral("/umu");
    if (!QDir(destDir).exists()) return false;
    const bool ok = QDir(destDir).removeRecursively();
    if (ok) {
        emit umuRuntimeChanged();
        emit runnerOperationStatus(QStringLiteral("Removed Tsuki-managed umu-launcher."), false);
    }
    return ok;
}

} // namespace Tsuki

