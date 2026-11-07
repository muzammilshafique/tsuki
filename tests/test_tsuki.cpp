#include <QtTest>
#include <QTemporaryDir>
#include <QSqlDatabase>
#include <QSqlQuery>
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
        QCOMPARE(defProf->buttonMappings.value("x").toString(), QString("BTN_NORTH"));
        QCOMPARE(defProf->buttonMappings.value("y").toString(), QString("BTN_WEST"));

        // Verify key codes: in Linux evdev, BTN_NORTH is BTN_X (0x133) and BTN_WEST is BTN_Y (0x134)
        QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_NORTH"), static_cast<quint16>(0x133));
        QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_X"), static_cast<quint16>(0x133));
        QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_WEST"), static_cast<quint16>(0x134));
        QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_Y"), static_cast<quint16>(0x134));

        // Test legacy profile migration/normalization
        ControllerProfileRecord legacyProf;
        legacyProf.id = "prof-legacy";
        legacyProf.name = "Legacy Profile";
        legacyProf.xboxEmulation = true;
        legacyProf.deadzone = 4000;
        legacyProf.buttonMappings["x"] = "BTN_WEST";
        legacyProf.buttonMappings["y"] = "BTN_NORTH";
        QVERIFY(db.saveControllerProfile(legacyProf));
        auto loadedLegacy = db.getControllerProfile("prof-legacy");
        QVERIFY(loadedLegacy.has_value());
        QCOMPARE(loadedLegacy->buttonMappings.value("x").toString(), QString("BTN_NORTH"));
        QCOMPARE(loadedLegacy->buttonMappings.value("y").toString(), QString("BTN_WEST"));

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

        // Test Xbox controller emulation resolution:
        // 1. Settings default is false, but game has xboxEmulationState = 1 -> should enable
        settings.setXboxEmulationDefault(false);
        game.xboxEmulationState = 1;
        const LaunchPlan planXboxOn = pipeline.buildLaunchPlan(game, protonRunner, prefix);
        QVERIFY(planXboxOn.useXboxEmulation);

        // 2. Settings default is true, but game has xboxEmulationState = 0 -> should disable
        settings.setXboxEmulationDefault(true);
        game.xboxEmulationState = 0;
        const LaunchPlan planXboxOff = pipeline.buildLaunchPlan(game, protonRunner, prefix);
        QVERIFY(!planXboxOff.useXboxEmulation);

        // 3. Settings default is false, and game has xboxEmulationState = -1 -> should follow default (false)
        settings.setXboxEmulationDefault(false);
        game.xboxEmulationState = -1;
        const LaunchPlan planXboxDefOff = pipeline.buildLaunchPlan(game, protonRunner, prefix);
        QVERIFY(!planXboxDefOff.useXboxEmulation);

        // 4. Settings default is true, and game has xboxEmulationState = -1 -> should follow default (true)
        settings.setXboxEmulationDefault(true);
        game.xboxEmulationState = -1;
        const LaunchPlan planXboxDefOn = pipeline.buildLaunchPlan(game, protonRunner, prefix);
        QVERIFY(planXboxDefOn.useXboxEmulation);
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

        // Test syncXboxEmulationToAllGames
        QString g1 = gm.addGame("Game 1", "/games/g1.exe");
        QString g2 = gm.addGame("Game 2", "/games/g2.exe");
        gm.syncXboxEmulationToAllGames(true);
        QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
        QCOMPARE(db.getGame(g2)->xboxEmulationState, 1);

        gm.syncXboxEmulationToAllGames(false);
        QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
        QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

        // Ensure settings starts at false before testing signal transition to true
        settings.setXboxEmulationDefault(false);
        gm.syncXboxEmulationToAllGames(false);

        // Test sync triggered via AppSettings controllerDefaultsChanged
        settings.setXboxEmulationDefault(true);
        QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
        QCOMPARE(db.getGame(g2)->xboxEmulationState, 1);

        settings.setXboxEmulationDefault(false);
        QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
        QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);
    }

    void testNativeGameSupport() {
        QTemporaryDir tmpDir;
        QVERIFY(tmpDir.isValid());
        DatabaseManager db(tmpDir.filePath("test_native.db"));
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

        // 1. Platform Detection
        // Create mock files
        const QString pePath = tmpDir.filePath("test.exe");
        QFile peFile(pePath);
        QVERIFY(peFile.open(QIODevice::WriteOnly));
        peFile.write("MZ\x90\x00");
        peFile.close();
        QCOMPARE(gm.detectPlatform(pePath), QString("windows"));

        const QString elfPath = tmpDir.filePath("test.x86_64");
        QFile elfFile(elfPath);
        QVERIFY(elfFile.open(QIODevice::WriteOnly));
        elfFile.write("\x7f\x45\x4c\x46");
        elfFile.close();
        QCOMPARE(gm.detectPlatform(elfPath), QString("linux"));

        const QString shPath = tmpDir.filePath("run.sh");
        QFile shFile(shPath);
        QVERIFY(shFile.open(QIODevice::WriteOnly));
        shFile.write("#!/bin/bash\nexit 0\n");
        shFile.close();
        QCOMPARE(gm.detectPlatform(shPath), QString("linux"));

        // Extension fallback when file does not exist
        QCOMPARE(gm.detectPlatform("/opt/games/celeste.AppImage"), QString("linux"));
        QCOMPARE(gm.detectPlatform("C:/Games/game.bat"), QString("windows"));

        // 2. Add Native Game
        const QString nativeId = gm.addNativeGame("Celeste", elfPath, tmpDir.path(), "--fullscreen");
        QVERIFY(!nativeId.isEmpty());

        auto opt = db.getGame(nativeId);
        QVERIFY(opt.has_value());
        QCOMPARE(opt->title, QString("Celeste"));
        QCOMPARE(opt->platform, QString("linux"));
        QVERIFY(opt->isNative());
        QVERIFY(opt->runnerId.isEmpty());
        QVERIFY(opt->prefixId.isEmpty());

        // Verify variant map produces LINUX tag and type 3
        const QVariantMap vmap = gm.getGameMap(nativeId);
        QCOMPARE(vmap.value("platform").toString(), QString("linux"));
        QCOMPARE(vmap.value("isNative").toBool(), true);
        QCOMPARE(vmap.value("runnerTag").toString(), QString("LINUX"));
        QCOMPARE(vmap.value("type").toInt(), 3);

        // 3. GameListModel integration
        GameListModel* model = gm.model();
        QVERIFY(model != nullptr);
        QVERIFY(model->rowCount() >= 1);

        // Model role verification
        QModelIndex idx = model->index(0, 0);
        QCOMPARE(model->data(idx, GameListModel::TypeRole).toInt(), 3);
        QCOMPARE(model->data(idx, GameListModel::RunnerTagRole).toString(), QString("LINUX"));
        QCOMPARE(model->data(idx, GameListModel::PlatformRole).toString(), QString("linux"));
        QCOMPARE(model->data(idx, GameListModel::IsNativeRole).toBool(), true);

        // Filters: Proton (0) and Wine (1) filters must exclude native games
        model->setFilterType(0);
        QCOMPARE(model->rowCount(), 0);
        model->setFilterType(1);
        QCOMPARE(model->rowCount(), 0);
        model->setFilterType(-1);
        QVERIFY(model->rowCount() >= 1);

        // 4. Update Game Details: cannot alter platform or set runner/prefix for native game
        QVariantMap updates;
        updates["title"] = "Celeste (Updated)";
        updates["platform"] = "windows";
        updates["runnerId"] = "some-wine-runner";
        updates["prefixId"] = "some-pfx";
        updates["environmentVariables"] = QVariantMap{{"SDL_VIDEODRIVER", "wayland"}};
        QVERIFY(gm.updateGameDetails(nativeId, updates));

        auto updated = db.getGame(nativeId);
        QVERIFY(updated.has_value());
        QCOMPARE(updated->title, QString("Celeste (Updated)"));
        QCOMPARE(updated->platform, QString("linux"));
        QVERIFY(updated->runnerId.isEmpty());
        QVERIFY(updated->prefixId.isEmpty());
        QCOMPARE(updated->environmentVariables.value("SDL_VIDEODRIVER").toString(), QString("wayland"));

        // 5. Build Native Launch Plan
        const LaunchPlan plan = pipeline.buildNativeLaunchPlan(*updated);
        QCOMPARE(plan.runnerName, QString("Native Linux"));
        QVERIFY(plan.prefixPath.isEmpty());
        QCOMPARE(plan.program, elfPath);
        QVERIFY(plan.arguments.contains("--fullscreen"));
        QCOMPARE(plan.environment.value("SDL_VIDEODRIVER"), QString("wayland"));
        QVERIFY(plan.environment.value("WINEPREFIX").isEmpty());
        QVERIFY(plan.environment.value("STEAM_COMPAT_DATA_PATH").isEmpty());
        QVERIFY(plan.environment.value("WINEDLLOVERRIDES").isEmpty());

        // 6. Settings: tagColorLinux
        {
            QSettings rawSettings(QStringLiteral("Tsuki"), QStringLiteral("TsukiLauncher"));
            const bool hadKey = rawSettings.contains(QStringLiteral("appearance/tagColorLinux"));
            const QVariant oldVal = rawSettings.value(QStringLiteral("appearance/tagColorLinux"));

            // Remove key to verify the clean default
            rawSettings.remove(QStringLiteral("appearance/tagColorLinux"));
            AppSettings freshSettings;
            QCOMPARE(freshSettings.tagColorLinux().name().toLower(), QString("#f59e0b"));

            freshSettings.setTagColorLinux(QColor("#10b981"));
            QCOMPARE(freshSettings.tagColorLinux().name().toLower(), QString("#10b981"));

            // Restore previous environment state
            if (hadKey) {
                rawSettings.setValue(QStringLiteral("appearance/tagColorLinux"), oldVal);
            } else {
                rawSettings.remove(QStringLiteral("appearance/tagColorLinux"));
            }
        }

        // 7. Remove game does not delete any prefix
        QVERIFY(gm.removeGame(nativeId, true));
        QVERIFY(!db.getGame(nativeId).has_value());

        // 8. Test legacy database migration (schema without 'platform' column)
        const QString legacyDbPath = tmpDir.filePath("legacy.db");
        {
            QSqlDatabase rawDb = QSqlDatabase::addDatabase("QSQLITE", "legacy_conn");
            rawDb.setDatabaseName(legacyDbPath);
            QVERIFY(rawDb.open());
            QSqlQuery q(rawDb);
            q.exec("CREATE TABLE games ("
                   "id TEXT PRIMARY KEY, title TEXT NOT NULL, executable_path TEXT NOT NULL, "
                   "working_directory TEXT, launch_arguments TEXT, runner_id TEXT, prefix_id TEXT, "
                   "cover_path TEXT, banner_path TEXT, logo_path TEXT, icon_path TEXT, "
                   "steamgrid_app_id TEXT, is_favorite INTEGER DEFAULT 0, is_pinned INTEGER DEFAULT 0, "
                   "playtime_seconds INTEGER DEFAULT 0, last_played_timestamp INTEGER DEFAULT 0, "
                   "added_timestamp INTEGER DEFAULT 0, launch_config_json TEXT);");
            q.exec("INSERT INTO games (id, title, executable_path) VALUES ('legacy-1', 'Legacy Game', '/bin/sh');");
            rawDb.close();
        }
        QSqlDatabase::removeDatabase("legacy_conn");

        // Initialize DatabaseManager on legacy db -> should migrate smoothly
        DatabaseManager migDb(legacyDbPath);
        QVERIFY(migDb.initialize());
        auto legGame = migDb.getGame("legacy-1");
        QVERIFY(legGame.has_value());
        QCOMPARE(legGame->platform, QString("windows"));
        QVERIFY(!legGame->isNative());
    }
};

QTEST_MAIN(TestTsuki)
#include "test_tsuki.moc"

