#include "WinetricksManager.h"
#include <QStandardPaths>
#include <QFileInfo>
#include <QFile>
#include <QDir>

namespace Tsuki {

WinetricksManager::WinetricksManager(DatabaseManager* db,
                                     AppSettings* settings,
                                     RunnerManager* runnerMgr,
                                     DownloadManager* dl,
                                     QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_runnerMgr(runnerMgr)
    , m_dl(dl)
{
    populateBuiltInCatalog();
    ensureWinetricksAvailable();
}

void WinetricksManager::ensureWinetricksAvailable() {
    const QString tsukiWt = AppSettings::toolsDir() + QStringLiteral("/winetricks");
    const QString sysWt = QStandardPaths::findExecutable(QStringLiteral("winetricks"));
    const QString heroicWt = QDir::homePath() + QStringLiteral("/.config/heroic/tools/winetricks");

    if (QFileInfo::exists(tsukiWt)) {
        m_winetricksPath = tsukiWt;
    } else if (!sysWt.isEmpty()) {
        m_winetricksPath = sysWt;
    } else if (QFileInfo::exists(heroicWt)) {
        // Copy Heroic's winetricks into Tsuki's own tools dir so Tsuki is 100% standalone
        QFile::copy(heroicWt, tsukiWt);
        QFile::setPermissions(tsukiWt, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                                       QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                                       QFileDevice::ReadOther | QFileDevice::ExeOther);
        m_winetricksPath = QFileInfo::exists(tsukiWt) ? tsukiWt : heroicWt;
    } else {
        // Download latest official winetricks script
        m_dl->enqueueDownload(QStringLiteral("winetricks-bin"),
                              QStringLiteral("Winetricks Tool"),
                              QUrl(QStringLiteral("https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")),
                              tsukiWt,
                              QString(),
                              [this, tsukiWt](bool ok, const QString&) {
                                  if (ok) {
                                      QFile::setPermissions(tsukiWt, QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                                                                     QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                                                                     QFileDevice::ReadOther | QFileDevice::ExeOther);
                                      m_winetricksPath = tsukiWt;
                                      emit binaryChanged();
                                  }
                              });
    }
    emit binaryChanged();
}

void WinetricksManager::populateBuiltInCatalog() {
    struct Entry {
        const char* verb;
        const char* title;
        const char* category;
        const char* description;
    };
    static const Entry entries[] = {
        // Visual C++ Runtimes
        {"vcrun2022", "Visual C++ 2015–2022 Redistributable", "vcpp", "MS Visual C++ 2015-2022 libraries (mfc140, vcruntime140, msvcp140)"},
        {"vcrun2019", "Visual C++ 2015–2019 Redistributable", "vcpp", "MS Visual C++ 2015-2019 libraries"},
        {"vcrun2015", "Visual C++ 2015 Redistributable", "vcpp", "MS Visual C++ 2015 runtime libraries"},
        {"vcrun2013", "Visual C++ 2013 Redistributable", "vcpp", "MS Visual C++ 2013 runtime (mfc120, msvcp120, msvcr120)"},
        {"vcrun2012", "Visual C++ 2012 Redistributable", "vcpp", "MS Visual C++ 2012 runtime (atl110, mfc110, msvcp110, msvcr110)"},
        {"vcrun2010", "Visual C++ 2010 Redistributable", "vcpp", "MS Visual C++ 2010 runtime (mfc100, msvcp100, msvcr100)"},
        {"vcrun2008", "Visual C++ 2008 Redistributable", "vcpp", "MS Visual C++ 2008 runtime (atl90, mfc90, msvcp90, msvcr90)"},
        {"vcrun2005", "Visual C++ 2005 Redistributable", "vcpp", "MS Visual C++ 2005 SP1 runtime (mfc80, msvcp80, msvcr80)"},
        {"vcrun6",    "Visual C++ 6.0 Runtime",          "vcpp", "MS Visual C++ 6 SP4 libraries (mfc42, msvcp60, msvcirt)"},

        // DirectX & Graphics/Audio
        {"d3dx9",          "DirectX 9 (d3dx9_24..43)",     "directx", "MS D3DX9 helper DLLs for DirectX 9 games"},
        {"d3dcompiler_43", "D3DCompiler 43",               "directx", "MS Direct3D HLSL Shader Compiler 43"},
        {"d3dcompiler_47", "D3DCompiler 47",               "directx", "MS Direct3D HLSL Shader Compiler 47 (DirectX 11/12)"},
        {"d3dx10",         "DirectX 10 (d3dx10_33..43)",   "directx", "MS D3DX10 helper DLLs"},
        {"d3dx11_43",      "DirectX 11 (d3dx11_43)",       "directx", "MS D3DX11_43 helper DLL"},
        {"xact",           "XACT Audio Engine (32/64-bit)","directx", "MS XACT Engine, XAudio2, X3DAudio for game audio"},
        {"xinput",         "Microsoft XInput",             "directx", "Xbox 360 Controller API DLLs (xinput1_3, xinput1_4)"},
        {"directplay",     "DirectPlay",                   "directx", "MS DirectPlay multiplayer networking for classic games"},
        {"physx",          "NVIDIA PhysX Runtime",         "directx", "NVIDIA PhysX physics runtime for games"},
        {"openal",         "OpenAL Runtime",               "directx", "Creative OpenAL 3D audio library"},
        {"faudio",         "FAudio (XAudio2 reimplementation)", "directx", "FAudio XAudio2/XACT replacement for Wine"},

        // DLLs & .NET / Media Runtimes
        {"dotnet48",   "MS .NET Framework 4.8",        "dlls", "Microsoft .NET Framework 4.8 runtime"},
        {"dotnet40",   "MS .NET Framework 4.0",        "dlls", "Microsoft .NET Framework 4.0 runtime"},
        {"mfc42",      "MFC 4.2 Library",              "dlls", "Visual C++ 6 MFC42 library"},
        {"gdiplus",    "MS GDI+ (gdiplus.dll)",        "dlls", "Microsoft GDI+ 2D graphics library"},
        {"quartz",     "DirectShow Quartz",            "dlls", "DirectShow runtime for in-game video cutscenes"},
        {"lavfilters", "LAV Filters (Video Codecs)",   "dlls", "Open-source DirectShow media splitters and decoders"},
        {"wmp11",      "Windows Media Player 11",      "dlls", "WMV/WMA codecs required by many games for cutscenes"},
        {"winhttp",    "MS WinHTTP",                   "dlls", "Windows HTTP Services DLL"},
        {"wininet",    "MS WinInet",                   "dlls", "Windows Internet API DLL"},
        {"dxvk",       "DXVK (via Winetricks)",        "dlls", "Vulkan-based D3D9/D3D10/D3D11 translation layer"},
        {"vkd3d",      "VKD3D (via Winetricks)",       "dlls", "Vulkan-based D3D12 translation layer"},

        // Fonts
        {"corefonts",      "Microsoft Core Fonts",     "fonts", "Arial, Courier, Georgia, Times New Roman, Trebuchet, Verdana"},
        {"tahoma",         "Microsoft Tahoma Font",    "fonts", "MS Tahoma & Tahoma Bold UI fonts"},
        {"liberationsans", "Liberation Fonts",         "fonts", "Red Hat Liberation Sans, Serif, Mono metric-compatible fonts"},
        {"cjkfonts",       "All CJK Fonts (JP/CN/KR)", "fonts", "Chinese, Japanese, and Korean fonts for East Asian games"},
        {" fakejapanese",  "Fake Japanese Fonts",      "fonts", "Alias Japanese font names to WenQuanYi Micro Hei"}
    };

    m_catalog.clear();
    for (const auto& e : entries) {
        QVariantMap m;
        m["verb"] = QString::fromLatin1(e.verb).trimmed();
        m["title"] = QString::fromLatin1(e.title);
        m["category"] = QString::fromLatin1(e.category);
        m["description"] = QString::fromLatin1(e.description);
        m_catalog.append(m);
    }
    emit catalogChanged();
}

QStringList WinetricksManager::readInstalledLog(const QString& prefixPath) const {
    QStringList installed;
    QFile f(prefixPath + QStringLiteral("/winetricks.log"));
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        while (!f.atEnd()) {
            const QString line = QString::fromUtf8(f.readLine()).trimmed();
            if (!line.isEmpty() && !installed.contains(line)) {
                installed.append(line);
            }
        }
    }
    return installed;
}

QVariantList WinetricksManager::filterCatalog(const QString& category, const QString& searchQuery, const QString& prefixId) const {
    QStringList installedVerbs;
    if (!prefixId.isEmpty()) {
        if (auto pfx = m_db->getPrefix(prefixId); pfx.has_value()) {
            installedVerbs = pfx->installedWinetricks;
            const QStringList diskVerbs = readInstalledLog(pfx->path);
            for (const QString& v : diskVerbs) {
                if (!installedVerbs.contains(v)) installedVerbs.append(v);
            }
        }
    }

    const QString cat = category.trimmed().toLower();
    const QString q = searchQuery.trimmed().toLower();

    QVariantList out;
    for (const QVariant& itemVar : m_catalog) {
        QVariantMap m = itemVar.toMap();
        const QString itemCat = m["category"].toString();
        const QString verb = m["verb"].toString();
        const QString title = m["title"].toString();
        const QString desc = m["description"].toString();

        if (!cat.isEmpty() && cat != QStringLiteral("all") && itemCat != cat) {
            continue;
        }
        if (!q.isEmpty() &&
            !verb.toLower().contains(q) &&
            !title.toLower().contains(q) &&
            !desc.toLower().contains(q)) {
            continue;
        }
        m["isInstalled"] = installedVerbs.contains(verb);
        out.append(m);
    }
    return out;
}

void WinetricksManager::appendLog(const QString& text) {
    m_liveOutput.append(text);
    emit liveOutputChanged();
}

void WinetricksManager::clearLiveOutput() {
    m_liveOutput.clear();
    emit liveOutputChanged();
}

void WinetricksManager::installVerb(const QString& prefixId, const QString& verb) {
    if (m_activeProcess) {
        appendLog(QStringLiteral("\n[Tsuki] Another Winetricks operation is already running.\n"));
        return;
    }
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) {
        emit verbFinished(prefixId, verb, false, QStringLiteral("Prefix not found."));
        return;
    }
    if (m_winetricksPath.isEmpty() || !QFileInfo::exists(m_winetricksPath)) {
        emit verbFinished(prefixId, verb, false, QStringLiteral("Winetricks binary is not installed yet."));
        return;
    }

