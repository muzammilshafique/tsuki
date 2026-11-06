#include "PrefixManager.h"
#include <QProcess>
#include <QDir>
#include <QFileInfo>
#include <QFile>
#include <QDesktopServices>
#include <QUrl>
#include <QUuid>
#include <QDateTime>
#include <QRegularExpression>
#include <QStandardPaths>

namespace Tsuki {

PrefixManager::PrefixManager(DatabaseManager* db,
                             AppSettings* settings,
                             RunnerManager* runnerMgr,
                             QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_runnerMgr(runnerMgr)
{
    // Ensure a default shared prefix entry is registered so games can choose shared or dedicated immediately
    if (m_db->getAllPrefixes().isEmpty()) {
        PrefixRecord defPfx;
        defPfx.id = QStringLiteral("default-prefix");
        defPfx.name = QStringLiteral("Default");
        defPfx.path = m_settings->defaultPrefixLocation() + QStringLiteral("/Default");
        defPfx.arch = QStringLiteral("win64");
        defPfx.windowsVersion = QStringLiteral("win10");
        defPfx.createdAt = QDateTime::currentSecsSinceEpoch();
        QDir().mkpath(defPfx.path + QStringLiteral("/drive_c"));
        ensureProtonSymlink(defPfx.path);
        m_db->savePrefix(defPfx);
    }
}

QList<PrefixRecord> PrefixManager::prefixes() const {
    return m_db->getAllPrefixes();
}

QVariantList PrefixManager::prefixesVariant() const {
    QVariantList list;
    for (const PrefixRecord& p : m_db->getAllPrefixes()) {
        list.append(p.toVariantMap());
    }
    return list;
}

std::optional<PrefixRecord> PrefixManager::getPrefix(const QString& prefixId) const {
    return m_db->getPrefix(prefixId);
}

QVariantMap PrefixManager::getPrefixMap(const QString& prefixId) const {
    auto p = m_db->getPrefix(prefixId);
    return p.has_value() ? p->toVariantMap() : QVariantMap();
}

void PrefixManager::setBusyState(bool busy, const QString& op) {
    m_isBusy = busy;
    m_currentOperation = op;
    emit busyChanged();
}

void PrefixManager::ensureProtonSymlink(const QString& prefixPath) {
    QDir().mkpath(prefixPath);
    QDir().mkpath(prefixPath + QStringLiteral("/drive_c"));
    const QString pfxLink = prefixPath + QStringLiteral("/pfx");
    QFileInfo fi(pfxLink);
    if (!fi.exists() && !fi.isSymLink()) {
        QFile::link(QStringLiteral("."), pfxLink);
    }
}

QString PrefixManager::suggestShortPrefixName(const QString& gameTitle) const {
    const QString trimmed = gameTitle.trimmed();
    if (trimmed.isEmpty()) return QStringLiteral("GamePrefix");

    const QStringList words = trimmed.split(QRegularExpression(QStringLiteral("[^A-Za-z0-9]+")), Qt::SkipEmptyParts);
    if (words.size() >= 3) {
        QString acronym;
        for (const QString& w : words) {
            if (!w.isEmpty()) acronym.append(w.at(0).toUpper());
        }
        if (acronym.length() >= 3) return acronym;
    }
    QString clean = trimmed;
    clean.remove(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]")));
    return clean.isEmpty() ? QStringLiteral("GamePrefix") : clean.left(20);
}

QProcessEnvironment PrefixManager::buildPrefixEnvironment(const PrefixRecord& pfx, const RunnerRecord& runner) const {
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WINEPREFIX"), pfx.path);
    env.insert(QStringLiteral("WINEARCH"), pfx.arch.isEmpty() ? QStringLiteral("win64") : pfx.arch);
    env.insert(QStringLiteral("WINEDEBUG"), m_settings->enableWineDebugLogs() ? QStringLiteral("+err,+warn") : QStringLiteral("-all"));
    env.insert(QStringLiteral("WINEDLLOVERRIDES"), QStringLiteral("mscoree,mshtml="));
    if (runner.isProton()) {
        env.insert(QStringLiteral("STEAM_COMPAT_DATA_PATH"), pfx.path);
        env.insert(QStringLiteral("STEAM_COMPAT_CLIENT_INSTALL_PATH"), AppSettings::dataDir());
    }
    return env;
}

QString PrefixManager::createPrefix(const QString& name,
                                    const QString& customBaseLocation,
                                    const QString& arch,
                                    const QString& windowsVersion,
                                    const QString& runnerId,
                                    bool initializeNow)
{
    QString cleanName = name.trimmed();
    if (cleanName.isEmpty()) cleanName = QStringLiteral("Prefix_") + QUuid::createUuid().toString(QUuid::Id128).left(6);

    QString baseDir = customBaseLocation.trimmed();
    if (baseDir.startsWith(QStringLiteral("file://"))) {
        baseDir = QUrl(baseDir).toLocalFile();
    }
    if (baseDir.isEmpty()) {
        baseDir = m_settings->defaultPrefixLocation();
    }

    QString safeFolder = cleanName;
    safeFolder.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_.-]")), QStringLiteral("_"));
    const QString fullPath = QDir(baseDir).filePath(safeFolder);
    QDir().mkpath(fullPath + QStringLiteral("/drive_c/windows/system32"));
    if (arch != QStringLiteral("win32")) {
        QDir().mkpath(fullPath + QStringLiteral("/drive_c/windows/syswow64"));
    }
    ensureProtonSymlink(fullPath);

    PrefixRecord rec;
    rec.id = QStringLiteral("pfx-") + QUuid::createUuid().toString(QUuid::Id128).left(10);
    rec.name = cleanName;
    rec.path = fullPath;
    rec.arch = (arch == QStringLiteral("win32")) ? QStringLiteral("win32") : QStringLiteral("win64");
    rec.windowsVersion = windowsVersion.isEmpty() ? QStringLiteral("win10") : windowsVersion;
    rec.runnerId = runnerId;
    rec.createdAt = QDateTime::currentSecsSinceEpoch();

    m_db->savePrefix(rec);
    emit prefixesChanged();

    if (initializeNow) {
        auto runnerOpt = m_runnerMgr->resolveRunner(runnerId);
        if (runnerOpt.has_value()) {
            const QString wineBin = m_runnerMgr->findWineBinaryForRunner(*runnerOpt);
            if (!wineBin.isEmpty() && QFileInfo::exists(wineBin)) {
                setBusyState(true, QStringLiteral("Initializing prefix '%1'…").arg(cleanName));
                auto* proc = new QProcess(this);
                proc->setProcessEnvironment(buildPrefixEnvironment(rec, *runnerOpt));
                const QString prefixId = rec.id;
                const QString winVer = rec.windowsVersion;
                connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc, prefixId]() {
                    emit prefixLogOutput(prefixId, QString::fromUtf8(proc->readAllStandardOutput()));
                });
                connect(proc, &QProcess::readyReadStandardError, this, [this, proc, prefixId]() {
                    emit prefixLogOutput(prefixId, QString::fromUtf8(proc->readAllStandardError()));
                });
                connect(proc, &QProcess::finished, this, [this, proc, prefixId, winVer](int code, QProcess::ExitStatus) {
                    proc->deleteLater();
                    setBusyState(false);
                    if (winVer != QStringLiteral("win10")) {
                        setWindowsVersion(prefixId, winVer);
                    }
                    emit prefixesChanged();
                    emit prefixOperationFinished(prefixId, code == 0,
                        code == 0 ? QStringLiteral("Prefix initialized successfully.")
                                  : QStringLiteral("Prefix created (wineboot exited with %1).").arg(code));
                });
                proc->start(wineBin, {QStringLiteral("wineboot"), QStringLiteral("-u")});
            }
        }
    }

    return rec.id;
}

