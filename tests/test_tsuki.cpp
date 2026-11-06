#include <QtTest>
#include <QTemporaryDir>
#include "../src/core/AppSettings.h"
#include "../src/core/DatabaseManager.h"
#include "../src/services/DownloadManager.h"
#include "../src/services/RunnerManager.h"
#include "../src/services/PrefixManager.h"
#include "../src/services/WinetricksManager.h"
#include "../src/services/ControllerManager.h"
#include "../src/services/SteamGridDbService.h"
#include "../src/services/DiagnosticsManager.h"
#include "../src/services/LaunchPipeline.h"
#include "../src/services/GameManager.h"

using namespace Tsuki;

class TestTsuki : public QObject {
    Q_OBJECT

private slots:
    void testDatabaseCrudAndPlaytime() {
        QTemporaryDir tmpDir;
        QVERIFY(tmpDir.isValid());
        DatabaseManager db(tmpDir.filePath("test.db"));
        QVERIFY(db.initialize());
        QVERIFY(db.isOpen());

        // Default controller profile should be seeded automatically
        auto defProf = db.getControllerProfile("default-xbox");
        QVERIFY(defProf.has_value());
        QCOMPARE(defProf->xboxEmulation, true);

        // Save and retrieve a prefix with custom name independent of game title
        PrefixRecord pfx;
        pfx.id = "pfx-gtasa";
        pfx.name = "GTASA";
        pfx.path = tmpDir.filePath("prefixes/GTASA");
        pfx.arch = "win64";
        pfx.windowsVersion = "win10";
        pfx.dllOverrides["dinput8"] = "n,b";
        pfx.installedWinetricks = {"vcrun2022", "d3dx9"};
        QVERIFY(db.savePrefix(pfx));

        auto loadedPfx = db.getPrefixByName("gtasa");
        QVERIFY(loadedPfx.has_value());
        QCOMPARE(loadedPfx->name, QString("GTASA"));
        QCOMPARE(loadedPfx->dllOverrides.value("dinput8").toString(), QString("n,b"));
        QVERIFY(loadedPfx->installedWinetricks.contains("vcrun2022"));

        // Save and retrieve a game with custom launch config
        GameRecord game;
        game.id = "game-1";
        game.title = "Grand Theft Auto: San Andreas";
        game.executablePath = tmpDir.filePath("gta_sa.exe");
        game.workingDirectory = tmpDir.path();
        game.launchArguments = "-windowed";
        game.prefixId = pfx.id;
        game.dxvkState = 1;
        game.esyncState = 1;
        game.fsyncState = 1;
        game.dxvkHud = "fps";
        game.virtualDesktop = true;
        game.virtualDesktopResolution = "1920x1080";
        game.cpuAffinity = "0-3";
        game.processPriority = -5;
        game.environmentVariables["DXVK_ASYNC"] = "1";
        QVERIFY(db.saveGame(game));

        auto loadedGame = db.getGame("game-1");
        QVERIFY(loadedGame.has_value());
        QCOMPARE(loadedGame->title, QString("Grand Theft Auto: San Andreas"));
        QCOMPARE(loadedGame->dxvkState, 1);
        QCOMPARE(loadedGame->dxvkHud, QString("fps"));
        QCOMPARE(loadedGame->virtualDesktop, true);
        QCOMPARE(loadedGame->cpuAffinity, QString("0-3"));
        QCOMPARE(loadedGame->processPriority, -5);
        QCOMPARE(loadedGame->environmentVariables.value("DXVK_ASYNC").toString(), QString("1"));

        // Update playtime
        QVERIFY(db.updatePlaytime("game-1", 3600, 1700000000));
        auto afterPlay = db.getGame("game-1");
        QVERIFY(afterPlay.has_value());
        QCOMPARE(afterPlay->playtimeSeconds, 3600);
        QCOMPARE(GameRecord::formatPlaytime(afterPlay->playtimeSeconds), QString("1.0h"));
    }