    auto runnerOpt = m_runnerMgr->resolveRunner(pfx->runnerId);
    if (!runnerOpt.has_value()) {
        emit verbFinished(prefixId, verb, false, QStringLiteral("No Wine runner available."));
        return;
    }

    const QString wineBin = m_runnerMgr->findWineBinaryForRunner(*runnerOpt);
    const QString wineserverBin = m_runnerMgr->findWineserverBinaryForRunner(*runnerOpt);

    m_currentVerb = verb;
    m_liveOutput = QStringLiteral("=== Running: winetricks --unattended %1 ===\nPrefix: %2 (%3)\nWine: %4\n\n")
                       .arg(verb, pfx->name, pfx->path, wineBin);
    emit liveOutputChanged();

    m_activeProcess = new QProcess(this);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WINEPREFIX"), pfx->path);
    env.insert(QStringLiteral("WINEARCH"), pfx->arch);
    env.insert(QStringLiteral("WINE"), wineBin);
    if (!wineserverBin.isEmpty()) {
        env.insert(QStringLiteral("WINESERVER"), wineserverBin);
    }
    env.insert(QStringLiteral("WINEDEBUG"), QStringLiteral("-all"));
    m_activeProcess->setProcessEnvironment(env);

    connect(m_activeProcess, &QProcess::readyReadStandardOutput, this, [this]() {
        if (m_activeProcess) appendLog(QString::fromUtf8(m_activeProcess->readAllStandardOutput()));
    });
    connect(m_activeProcess, &QProcess::readyReadStandardError, this, [this]() {
        if (m_activeProcess) appendLog(QString::fromUtf8(m_activeProcess->readAllStandardError()));
    });