QString PrefixManager::importPrefix(const QString& name, const QString& existingPath) {
    QString cleanPath = existingPath.trimmed();
    if (cleanPath.startsWith(QStringLiteral("file://"))) {
        cleanPath = QUrl(cleanPath).toLocalFile();
    }
    QFileInfo fi(cleanPath);
    if (!fi.exists() || !fi.isDir()) {
        emit prefixOperationFinished(QString(), false, QStringLiteral("Selected prefix directory does not exist."));
        return QString();
    }

    // If user selected a Proton compatdata folder containing 'pfx/', support it cleanly
    if (QDir(cleanPath + QStringLiteral("/pfx/drive_c")).exists() && !QDir(cleanPath + QStringLiteral("/drive_c")).exists()) {
        cleanPath = cleanPath + QStringLiteral("/pfx");
    }
    ensureProtonSymlink(cleanPath);

    PrefixRecord rec;
    rec.id = QStringLiteral("pfx-") + QUuid::createUuid().toString(QUuid::Id128).left(10);
    rec.name = name.trimmed().isEmpty() ? fi.fileName() : name.trimmed();
    rec.path = cleanPath;
    rec.arch = QDir(cleanPath + QStringLiteral("/drive_c/windows/syswow64")).exists()
                   ? QStringLiteral("win64")
                   : QStringLiteral("win32");
    rec.windowsVersion = QStringLiteral("win10");
    rec.createdAt = QDateTime::currentSecsSinceEpoch();

    m_db->savePrefix(rec);
    emit prefixesChanged();
    emit prefixOperationFinished(rec.id, true, QStringLiteral("Imported prefix '%1'.").arg(rec.name));
    return rec.id;
}