    void testPrefixManagerAndShortNames() {
        QTemporaryDir tmpDir;
        DatabaseManager db(tmpDir.filePath("test2.db"));
        QVERIFY(db.initialize());
        AppSettings settings;
        DownloadManager dl;
        RunnerManager runnerMgr(&db, &settings, &dl);
        PrefixManager prefixMgr(&db, &settings, &runnerMgr);

        // Verify short prefix name generation ("Grand Theft Auto San Andreas" -> "GTASA")
        QCOMPARE(prefixMgr.suggestShortPrefixName("Grand Theft Auto San Andreas"), QString("GTASA"));

        // Create prefix without blocking on wineboot
        const QString pfxId = prefixMgr.createPrefix("GTASA", tmpDir.filePath("prefixes"), "win64", "win10", "", false);
        QVERIFY(!pfxId.isEmpty());

        auto pfx = prefixMgr.getPrefix(pfxId);
        QVERIFY(pfx.has_value());
        QVERIFY(QDir(pfx->path + "/drive_c/windows/system32").exists());
        QVERIFY(QFileInfo(pfx->path + "/pfx").isSymLink());

        // Set DLL override and verify user.reg written on disk
        QVERIFY(prefixMgr.setDllOverride(pfxId, "d3d9.dll", "n,b"));
        QFile regFile(pfx->path + "/user.reg");
        QVERIFY(regFile.exists());
        QVERIFY(regFile.open(QIODevice::ReadOnly | QIODevice::Text));
        const QString regContent = QString::fromUtf8(regFile.readAll());
        QVERIFY(regContent.contains("\"d3d9\"=\"n,b\""));

        // Install DXVK & VKD3D overrides
        QVERIFY(prefixMgr.installDxvk(pfxId, true));
        QVERIFY(prefixMgr.installVkd3d(pfxId, true));
        auto updatedPfx = prefixMgr.getPrefix(pfxId);
        QVERIFY(updatedPfx->dxvkInstalled);
        QVERIFY(updatedPfx->vkd3dInstalled);
    }

    void testLaunchPipelineEnvironmentAndProtonStandalone() {
        QTemporaryDir tmpDir;
        DatabaseManager db(tmpDir.filePath("test3.db"));
        QVERIFY(db.initialize());
        AppSettings settings;
        DownloadManager dl;
        RunnerManager runnerMgr(&db, &settings, &dl);
        PrefixManager prefixMgr(&db, &settings, &runnerMgr);
        ControllerManager ctrlMgr(&db, &settings);
        DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
        LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr, &diagMgr);

        GameRecord game;
        game.id = "game-elden";
        game.title = "Elden Ring";
        game.executablePath = "/games/EldenRing/eldenring.exe";
        game.workingDirectory = "/games/EldenRing";
        game.launchArguments = "-eac-nop-loaded -windowed";
        game.dxvkState = 1;
        game.vkd3dState = 1;
        game.esyncState = 1;
        game.fsyncState = 1;
        game.dxvkHud = "fps";
        game.virtualDesktop = true;
        game.virtualDesktopResolution = "2560x1440";
        game.environmentVariables["CUSTOM_VAR"] = "TSUKI_VAL";
        game.dllOverrides["dinput8"] = "n,b";

        RunnerRecord protonRunner;
        protonRunner.id = "runner-ge-proton";
        protonRunner.name = "GE-Proton-latest";
        protonRunner.type = "proton-ge";
        protonRunner.path = "/opt/proton-ge";
        protonRunner.binaryPath = "/opt/proton-ge/proton";

        PrefixRecord prefix;
        prefix.id = "pfx-er";
        prefix.name = "ER";
        prefix.path = tmpDir.filePath("prefixes/ER");
        prefix.arch = "win64";