    connect(m_activeProcess, &QProcess::finished, this, [this, prefixId, verb](int exitCode, QProcess::ExitStatus status) {
        if (m_activeProcess) {
            m_activeProcess->deleteLater();
            m_activeProcess = nullptr;
        }
        m_currentVerb.clear();
        emit runningChanged();

        const bool ok = (status == QProcess::NormalExit && exitCode == 0);
        if (ok) {
            if (auto pfxOpt = m_db->getPrefix(prefixId); pfxOpt.has_value()) {
                if (!pfxOpt->installedWinetricks.contains(verb)) {
                    pfxOpt->installedWinetricks.append(verb);
                    m_db->savePrefix(*pfxOpt);
                }
            }
            appendLog(QStringLiteral("\n=== Completed '%1' successfully ===\n").arg(verb));
            emit verbFinished(prefixId, verb, true, QStringLiteral("Installed '%1' successfully.").arg(verb));
        } else {
            appendLog(QStringLiteral("\n=== Winetricks '%1' exited with code %2 ===\n").arg(verb).arg(exitCode));
            emit verbFinished(prefixId, verb, false, QStringLiteral("Winetricks '%1' exited with code %2.").arg(verb).arg(exitCode));
        }
        emit catalogChanged();
    });

    emit runningChanged();
    m_activeProcess->start(m_winetricksPath, {QStringLiteral("--unattended"), verb});
}