QString PrefixManager::clonePrefix(const QString& sourcePrefixId, const QString& newName, const QString& customDestDir) {
    auto src = m_db->getPrefix(sourcePrefixId);
    if (!src.has_value()) return QString();

    QString cleanName = newName.trimmed();
    if (cleanName.isEmpty()) cleanName = src->name + QStringLiteral("_Clone");

    QString baseDir = customDestDir.trimmed();
    if (baseDir.startsWith(QStringLiteral("file://"))) baseDir = QUrl(baseDir).toLocalFile();
    if (baseDir.isEmpty()) baseDir = m_settings->defaultPrefixLocation();

    QString safeFolder = cleanName;
    safeFolder.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_.-]")), QStringLiteral("_"));
    const QString destPath = QDir(baseDir).filePath(safeFolder);
    QDir().mkpath(baseDir);

    PrefixRecord cloned = *src;
    cloned.id = QStringLiteral("pfx-") + QUuid::createUuid().toString(QUuid::Id128).left(10);
    cloned.name = cleanName;
    cloned.path = destPath;
    cloned.createdAt = QDateTime::currentSecsSinceEpoch();

    m_db->savePrefix(cloned);
    emit prefixesChanged();

    setBusyState(true, QStringLiteral("Cloning prefix '%1' → '%2'…").arg(src->name, cleanName));
    auto* proc = new QProcess(this);
    const QString newId = cloned.id;
    connect(proc, &QProcess::finished, this, [this, proc, newId, destPath](int code, QProcess::ExitStatus) {
        proc->deleteLater();
        ensureProtonSymlink(destPath);
        setBusyState(false);
        emit prefixesChanged();
        emit prefixOperationFinished(newId, code == 0,
            code == 0 ? QStringLiteral("Cloned prefix successfully.")
                      : QStringLiteral("Clone finished with exit code %1.").arg(code));
    });
    proc->start(QStringLiteral("cp"), {QStringLiteral("-a"), src->path, destPath});
    return cloned.id;
}

void PrefixManager::backupPrefix(const QString& prefixId, const QString& destinationArchivePath) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;

    QString dest = destinationArchivePath.trimmed();
    if (dest.startsWith(QStringLiteral("file://"))) dest = QUrl(dest).toLocalFile();
    if (dest.isEmpty()) {
        const QString ts = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"));
        dest = AppSettings::backupsDir() + QStringLiteral("/%1_%2.tar.gz").arg(pfx->name, ts);
    }
    QDir().mkpath(QFileInfo(dest).absolutePath());

    setBusyState(true, QStringLiteral("Backing up prefix '%1'…").arg(pfx->name));
    auto* proc = new QProcess(this);
    const QFileInfo pfxDirInfo(pfx->path);
    connect(proc, &QProcess::finished, this, [this, proc, prefixId, dest](int code, QProcess::ExitStatus) {
        proc->deleteLater();
        setBusyState(false);
        emit prefixOperationFinished(prefixId, code == 0,
            code == 0 ? QStringLiteral("Backup saved to %1").arg(dest)
                      : QStringLiteral("Backup failed (exit code %1)").arg(code));
    });
    proc->start(QStringLiteral("tar"),
                {QStringLiteral("-czf"), dest, QStringLiteral("-C"), pfxDirInfo.absolutePath(), pfxDirInfo.fileName()});
}