        const LaunchPlan plan = pipeline.buildLaunchPlan(game, protonRunner, prefix);
        QVERIFY(plan.arguments.contains("waitforexitandrun"));
        QVERIFY(plan.arguments.contains("explorer"));
        QVERIFY(plan.arguments.contains("/desktop=Tsuki,2560x1440"));
        QVERIFY(plan.arguments.contains("/games/EldenRing/eldenring.exe"));
        QVERIFY(plan.arguments.contains("-eac-nop-loaded"));
        QCOMPARE(plan.environment.value("WINEPREFIX"), prefix.path);
        QCOMPARE(plan.environment.value("STEAM_COMPAT_DATA_PATH"), prefix.path);
        QCOMPARE(plan.environment.value("DXVK_HUD"), QString("fps"));
        QCOMPARE(plan.environment.value("WINEESYNC"), QString("1"));
        QCOMPARE(plan.environment.value("WINEFSYNC"), QString("1"));
        QCOMPARE(plan.environment.value("CUSTOM_VAR"), QString("TSUKI_VAL"));
        QVERIFY(plan.environment.value("WINEDLLOVERRIDES").contains("dinput8=n,b"));
        QVERIFY(plan.environment.value("WINEDLLOVERRIDES").contains("d3d11=n,b"));
        QVERIFY(plan.environment.value("WINEDLLOVERRIDES").contains("d3d12=n,b"));
    }

    void testWinetricksAndDiagnosticsErrorAnalysis() {
        QTemporaryDir tmpDir;
        DatabaseManager db(tmpDir.filePath("test4.db"));
        QVERIFY(db.initialize());
        AppSettings settings;
        DownloadManager dl;
        RunnerManager runnerMgr(&db, &settings, &dl);
        PrefixManager prefixMgr(&db, &settings, &runnerMgr);
        WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
        DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);

        // Verify Winetricks catalog filtering
        const QVariantList vcppList = wtMgr.filterCatalog("vcpp", "2022", "");
        QCOMPARE(vcppList.size(), 1);
        QCOMPARE(vcppList.first().toMap().value("verb").toString(), QString("vcrun2022"));

        // Verify Wine error log analyzer detects missing DLL (c0000135)
        diagMgr.startNewGameLog("game-err", "=== Test Log ===");
        diagMgr.appendGameLog("game-err", "0024:err:module:import_dll Library MSVCP140.dll not found (status c0000135)");
        const QVariantMap analysis = diagMgr.analyzeGameLogForErrors("game-err", 53);
        QVERIFY(analysis.value("summary").toString().contains("0xC0000135"));
        QVERIFY(analysis.value("recommendation").toString().contains("vcrun2022"));
    }

    void testGameManagerAndArtwork() {
        QTemporaryDir tmpDir;
        DatabaseManager db(tmpDir.filePath("test5.db"));
        QVERIFY(db.initialize());
        AppSettings settings;
        DownloadManager dl;
        RunnerManager runnerMgr(&db, &settings, &dl);
        PrefixManager prefixMgr(&db, &settings, &runnerMgr);
        ControllerManager ctrlMgr(&db, &settings);
        DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
        LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr, &diagMgr);
        SteamGridDbService sgdb(&settings, &dl);
        GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

        // Test title guessing from parent directories for short/generic executables
        QCOMPARE(gm.guessTitleFromExecutable("/home/user/Games/Silent Hill 2/sh2pc.exe"), QString("Silent Hill 2"));
        QCOMPARE(gm.guessTitleFromExecutable("/home/user/Games/Grand Theft Auto San Andreas/gta_sa.exe"), QString("Grand Theft Auto San Andreas"));
        QCOMPARE(gm.guessTitleFromExecutable("/games/Cyberpunk 2077/bin/x64/Cyberpunk2077.exe"), QString("Cyberpunk 2077"));

        // Test minimal fallback SVG generation
        QString posterPath = SteamGridDbService::generateFallbackPoster("test-game-1", "Silent Hill 2");
        QVERIFY(QFile::exists(posterPath));
        QFile posterFile(posterPath);
        QVERIFY(posterFile.open(QIODevice::ReadOnly));
        QString posterContent = QString::fromUtf8(posterFile.readAll());
        // Verify dark minimal theme and no purple gradients
        QVERIFY(posterContent.contains("#101014"));
        QVERIFY(!posterContent.contains("#1e1b4b"));
        QVERIFY(!posterContent.contains("#2e1065"));
        QVERIFY(posterContent.contains("Silent Hill 2"));

        // Test adding game and removing with dedicated prefix deletion
        QString gameId = gm.addGame("Custom Title", "/home/user/Games/Test/game.exe", "", "", "", "dedicated", "CustomPfx", tmpDir.filePath("prefixes"), "win64");
        QVERIFY(!gameId.isEmpty());
        auto opt = db.getGame(gameId);
        QVERIFY(opt.has_value());
        QCOMPARE(opt->title, QString("Custom Title"));
        QString pfxId = opt->prefixId;
        QVERIFY(!pfxId.isEmpty());
        QVERIFY(prefixMgr.getPrefix(pfxId).has_value());

        // Remove game with deleteDedicatedPrefix = true
        QVERIFY(gm.removeGame(gameId, true));
        QVERIFY(!db.getGame(gameId).has_value());
        QVERIFY(!prefixMgr.getPrefix(pfxId).has_value());
    }
};

QTEST_MAIN(TestTsuki)
#include "test_tsuki.moc"