void WinetricksManager::removeComponent(const QString& prefixId, const QString& verb) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value()) return;

    pfx->installedWinetricks.removeAll(verb);
    pfx->dllOverrides.remove(verb);
    m_db->savePrefix(*pfx);

    // Also remove from winetricks.log in the prefix if present
    const QString logFile = pfx->path + QStringLiteral("/winetricks.log");
    QFile f(logFile);
    if (f.exists() && f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QStringList kept;
        while (!f.atEnd()) {
            const QString line = QString::fromUtf8(f.readLine()).trimmed();
            if (!line.isEmpty() && line != verb) kept.append(line);
        }
        f.close();
        if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            for (const QString& k : kept) {
                f.write((k + QLatin1Char('\n')).toUtf8());
            }
            f.close();
        }
    }

    appendLog(QStringLiteral("[Tsuki] Removed '%1' tracking & DLL override from prefix '%2'. Use Wine Uninstaller for MSI packages.\n")
                  .arg(verb, pfx->name));
    emit catalogChanged();
    emit verbFinished(prefixId, verb, true, QStringLiteral("Removed '%1' from prefix '%2'.").arg(verb, pfx->name));
}

void WinetricksManager::launchWinetricksGui(const QString& prefixId) {
    auto pfx = m_db->getPrefix(prefixId);
    if (!pfx.has_value() || m_winetricksPath.isEmpty()) return;
    auto runnerOpt = m_runnerMgr->resolveRunner(pfx->runnerId);
    if (!runnerOpt.has_value()) return;

    auto* proc = new QProcess(this);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WINEPREFIX"), pfx->path);
    env.insert(QStringLiteral("WINEARCH"), pfx->arch);
    env.insert(QStringLiteral("WINE"), m_runnerMgr->findWineBinaryForRunner(*runnerOpt));
    proc->setProcessEnvironment(env);
    connect(proc, &QProcess::finished, proc, &QObject::deleteLater);
    proc->start(m_winetricksPath, {QStringLiteral("--gui")});
}

void WinetricksManager::cancelCurrentOperation() {
    if (!m_activeProcess) return;
    m_activeProcess->terminate();
    if (!m_activeProcess->waitForFinished(1500)) {
        m_activeProcess->kill();
    }
}

} // namespace Tsuki