void PrefixManager::restorePrefix(const QString& archivePath, const QString& prefixName, const QString& targetBaseDir) {
    QString cleanArchive = archivePath.trimmed();
    if (cleanArchive.startsWith(QStringLiteral("file://"))) cleanArchive = QUrl(cleanArchive).toLocalFile();
    if (!QFileInfo::exists(cleanArchive)) {
        emit prefixOperationFinished(QString(), false, QStringLiteral("Backup archive does not exist: %1").arg(cleanArchive));
        return;
    }

    QString baseDir = targetBaseDir.trimmed();
    if (baseDir.startsWith(QStringLiteral("file://"))) baseDir = QUrl(baseDir).toLocalFile();
    if (baseDir.isEmpty()) baseDir = m_settings->defaultPrefixLocation();

    QString cleanName = prefixName.trimmed();
    if (cleanName.isEmpty()) {
        cleanName = QFileInfo(cleanArchive).baseName();
    }
    const QString destPath = QDir(baseDir).filePath(cleanName);
    QDir().mkpath(destPath);

    setBusyState(true, QStringLiteral("Restoring prefix '%1'…").arg(cleanName));
    auto* proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc, cleanName, destPath](int code, QProcess::ExitStatus) {
        proc->deleteLater();
        setBusyState(false);
        if (code == 0) {
            // Check if archive extracted into a single sub-folder
            QString finalPath = destPath;
            QDir d(destPath);
            const QFileInfoList sub = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
            if (sub.size() == 1 && !QDir(destPath + QStringLiteral("/drive_c")).exists()) {
                finalPath = sub.first().absoluteFilePath();
            }
            importPrefix(cleanName, finalPath);
        } else {
            emit prefixOperationFinished(QString(), false, QStringLiteral("Failed to restore backup archive."));
        }
    });
    proc->start(QStringLiteral("tar"), {QStringLiteral("-xf"), cleanArchive, QStringLiteral("-C"), destPath});
}

bool PrefixManager::deletePrefix(const QString& prefixId, bool deleteFilesFromDisk) {
    if (prefixId == QStringLiteral("default-prefix")) {
        emit prefixOperationFinished(prefixId, false, QStringLiteral("The Default prefix cannot be deleted."));
        return false;
    }
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return false;

    if (deleteFilesFromDisk && !pfx->path.isEmpty() && QFileInfo::exists(pfx->path)) {
        QDir(pfx->path).removeRecursively();
    }
    const bool ok = m_db->removePrefix(prefixId);
    if (ok) {
        emit prefixesChanged();
        emit prefixOperationFinished(prefixId, true, QStringLiteral("Deleted prefix '%1'.").arg(pfx->name));
    }
    return ok;
}

bool PrefixManager::renamePrefix(const QString& prefixId, const QString& newName) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value() || newName.trimmed().isEmpty()) return false;
    pfx->name = newName.trimmed();
    const bool ok = m_db->savePrefix(*pfx);
    if (ok) emit prefixesChanged();
    return ok;
}

void PrefixManager::setWindowsVersion(const QString& prefixId, const QString& winVer) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;

    pfx->windowsVersion = winVer;
    m_db->savePrefix(*pfx);
    emit prefixesChanged();

    auto runnerOpt = m_runnerMgr->resolveRunner(pfx->runnerId);
    if (!runnerOpt.has_value()) return;
    const QString wineBin = m_runnerMgr->findWineBinaryForRunner(*runnerOpt);
    if (wineBin.isEmpty() || !QFileInfo::exists(wineBin)) return;

    auto* proc = new QProcess(this);
    proc->setProcessEnvironment(buildPrefixEnvironment(*pfx, *runnerOpt));
    connect(proc, &QProcess::finished, this, [this, proc, prefixId, winVer](int code, QProcess::ExitStatus) {
        proc->deleteLater();
        emit prefixOperationFinished(prefixId, code == 0,
            QStringLiteral("Set Windows version to %1.").arg(winVer.toUpper()));
    });
    proc->start(wineBin, {QStringLiteral("winecfg"), QStringLiteral("-v"), winVer});
}

bool PrefixManager::writeRegistryDllOverrides(const QString& prefixPath, const QVariantMap& overrides) {
    QDir().mkpath(prefixPath);
    const QString userRegPath = prefixPath + QStringLiteral("/user.reg");
    QFile file(userRegPath);
    QString content;
    if (file.exists() && file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        content = QString::fromUtf8(file.readAll());
        file.close();
    } else {
        content = QStringLiteral("WINE REGISTRY Version 2\n;; All keys relative to \\\\User\\\\S-1-5-21-0-0-0-1000\n\n");
    }

    QString sectionLines = QStringLiteral("[Software\\\\Wine\\\\DllOverrides] %1\n").arg(QDateTime::currentSecsSinceEpoch());
    for (auto it = overrides.constBegin(); it != overrides.constEnd(); ++it) {
        sectionLines += QStringLiteral("\"%1\"=\"%2\"\n").arg(it.key(), it.value().toString());
    }
    sectionLines += QLatin1Char('\n');

    const QRegularExpression re(QStringLiteral("\\[Software\\\\\\\\Wine\\\\\\\\DllOverrides\\][^\\[]*"));
    if (content.contains(re)) {
        content.replace(re, sectionLines);
    } else {
        content.append(QLatin1Char('\n') + sectionLines);
    }

    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        file.write(content.toUtf8());
        file.close();
        return true;
    }
    return false;
}

bool PrefixManager::setDllOverride(const QString& prefixId, const QString& dllName, const QString& mode) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value() || dllName.trimmed().isEmpty()) return false;
    QString cleanDll = dllName.trimmed().toLower();
    if (cleanDll.endsWith(QStringLiteral(".dll"))) cleanDll.chop(4);

    pfx->dllOverrides.insert(cleanDll, mode.isEmpty() ? QStringLiteral("n,b") : mode);
    writeRegistryDllOverrides(pfx->path, pfx->dllOverrides);
    const bool ok = m_db->savePrefix(*pfx);
    if (ok) emit prefixesChanged();
    return ok;
}

bool PrefixManager::removeDllOverride(const QString& prefixId, const QString& dllName) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return false;
    pfx->dllOverrides.remove(dllName.trimmed().toLower());
    writeRegistryDllOverrides(pfx->path, pfx->dllOverrides);
    const bool ok = m_db->savePrefix(*pfx);
    if (ok) emit prefixesChanged();
    return ok;
}

bool PrefixManager::installDxvk(const QString& prefixId, bool enable) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return false;

    const QString sys32 = pfx->path + QStringLiteral("/drive_c/windows/system32");
    const QString syswow64 = pfx->path + QStringLiteral("/drive_c/windows/syswow64");
    QDir().mkpath(sys32);
    if (pfx->arch == QStringLiteral("win64")) QDir().mkpath(syswow64);

    const QStringList dxvkDlls = {
        QStringLiteral("d3d9"), QStringLiteral("d3d10core"), QStringLiteral("d3d11"), QStringLiteral("dxgi")
    };

    if (enable) {
        const QStringList dxvkDirs = m_runnerMgr->findDxvkDirectories();
        if (!dxvkDirs.isEmpty()) {
            const QString dxvkRoot = dxvkDirs.first();
            for (const QString& dll : dxvkDlls) {
                const QString src64 = dxvkRoot + QStringLiteral("/x64/") + dll + QStringLiteral(".dll");
                const QString src32 = dxvkRoot + QStringLiteral("/x32/") + dll + QStringLiteral(".dll");
                if (pfx->arch == QStringLiteral("win64") && QFileInfo::exists(src64)) {
                    const QString dst64 = sys32 + QStringLiteral("/") + dll + QStringLiteral(".dll");
                    QFile::remove(dst64);
                    QFile::copy(src64, dst64);
                    if (QFileInfo::exists(src32)) {
                        const QString dst32 = syswow64 + QStringLiteral("/") + dll + QStringLiteral(".dll");
                        QFile::remove(dst32);
                        QFile::copy(src32, dst32);
                    }
                } else if (QFileInfo::exists(src32)) {
                    const QString dst32 = sys32 + QStringLiteral("/") + dll + QStringLiteral(".dll");
                    QFile::remove(dst32);
                    QFile::copy(src32, dst32);
                }
            }
        }
        for (const QString& dll : dxvkDlls) {
            pfx->dllOverrides.insert(dll, QStringLiteral("n,b"));
        }
        pfx->dxvkInstalled = true;
    } else {
        for (const QString& dll : dxvkDlls) {
            pfx->dllOverrides.remove(dll);
        }
        pfx->dxvkInstalled = false;
    }

    writeRegistryDllOverrides(pfx->path, pfx->dllOverrides);
    const bool ok = m_db->savePrefix(*pfx);
    if (ok) {
        emit prefixesChanged();
        emit prefixOperationFinished(prefixId, true,
            enable ? QStringLiteral("Enabled DXVK in prefix '%1'.").arg(pfx->name)
                   : QStringLiteral("Disabled DXVK in prefix '%1'.").arg(pfx->name));
    }
    return ok;
}

bool PrefixManager::installVkd3d(const QString& prefixId, bool enable) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return false;

    const QString sys32 = pfx->path + QStringLiteral("/drive_c/windows/system32");
    const QString syswow64 = pfx->path + QStringLiteral("/drive_c/windows/syswow64");
    QDir().mkpath(sys32);
    if (pfx->arch == QStringLiteral("win64")) QDir().mkpath(syswow64);

    const QStringList vkd3dDlls = {QStringLiteral("d3d12"), QStringLiteral("d3d12core")};

    if (enable) {
        const QStringList vkd3dDirs = m_runnerMgr->findVkd3dDirectories();
        if (!vkd3dDirs.isEmpty()) {
            const QString vkd3dRoot = vkd3dDirs.first();
            for (const QString& dll : vkd3dDlls) {
                const QString src64 = vkd3dRoot + QStringLiteral("/x64/") + dll + QStringLiteral(".dll");
                const QString src32 = vkd3dRoot + QStringLiteral("/x86/") + dll + QStringLiteral(".dll");
                if (pfx->arch == QStringLiteral("win64") && QFileInfo::exists(src64)) {
                    const QString dst64 = sys32 + QStringLiteral("/") + dll + QStringLiteral(".dll");
                    QFile::remove(dst64);
                    QFile::copy(src64, dst64);
                    if (QFileInfo::exists(src32)) {
                        const QString dst32 = syswow64 + QStringLiteral("/") + dll + QStringLiteral(".dll");
                        QFile::remove(dst32);
                        QFile::copy(src32, dst32);
                    }
                }
            }
        }
        for (const QString& dll : vkd3dDlls) {
            pfx->dllOverrides.insert(dll, QStringLiteral("n,b"));
        }
        pfx->vkd3dInstalled = true;
    } else {
        for (const QString& dll : vkd3dDlls) {
            pfx->dllOverrides.remove(dll);
        }
        pfx->vkd3dInstalled = false;
    }

    writeRegistryDllOverrides(pfx->path, pfx->dllOverrides);
    const bool ok = m_db->savePrefix(*pfx);
    if (ok) {
        emit prefixesChanged();
        emit prefixOperationFinished(prefixId, true,
            enable ? QStringLiteral("Enabled VKD3D-Proton in prefix '%1'.").arg(pfx->name)
                   : QStringLiteral("Disabled VKD3D-Proton in prefix '%1'.").arg(pfx->name));
    }
    return ok;
}

void PrefixManager::runExecutableInPrefix(const QString& prefixId, const QString& exeOrMsiPath, const QStringList& args) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;

    QString cleanExe = exeOrMsiPath.trimmed();
    if (cleanExe.startsWith(QStringLiteral("file://"))) {
        cleanExe = QUrl(cleanExe).toLocalFile();
    }
    if (!QFileInfo::exists(cleanExe)) {
        emit prefixOperationFinished(prefixId, false, QStringLiteral("Installer file not found: %1").arg(cleanExe));
        return;
    }

    auto runnerOpt = m_runnerMgr->resolveRunner(pfx->runnerId);
    if (!runnerOpt.has_value()) {
        emit prefixOperationFinished(prefixId, false, QStringLiteral("No Wine/Proton runner available."));
        return;
    }

    const QString wineBin = m_runnerMgr->findWineBinaryForRunner(*runnerOpt);
    auto* proc = new QProcess(this);
    proc->setProcessEnvironment(buildPrefixEnvironment(*pfx, *runnerOpt));
    proc->setWorkingDirectory(QFileInfo(cleanExe).absolutePath());

    QStringList fullArgs;
    if (cleanExe.endsWith(QStringLiteral(".msi"), Qt::CaseInsensitive)) {
        fullArgs << QStringLiteral("msiexec") << QStringLiteral("/i") << cleanExe;
    } else {
        fullArgs << cleanExe;
    }
    fullArgs.append(args);

    connect(proc, &QProcess::readyReadStandardOutput, this, [this, proc, prefixId]() {
        emit prefixLogOutput(prefixId, QString::fromUtf8(proc->readAllStandardOutput()));
    });
    connect(proc, &QProcess::readyReadStandardError, this, [this, proc, prefixId]() {
        emit prefixLogOutput(prefixId, QString::fromUtf8(proc->readAllStandardError()));
    });
    connect(proc, &QProcess::finished, this, [this, proc, prefixId, cleanExe](int code, QProcess::ExitStatus) {
        proc->deleteLater();
        emit prefixOperationFinished(prefixId, code == 0,
            QStringLiteral("Finished running '%1' (exit code %2).").arg(QFileInfo(cleanExe).fileName()).arg(code));
    });

    proc->start(wineBin, fullArgs);
}

void PrefixManager::runWineTool(const QString& prefixId, const QString& toolName) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;
    auto runnerOpt = m_runnerMgr->resolveRunner(pfx->runnerId);
    if (!runnerOpt.has_value()) return;

    const QString wineBin = m_runnerMgr->findWineBinaryForRunner(*runnerOpt);
    auto* proc = new QProcess(this);
    proc->setProcessEnvironment(buildPrefixEnvironment(*pfx, *runnerOpt));
    proc->setWorkingDirectory(pfx->path);
    connect(proc, &QProcess::finished, proc, &QObject::deleteLater);
    proc->start(wineBin, {toolName});
}

void PrefixManager::openPrefixInFileManager(const QString& prefixId) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;
    QDir().mkpath(pfx->path);
    QDesktopServices::openUrl(QUrl::fromLocalFile(pfx->path));
}

void PrefixManager::openPrefixInTerminal(const QString& prefixId) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;
    QDir().mkpath(pfx->path);

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WINEPREFIX"), pfx->path);
    env.insert(QStringLiteral("WINEARCH"), pfx->arch);

    const QStringList terminals = {
        QStringLiteral("konsole"),
        QStringLiteral("kitty"),
        QStringLiteral("alacritty"),
        QStringLiteral("ptyxis"),
        QStringLiteral("gnome-terminal"),
        QStringLiteral("xfce4-terminal"),
        QStringLiteral("foot"),
        QStringLiteral("xterm")
    };
    for (const QString& term : terminals) {
        const QString bin = QStandardPaths::findExecutable(term);
        if (!bin.isEmpty()) {
            QProcess::startDetached(bin, {}, pfx->path);
            return;
        }
    }
}

} // namespace Tsuki

