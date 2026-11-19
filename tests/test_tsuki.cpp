#include "../src/core/AppSettings.h"
#include "../src/core/DatabaseManager.h"
#include "../src/services/ControllerManager.h"
#include "../src/services/DiagnosticsManager.h"
#include "../src/services/DownloadManager.h"
#include "../src/services/EpicManifestParser.h"
#include "../src/services/EpicService.h"
#include "../src/services/GameManager.h"
#include "../src/services/LaunchPipeline.h"
#include "../src/services/PrefixManager.h"
#include "../src/services/RunnerManager.h"
#include "../src/services/SteamGridDbService.h"
#include "../src/services/WinetricksManager.h"
#include "../src/ui/UiController.h"
#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QFontDatabase>
#include <QFontInfo>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScopeGuard>
#include <QSignalSpy>
#include <QSqlDatabase>
#include <QSqlQuery>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUrl>
#include <QWheelEvent>
#include <QtTest>
#include <SDL2/SDL.h>
#include <zlib.h>
#include <QCryptographicHash>
#include <QtEndian>
#include <cerrno>
#include <csignal>
#include <linux/input-event-codes.h>
#include <linux/uinput.h>

using namespace Tsuki;

namespace {

/// Resolve a QML file from the source tree even under -ffile-prefix-map builds.
QUrl resolveQmlUrl(const QString &relativePath) {
  QStringList candidates;
#ifdef TSUKI_SOURCE_DIR
  candidates << QStringLiteral(TSUKI_SOURCE_DIR) + QLatin1Char('/') +
                    relativePath;
#endif
  candidates << QDir::currentPath() + QLatin1Char('/') + relativePath
             << QCoreApplication::applicationDirPath() +
                    QStringLiteral("/../") + relativePath
             << QFileInfo(QString::fromUtf8(__FILE__)).absolutePath() +
                    QStringLiteral("/../") + relativePath;
  for (const QString &path : candidates) {
    if (QFileInfo::exists(path)) {
      return QUrl::fromLocalFile(QFileInfo(path).canonicalFilePath());
    }
  }
  return QUrl::fromLocalFile(candidates.constFirst());
}

class MockUinputBackend : public IUinputBackend {
public:
  bool failOpen = false;
  bool failIoctl = false;
  unsigned long failIoctlReq = 0;
  bool failWrite = false;

  int openCount = 0;
  int closeCount = 0;
  int ioctlCount = 0;
  int writeCount = 0;

  QList<struct input_event> recordedEvents;
  QString probedStatusString = QStringLiteral("Ready (/dev/uinput writable)");

  int openDevice(const char *path, int flags) override {
    Q_UNUSED(path);
    Q_UNUSED(flags);
    openCount++;
    if (failOpen) {
      errno = EACCES;
      return -1;
    }
    return 42; // fake fd
  }

  int ioctlCall(int fd, unsigned long request, void *arg) override {
    Q_UNUSED(fd);
    Q_UNUSED(arg);
    ioctlCount++;
    if (failIoctl && (failIoctlReq == 0 || failIoctlReq == request)) {
      errno = EINVAL;
      return -1;
    }
    return 0;
  }

  ssize_t writeBytes(int fd, const void *buf, size_t count) override {
    Q_UNUSED(fd);
    writeCount++;
    if (failWrite) {
      errno = EIO;
      return -1;
    }
    const auto *evs = reinterpret_cast<const struct input_event *>(buf);
    size_t n = count / sizeof(struct input_event);
    for (size_t i = 0; i < n; ++i) {
      recordedEvents.append(evs[i]);
    }
    return count;
  }

  int closeDevice(int fd) override {
    Q_UNUSED(fd);
    closeCount++;
    return 0;
  }

  QString probeStatus() override { return probedStatusString; }
};

} // namespace

class TestTsuki : public QObject {
  Q_OBJECT

private slots:
  void initTestCase() { AppSettings::registerApplicationFonts(); }

  void testDatabaseCrudAndPlaytime() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath("test.db"));
    QVERIFY(db.initialize());
    QVERIFY(db.isOpen());

    // Verify key codes: in Linux evdev, BTN_NORTH is BTN_X (0x133) and BTN_WEST
    // is BTN_Y (0x134)
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_NORTH"),
             static_cast<quint16>(0x133));
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_X"),
             static_cast<quint16>(0x133));
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_WEST"),
             static_cast<quint16>(0x134));
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_Y"),
             static_cast<quint16>(0x134));

    // Test bulk setting per-game emulation states
    GameRecord gClr;
    gClr.id = "g-clr-test";
    gClr.title = "Sync Test";
    gClr.executablePath = "/bin/true";
    gClr.xboxEmulationState = 1;
    QVERIFY(db.saveGame(gClr));
    QCOMPARE(db.getGame("g-clr-test")->xboxEmulationState, 1);
    QVERIFY(db.setAllGamesXboxEmulationState(false));
    QCOMPARE(db.getGame("g-clr-test")->xboxEmulationState, 0);
    QVERIFY(db.setAllGamesXboxEmulationState(true));
    QCOMPARE(db.getGame("g-clr-test")->xboxEmulationState, 1);

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
    QCOMPARE(loadedPfx->dllOverrides.value("dinput8").toString(),
             QString("n,b"));
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
    QCOMPARE(loadedGame->environmentVariables.value("DXVK_ASYNC").toString(),
             QString("1"));

    // Update playtime
    QVERIFY(db.updatePlaytime("game-1", 3600, 1700000000));
    auto afterPlay = db.getGame("game-1");
    QVERIFY(afterPlay.has_value());
    QCOMPARE(afterPlay->playtimeSeconds, 3600);
    QCOMPARE(GameRecord::formatPlaytime(afterPlay->playtimeSeconds),
             QString("1.0h"));
  }

  void testPrefixManagerAndShortNames() {
    QTemporaryDir tmpDir;
    DatabaseManager db(tmpDir.filePath("test2.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);

    // Verify short prefix name generation ("Grand Theft Auto San Andreas" ->
    // "GTASA")
    QCOMPARE(prefixMgr.suggestShortPrefixName("Grand Theft Auto San Andreas"),
             QString("GTASA"));

    // Create prefix without blocking on wineboot
    const QString pfxId = prefixMgr.createPrefix(
        "GTASA", tmpDir.filePath("prefixes"), "win64", "win10", "", false);
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
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);

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

    const LaunchPlan plan =
        pipeline.buildLaunchPlan(game, protonRunner, prefix);
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
    // 1. Settings default is false, game has xboxEmulationState = 1 -> enabled
    // (per-game override works)
    settings.setXboxEmulationDefault(false);
    game.xboxEmulationState = 1;
    const LaunchPlan planXboxOnGlobalOff =
        pipeline.buildLaunchPlan(game, protonRunner, prefix);
    QVERIFY(planXboxOnGlobalOff.useXboxEmulation);

    // 2. Settings default is true, but game has xboxEmulationState = 0 ->
    // disabled (per-game override works)
    settings.setXboxEmulationDefault(true);
    game.xboxEmulationState = 0;
    const LaunchPlan planXboxOff =
        pipeline.buildLaunchPlan(game, protonRunner, prefix);
    QVERIFY(!planXboxOff.useXboxEmulation);

    // 3. Settings default is true, and game has xboxEmulationState = 1 ->
    // enabled
    settings.setXboxEmulationDefault(true);
    game.xboxEmulationState = 1;
    const LaunchPlan planXboxOn =
        pipeline.buildLaunchPlan(game, protonRunner, prefix);
    QVERIFY(planXboxOn.useXboxEmulation);

    // 4. Settings default is false, and game has xboxEmulationState = 0 ->
    // disabled
    settings.setXboxEmulationDefault(false);
    game.xboxEmulationState = 0;
    const LaunchPlan planXboxAllOff =
        pipeline.buildLaunchPlan(game, protonRunner, prefix);
    QVERIFY(!planXboxAllOff.useXboxEmulation);
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
    QCOMPARE(vcppList.first().toMap().value("verb").toString(),
             QString("vcrun2022"));

    // Verify Wine error log analyzer detects missing DLL (c0000135)
    diagMgr.startNewGameLog("game-err", "=== Test Log ===");
    diagMgr.appendGameLog("game-err",
                          "0024:err:module:import_dll Library MSVCP140.dll not "
                          "found (status c0000135)");
    const QVariantMap analysis =
        diagMgr.analyzeGameLogForErrors("game-err", 53);
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
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    SteamGridDbService sgdb(&settings, &dl);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    // Test title guessing from parent directories for short/generic executables
    QCOMPARE(
        gm.guessTitleFromExecutable("/home/user/Games/Silent Hill 2/sh2pc.exe"),
        QString("Silent Hill 2"));
    QCOMPARE(gm.guessTitleFromExecutable(
                 "/home/user/Games/Grand Theft Auto San Andreas/gta_sa.exe"),
             QString("Grand Theft Auto San Andreas"));
    QCOMPARE(gm.guessTitleFromExecutable(
                 "/games/Cyberpunk 2077/bin/x64/Cyberpunk2077.exe"),
             QString("Cyberpunk 2077"));

    // Test minimal fallback SVG generation
    QString posterPath = SteamGridDbService::generateFallbackPoster(
        "test-game-1", "Silent Hill 2");
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
    QString gameId = gm.addGame(
        "Custom Title", "/home/user/Games/Test/game.exe", "", "", "",
        "dedicated", "CustomPfx", tmpDir.filePath("prefixes"), "win64");
    QVERIFY(!gameId.isEmpty());
    auto opt = db.getGame(gameId);
    QVERIFY(opt.has_value());
    QCOMPARE(opt->title, QString("Custom Title"));
    QString pfxId = opt->prefixId;
    QVERIFY(!pfxId.isEmpty());
    QVERIFY(prefixMgr.getPrefix(pfxId).has_value());

    // Test per-game Xbox emulation setting independence and global
    // synchronization
    QString g1 = gm.addGame("Game 1", "/games/g1.exe");
    QString g2 = gm.addGame("Game 2", "/games/g2.exe");
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

    // Global ON -> All games ON
    settings.setXboxEmulationDefault(true);
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 1);

    // Modifying Game 1 setting must only affect Game 1
    gm.updateGameDetails(g1, QVariantMap{{"xboxEmulationState", 0}});
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 1);

    // Global OFF -> ALL games OFF
    settings.setXboxEmulationDefault(false);
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

    // Manually enable Game 1 while global is OFF -> Game 1 ON, Game 2 OFF
    gm.updateGameDetails(g1, QVariantMap{{"xboxEmulationState", 1}});
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

    // Global ON again -> ALL games ON
    settings.setXboxEmulationDefault(true);
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 1);
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
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
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
    QCOMPARE(gm.detectPlatform("/opt/games/celeste.AppImage"),
             QString("linux"));
    QCOMPARE(gm.detectPlatform("C:/Games/game.bat"), QString("windows"));

    // 2. Add Native Game
    const QString nativeId =
        gm.addNativeGame("Celeste", elfPath, tmpDir.path(), "--fullscreen");
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
    GameListModel *model = gm.model();
    QVERIFY(model != nullptr);
    QVERIFY(model->rowCount() >= 1);

    // Model role verification
    QModelIndex idx = model->index(0, 0);
    QCOMPARE(model->data(idx, GameListModel::TypeRole).toInt(), 3);
    QCOMPARE(model->data(idx, GameListModel::RunnerTagRole).toString(),
             QString("LINUX"));
    QCOMPARE(model->data(idx, GameListModel::PlatformRole).toString(),
             QString("linux"));
    QCOMPARE(model->data(idx, GameListModel::IsNativeRole).toBool(), true);

    // Filters: Proton (0) and Wine (1) filters must exclude native games
    model->setFilterType(0);
    QCOMPARE(model->rowCount(), 0);
    model->setFilterType(1);
    QCOMPARE(model->rowCount(), 0);
    model->setFilterType(-1);
    QVERIFY(model->rowCount() >= 1);

    // 4. Update Game Details: cannot alter platform or set runner/prefix for
    // native game
    QVariantMap updates;
    updates["title"] = "Celeste (Updated)";
    updates["platform"] = "windows";
    updates["runnerId"] = "some-wine-runner";
    updates["prefixId"] = "some-pfx";
    updates["environmentVariables"] =
        QVariantMap{{"SDL_VIDEODRIVER", "wayland"}};
    QVERIFY(gm.updateGameDetails(nativeId, updates));

    auto updated = db.getGame(nativeId);
    QVERIFY(updated.has_value());
    QCOMPARE(updated->title, QString("Celeste (Updated)"));
    QCOMPARE(updated->platform, QString("linux"));
    QVERIFY(updated->runnerId.isEmpty());
    QVERIFY(updated->prefixId.isEmpty());
    QCOMPARE(updated->environmentVariables.value("SDL_VIDEODRIVER").toString(),
             QString("wayland"));

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
      QSettings rawSettings(QStringLiteral("Tsuki"),
                            QStringLiteral("TsukiLauncher"));
      const bool hadKey =
          rawSettings.contains(QStringLiteral("appearance/tagColorLinux"));
      const QVariant oldVal =
          rawSettings.value(QStringLiteral("appearance/tagColorLinux"));

      // Remove key to verify the clean default
      rawSettings.remove(QStringLiteral("appearance/tagColorLinux"));
      AppSettings freshSettings;
      QCOMPARE(freshSettings.tagColorLinux().name().toLower(),
               QString("#f59e0b"));

      freshSettings.setTagColorLinux(QColor("#10b981"));
      QCOMPARE(freshSettings.tagColorLinux().name().toLower(),
               QString("#10b981"));

      // Restore previous environment state
      if (hadKey) {
        rawSettings.setValue(QStringLiteral("appearance/tagColorLinux"),
                             oldVal);
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
      q.exec(
          "CREATE TABLE games ("
          "id TEXT PRIMARY KEY, title TEXT NOT NULL, executable_path TEXT NOT "
          "NULL, "
          "working_directory TEXT, launch_arguments TEXT, runner_id TEXT, "
          "prefix_id TEXT, "
          "cover_path TEXT, banner_path TEXT, logo_path TEXT, icon_path TEXT, "
          "steamgrid_app_id TEXT, is_favorite INTEGER DEFAULT 0, is_pinned "
          "INTEGER DEFAULT 0, "
          "playtime_seconds INTEGER DEFAULT 0, last_played_timestamp INTEGER "
          "DEFAULT 0, "
          "added_timestamp INTEGER DEFAULT 0, launch_config_json TEXT);");
      q.exec("INSERT INTO games (id, title, executable_path) VALUES "
             "('legacy-1', 'Legacy Game', '/bin/sh');");
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

  void testUnknownMappingValidation() {
    QVERIFY(ControllerManager::isValidButtonName("BTN_SOUTH"));
    QVERIFY(ControllerManager::isValidButtonName("BTN_A"));
    QVERIFY(ControllerManager::isValidButtonName("BTN_NORTH"));
    QVERIFY(ControllerManager::isValidButtonName("BTN_WEST"));
    QVERIFY(!ControllerManager::isValidButtonName("BTN_INVALID"));
    QVERIFY(!ControllerManager::isValidButtonName(""));

    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_INVALID"),
             static_cast<quint16>(0));
    QCOMPARE(ControllerManager::linuxKeyCodeForName(""),
             static_cast<quint16>(0));
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_SOUTH"),
             static_cast<quint16>(0x130));
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_NORTH"),
             static_cast<quint16>(0x133));
    QCOMPARE(ControllerManager::linuxKeyCodeForName("BTN_WEST"),
             static_cast<quint16>(0x134));

    const auto defMap = ControllerManager::defaultXboxMappings();
    QCOMPARE(defMap.value("a").toString(), QString("BTN_SOUTH"));
    QCOMPARE(defMap.value("x").toString(), QString("BTN_NORTH"));
    QCOMPARE(defMap.value("y").toString(), QString("BTN_WEST"));
    QCOMPARE(defMap.value("b").toString(), QString("BTN_EAST"));
  }

  void testDuplicateMappingPressReleaseBehavior() {
    auto mockBackend = std::make_unique<MockUinputBackend>();
    MockUinputBackend *rawMock = mockBackend.get();
    UinputXboxDevice dev(std::move(mockBackend));

    QVERIFY(dev.start("Test Virtual Device"));
    rawMock->recordedEvents.clear();

    // Map physical A and B both to BTN_SOUTH
    QVariantMap dupMap;
    dupMap["a"] = "BTN_SOUTH";
    dupMap["b"] = "BTN_SOUTH";

    XboxPadState state;
    // Step 1: Press A only -> BTN_SOUTH = 1
    state.a = true;
    state.b = false;
    dev.syncState(state, dupMap);

    bool foundSouthPress = false;
    for (const auto &ev : rawMock->recordedEvents) {
      if (ev.type == EV_KEY && ev.code == BTN_SOUTH && ev.value == 1)
        foundSouthPress = true;
    }
    QVERIFY(foundSouthPress);

    // Step 2: Press B as well while A is held -> still held, no unneeded event
    rawMock->recordedEvents.clear();
    state.b = true;
    dev.syncState(state, dupMap);
    QVERIFY(rawMock->recordedEvents.isEmpty());

    // Step 3: Release A while B is STILL held -> BTN_SOUTH must NOT be
    // released!
    rawMock->recordedEvents.clear();
    state.a = false;
    state.b = true;
    dev.syncState(state, dupMap);
    bool foundSouthRelease = false;
    for (const auto &ev : rawMock->recordedEvents) {
      if (ev.type == EV_KEY && ev.code == BTN_SOUTH && ev.value == 0)
        foundSouthRelease = true;
    }
    QVERIFY(!foundSouthRelease);

    // Step 4: Release B as well -> now both released, BTN_SOUTH = 0
    rawMock->recordedEvents.clear();
    state.b = false;
    dev.syncState(state, dupMap);
    foundSouthRelease = false;
    for (const auto &ev : rawMock->recordedEvents) {
      if (ev.type == EV_KEY && ev.code == BTN_SOUTH && ev.value == 0)
        foundSouthRelease = true;
    }
    QVERIFY(foundSouthRelease);
  }

  void testDeadzoneValidationAndNormalization() {
    // Deadzone threshold filtering: within 4000 deadzone is suppressed to 0
    QCOMPARE(ControllerManager::applyDeadzone(3000, 4000),
             static_cast<qint16>(0));
    QCOMPARE(ControllerManager::applyDeadzone(-3000, 4000),
             static_cast<qint16>(0));
    QCOMPARE(ControllerManager::applyDeadzone(5000, 4000),
             static_cast<qint16>(5000));
    QCOMPARE(ControllerManager::applyDeadzone(-5000, 4000),
             static_cast<qint16>(-5000));

    // Default deadzone overload
    QCOMPARE(ControllerManager::applyDeadzone(2500), static_cast<qint16>(0));
    QCOMPARE(ControllerManager::applyDeadzone(4500), static_cast<qint16>(4500));

    // Trigger axis scaling in UinputXboxDevice
    auto mockBackend = std::make_unique<MockUinputBackend>();
    MockUinputBackend *rawMock = mockBackend.get();
    UinputXboxDevice dev(std::move(mockBackend));
    dev.start("DZ Test");
    rawMock->recordedEvents.clear();

    XboxPadState st;
    st.lt = 16384; // 16384 / 128 = 128
    st.rt = 32767; // 32767 / 128 = 255
    dev.syncState(st);

    bool foundZ = false;
    bool foundRZ = false;
    for (const auto &ev : rawMock->recordedEvents) {
      if (ev.type == EV_ABS && ev.code == ABS_Z && ev.value == 128)
        foundZ = true;
      if (ev.type == EV_ABS && ev.code == ABS_RZ && ev.value == 255)
        foundRZ = true;
    }
    QVERIFY(foundZ);
    QVERIFY(foundRZ);
  }

  void testGlobalDefaultVersusPerGameOverrideResolution() {
    QTemporaryDir tmpDir;
    DatabaseManager db(tmpDir.filePath("test_res.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);

    GameRecord g;
    g.id = "g-res";
    g.title = "Resolution Test";
    g.executablePath = "/bin/true";
    g.platform = "linux";

    // 1. Global = false, Game = 0 -> false
    settings.setXboxEmulationDefault(false);
    g.xboxEmulationState = 0;
    QCOMPARE(pipeline.buildNativeLaunchPlan(g).useXboxEmulation, false);

    // 2. Global = false, Game = 1 -> true (Per-game override ON works even when
    // global default is OFF)
    settings.setXboxEmulationDefault(false);
    g.xboxEmulationState = 1;
    QCOMPARE(pipeline.buildNativeLaunchPlan(g).useXboxEmulation, true);

    // 3. Global = true, Game = 0 -> false (Per-game override OFF works even
    // when global default is ON)
    settings.setXboxEmulationDefault(true);
    g.xboxEmulationState = 0;
    QCOMPARE(pipeline.buildNativeLaunchPlan(g).useXboxEmulation, false);

    // 4. Global = true, Game = 1 -> true
    settings.setXboxEmulationDefault(true);
    g.xboxEmulationState = 1;
    QCOMPARE(pipeline.buildNativeLaunchPlan(g).useXboxEmulation, true);
  }

  void testGlobalSynchronizationAndIndependentOverrides() {
    QTemporaryDir tmpDir;
    DatabaseManager db(tmpDir.filePath("test_sync_override.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings,
                              std::make_unique<MockUinputBackend>());
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    SteamGridDbService sgdb(&settings, &dl);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    QString scriptPath = tmpDir.filePath("sleeper_rt.sh");
    QFile f(scriptPath);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("#!/bin/sh\nsleep 10\n");
    f.close();
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                     QFileDevice::ExeOwner);

    // Add Game A and Game B
    QString gA = gm.addNativeGame("Game A", scriptPath);
    QString gB = gm.addNativeGame("Game B", scriptPath);

    // 1. Global ON -> All games ON in DB
    settings.setXboxEmulationDefault(true);
    QCOMPARE(db.getGame(gA)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(gB)->xboxEmulationState, 1);

    // 2. Manually disable Game A -> Game A OFF, Game B remains ON
    gm.updateGameDetails(gA, QVariantMap{{"xboxEmulationState", 0}});
    QCOMPARE(db.getGame(gA)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(gB)->xboxEmulationState, 1);

    // 3. Global OFF -> ALL games OFF in DB
    settings.setXboxEmulationDefault(false);
    QCOMPARE(db.getGame(gA)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(gB)->xboxEmulationState, 0);

    // 4. Manually enable Game A while global is OFF -> Game A ON, Game B
    // remains OFF
    gm.updateGameDetails(gA, QVariantMap{{"xboxEmulationState", 1}});
    QCOMPARE(db.getGame(gA)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(gB)->xboxEmulationState, 0);

    // 5. Launch Game A while global is OFF: MUST start virtual controller
    // emulation!
    QVERIFY(pipeline.launchGame(gA));
    QVERIFY(pipeline.isGameRunning(gA));
    QVERIFY(ctrlMgr.isEmulationActive());

    pipeline.stopGame(gA);
    QTRY_VERIFY_WITH_TIMEOUT(!pipeline.isGameRunning(gA), 2000);
    QVERIFY(!ctrlMgr.isEmulationActive());
  }

  void testSubsequentGlobalSynchronizationOverwritesIndividualOverrides() {
    QTemporaryDir tmpDir;
    DatabaseManager db(tmpDir.filePath("test_subsequent_sync.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    SteamGridDbService sgdb(&settings, &dl);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    QString g1 = gm.addGame("Sync 1", "/bin/true");
    QString g2 = gm.addGame("Sync 2", "/bin/true");

    // Global OFF initial
    settings.setXboxEmulationDefault(false);
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

    // Manually enable Game 1
    gm.updateGameDetails(g1, QVariantMap{{"xboxEmulationState", 1}});
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

    // Subsequent Global ON -> ALL games overwritten to ON
    settings.setXboxEmulationDefault(true);
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 1);

    // Manually disable Game 2
    gm.updateGameDetails(g2, QVariantMap{{"xboxEmulationState", 0}});
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 1);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);

    // Subsequent Global OFF -> ALL games overwritten to OFF
    settings.setXboxEmulationDefault(false);
    QCOMPARE(db.getGame(g1)->xboxEmulationState, 0);
    QCOMPARE(db.getGame(g2)->xboxEmulationState, 0);
  }

  void testFailedProcessLaunchCleanup() {
    QTemporaryDir tmpDir;
    DatabaseManager db(tmpDir.filePath("test_fail.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings,
                              std::make_unique<MockUinputBackend>());
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);

    // Create a non-executable file as executablePath
    QString notExec = tmpDir.filePath("not_executable.bin");
    QFile f(notExec);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("test");
    f.close();
    f.setPermissions(QFileDevice::ReadOwner |
                     QFileDevice::WriteOwner); // NO execute perm

    GameRecord game;
    game.id = "game-fail";
    game.title = "Failed Game";
    game.executablePath = notExec;
    game.platform = "linux";
    game.xboxEmulationState = 1;
    db.saveGame(game);

    settings.setXboxEmulationDefault(true);
    QSignalSpy failedSpy(&pipeline, &LaunchPipeline::gameLaunchFailed);

    pipeline.launchGame("game-fail");

    // Wait for FailedToStart to be emitted and handled
    QTRY_COMPARE_WITH_TIMEOUT(failedSpy.count(), 1, 1000);

    // Verify session was cleanly removed and state is not stuck running
    QVERIFY(!pipeline.isGameRunning("game-fail"));
    QVERIFY(pipeline.runningGameIds().isEmpty());
    QCOMPARE(pipeline.runningCount(), 0);

    // Controller emulation must not remain running
    QVERIFY(!ctrlMgr.isEmulationActive());
  }

  void testMultipleRunningGamesEmulationLifecycle() {
    QTemporaryDir tmpDir;
    DatabaseManager db(tmpDir.filePath("test_multi.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings,
                              std::make_unique<MockUinputBackend>());
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);

    QString scriptPath = tmpDir.filePath("sleeper.sh");
    QFile f(scriptPath);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("#!/bin/sh\nsleep 10\n");
    f.close();
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                     QFileDevice::ExeOwner);

    GameRecord g1;
    g1.id = "g-emu-on";
    g1.title = "Game With Emulation";
    g1.executablePath = scriptPath;
    g1.platform = "linux";
    g1.xboxEmulationState = 1;
    db.saveGame(g1);

    GameRecord g2;
    g2.id = "g-emu-off";
    g2.title = "Game Without Emulation";
    g2.executablePath = scriptPath;
    g2.platform = "linux";
    g2.xboxEmulationState = 0;
    db.saveGame(g2);

    settings.setXboxEmulationDefault(true);

    // Launch Game 1 (needs emulation)
    QVERIFY(pipeline.launchGame("g-emu-on"));
    QVERIFY(pipeline.isGameRunning("g-emu-on"));
    QVERIFY(ctrlMgr.isEmulationActive());

    // Launch Game 2 (no emulation)
    QVERIFY(pipeline.launchGame("g-emu-off"));
    QVERIFY(pipeline.isGameRunning("g-emu-off"));
    QVERIFY(ctrlMgr.isEmulationActive()); // Kept active for Game 1

    // Stop Game 1 (which needed emulation)
    pipeline.stopGame("g-emu-on");
    QTRY_VERIFY_WITH_TIMEOUT(!pipeline.isGameRunning("g-emu-on"), 2000);

    // Game 2 is still running, but does NOT require emulation -> emulation must
    // stop!
    QVERIFY(pipeline.isGameRunning("g-emu-off"));
    QVERIFY(!ctrlMgr.isEmulationActive());

    // Stop Game 2
    pipeline.stopGame("g-emu-off");
    QTRY_VERIFY_WITH_TIMEOUT(!pipeline.isGameRunning("g-emu-off"), 2000);
    QVERIFY(!ctrlMgr.isEmulationActive());
  }

  void testStopGameKillsDetachedSessionAndSdlNoSignalHandlers() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath("test_detached.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings,
                              std::make_unique<MockUinputBackend>());
    QCOMPARE(QByteArray(SDL_GetHint(SDL_HINT_NO_SIGNAL_HANDLERS)),
             QByteArray("1"));

    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);

    const QString pidFile = tmpDir.filePath("detached.pid");
    const QString scriptPath = tmpDir.filePath("spawn_detached.sh");
    QFile f(scriptPath);
    QVERIFY(f.open(QIODevice::WriteOnly));
    const QByteArray script = QByteArray("#!/bin/sh\n"
                                         "setsid sleep 30 >/dev/null 2>&1 &\n"
                                         "CPID=$!\n"
                                         "echo \"$CPID\" > \"") +
                              pidFile.toUtf8() +
                              QByteArray(".tmp\"\n"
                                         "mv \"") +
                              pidFile.toUtf8() + QByteArray(".tmp\" \"") +
                              pidFile.toUtf8() +
                              QByteArray("\"\n"
                                         "wait \"$CPID\"\n");
    f.write(script);
    f.close();
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner |
                     QFileDevice::ExeOwner);

    GameRecord g;
    g.id = "detached-game";
    g.title = "Detached Child Game";
    g.executablePath = scriptPath;
    g.platform = "linux";
    g.gamescopeState = 0;
    db.saveGame(g);

    QVERIFY(pipeline.launchGame("detached-game"));
    QTRY_VERIFY_WITH_TIMEOUT(QFileInfo::exists(pidFile), 2000);

    QFile pf(pidFile);
    QVERIFY(pf.open(QIODevice::ReadOnly));
    bool ok = false;
    const qint64 childPid = pf.readAll().trimmed().toLongLong(&ok);
    QVERIFY(ok && childPid > 1);
    auto cleanupChild = qScopeGuard([&]() {
      if (childPid > 1) {
        ::kill(static_cast<pid_t>(childPid), SIGKILL);
      }
    });
    auto isProcessAliveNonZombie = [](qint64 pid) -> bool {
      if (pid <= 1)
        return false;
      if (::kill(static_cast<pid_t>(pid), 0) != 0)
        return false;
      QFile statFile(QStringLiteral("/proc/%1/stat").arg(pid));
      if (!statFile.open(QIODevice::ReadOnly))
        return false;
      const QByteArray data = statFile.readAll();
      const int rparen = data.lastIndexOf(')');
      if (rparen < 0)
        return false;
      const QList<QByteArray> fields =
          data.mid(rparen + 1).trimmed().split(' ');
      if (fields.isEmpty())
        return false;
      const QByteArray state = fields.at(0);
      return state != "Z" && state != "X";
    };
    QVERIFY(isProcessAliveNonZombie(childPid));

    QElapsedTimer stopTimer;
    stopTimer.start();
    pipeline.stopGame("detached-game");
    QVERIFY(stopTimer.elapsed() < 500);

    QTRY_VERIFY_WITH_TIMEOUT(!pipeline.isGameRunning("detached-game"), 2000);
    QTRY_VERIFY_WITH_TIMEOUT(!isProcessAliveNonZombie(childPid), 2000);
  }

  void testControllerDisconnectNeutralization() {
    auto mockBackend = std::make_unique<MockUinputBackend>();
    MockUinputBackend *rawMock = mockBackend.get();
    UinputXboxDevice dev(std::move(mockBackend));

    QVERIFY(dev.start("Neutral Test"));
    rawMock->recordedEvents.clear();

    // Simulate held buttons and moved stick
    XboxPadState held;
    held.a = true;
    held.lb = true;
    held.lx = 20000;
    held.lt = 10000;
    dev.syncState(held, {});

    bool sawPress = false;
    for (const auto &ev : rawMock->recordedEvents) {
      if (ev.type == EV_KEY && ev.code == BTN_SOUTH && ev.value == 1)
        sawPress = true;
    }
    QVERIFY(sawPress);

    // Reset to neutral
    rawMock->recordedEvents.clear();
    dev.resetToNeutral();

    bool sawReleaseA = false;
    bool sawReleaseLB = false;
    bool sawCenterLX = false;
    bool sawZeroLT = false;
    bool sawSyn = false;

    for (const auto &ev : rawMock->recordedEvents) {
      if (ev.type == EV_KEY && ev.code == BTN_SOUTH && ev.value == 0)
        sawReleaseA = true;
      if (ev.type == EV_KEY && ev.code == BTN_TL && ev.value == 0)
        sawReleaseLB = true;
      if (ev.type == EV_ABS && ev.code == ABS_X && ev.value == 0)
        sawCenterLX = true;
      if (ev.type == EV_ABS && ev.code == ABS_Z && ev.value == 0)
        sawZeroLT = true;
      if (ev.type == EV_SYN && ev.code == SYN_REPORT)
        sawSyn = true;
    }

    QVERIFY(sawReleaseA);
    QVERIFY(sawReleaseLB);
    QVERIFY(sawCenterLX);
    QVERIFY(sawZeroLT);
    QVERIFY(sawSyn);
  }

  void testRepeatedStartStopLifecycleBehavior() {
    auto mockBackend = std::make_unique<MockUinputBackend>();
    MockUinputBackend *rawMock = mockBackend.get();
    UinputXboxDevice dev(std::move(mockBackend));

    QVERIFY(dev.start("Session 1"));
    QVERIFY(dev.isActive());
    QCOMPARE(rawMock->openCount, 1);

    // Repeated start is safe and idempotent
    QVERIFY(dev.start("Session 2"));
    QVERIFY(dev.isActive());
    QCOMPARE(rawMock->openCount, 2);
    QCOMPARE(rawMock->closeCount, 1);

    // Stop
    dev.stop();
    QVERIFY(!dev.isActive());
    QCOMPARE(rawMock->closeCount, 2);

    // Repeated stop is a safe no-op
    dev.stop();
    QVERIFY(!dev.isActive());
    QCOMPARE(rawMock->closeCount, 2);
  }

  void testFailedVirtualDeviceInitializationAndCleanup() {
    // Case 1: Open fails (e.g. permission denied)
    {
      auto mockBackend = std::make_unique<MockUinputBackend>();
      mockBackend->failOpen = true;
      UinputXboxDevice dev(std::move(mockBackend));
      QVERIFY(!dev.start("FailOpen"));
      QVERIFY(!dev.isActive());
      QVERIFY(dev.status().contains("Failed to open /dev/uinput"));
    }

    // Case 2: ioctl UI_DEV_CREATE fails
    {
      auto mockBackend = std::make_unique<MockUinputBackend>();
      MockUinputBackend *rawMock = mockBackend.get();
      mockBackend->failIoctl = true;
      mockBackend->failIoctlReq = UI_DEV_CREATE;
      UinputXboxDevice dev(std::move(mockBackend));
      QVERIFY(!dev.start("FailCreate"));
      QVERIFY(!dev.isActive());
      QVERIFY(dev.status().contains("UI_DEV_CREATE"));
      // File descriptor was closed cleanly
      QCOMPARE(rawMock->closeCount, 1);
    }

    // Case 3: write failure does not advance delta tracking; retries when error
    // clears
    {
      auto mockBackend = std::make_unique<MockUinputBackend>();
      MockUinputBackend *rawMock = mockBackend.get();
      UinputXboxDevice dev(std::move(mockBackend));
      QVERIFY(dev.start("WriteRetryTest"));
      rawMock->recordedEvents.clear();

      // Simulate write failure
      rawMock->failWrite = true;
      XboxPadState st;
      st.a = true;
      dev.syncState(st, {});
      QVERIFY(rawMock->writeCount > 0);
      QVERIFY(rawMock->recordedEvents.isEmpty());

      // Clear write error: on next syncState, it must re-attempt to send the
      // pending state change
      rawMock->failWrite = false;
      dev.syncState(st, {});
      bool sawA = false;
      for (const auto &ev : rawMock->recordedEvents) {
        if (ev.type == EV_KEY && ev.code == BTN_SOUTH && ev.value == 1)
          sawA = true;
      }
      QVERIFY(sawA);
    }
  }

  void testRunnerManagerSteamDetectionAndProtonCachyOS() {
    // 1. Verify RunnerRecord::isProton() with proton-cachyos
    RunnerRecord cachyRec;
    cachyRec.id = QStringLiteral("cachy-test");
    cachyRec.name = QStringLiteral("Proton CachyOS");
    cachyRec.type = QStringLiteral("proton-cachyos");
    cachyRec.binaryPath = QStringLiteral("/tmp/fake/proton");
    QVERIFY(cachyRec.isProton());

    // 2. Test fallback releases for proton-cachyos
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath("test_runners.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager rm(&db, &settings, &dl);

    rm.fetchAvailableReleases(QStringLiteral("proton-cachyos"));
    const QVariantList rels = rm.availableReleases();
    QVERIFY(!rels.isEmpty());
    const QVariantMap firstRel = rels.first().toMap();
    QCOMPARE(firstRel.value(QStringLiteral("category")).toString(),
             QStringLiteral("proton-cachyos"));
    QVERIFY(firstRel.value(QStringLiteral("downloadUrl"))
                .toString()
                .contains(QStringLiteral("proton-cachyos")));
    QVERIFY(firstRel.value(QStringLiteral("fileName"))
                .toString()
                .endsWith(QStringLiteral(".tar.xz")));

    // 3. Test tag generation
    RunnerRecord rGe;
    rGe.id = QStringLiteral("r-ge");
    rGe.name = QStringLiteral("GE-Proton");
    rGe.type = QStringLiteral("proton-ge");
    rGe.path = QStringLiteral("/bin");
    rGe.binaryPath = QStringLiteral("/bin/true");
    QVERIFY(db.saveRunner(rGe));
    QCOMPARE(rm.runnerTagForId(rGe.id), QStringLiteral("PROTON-GE"));

    RunnerRecord rCachy;
    rCachy.id = QStringLiteral("r-cachy");
    rCachy.name = QStringLiteral("Proton-CachyOS");
    rCachy.type = QStringLiteral("proton-cachyos");
    rCachy.path = QStringLiteral("/bin");
    rCachy.binaryPath = QStringLiteral("/bin/true");
    QVERIFY(db.saveRunner(rCachy));
    QCOMPARE(rm.runnerTagForId(rCachy.id), QStringLiteral("CACHYOS"));

    // 4. Test custom runner resolution
    RunnerRecord rCustom;
    rCustom.id = QStringLiteral("custom-1");
    rCustom.name = QStringLiteral("Test Custom Runner");
    rCustom.type = QStringLiteral("custom");
    rCustom.path = QStringLiteral("/tmp");
    rCustom.binaryPath = QStringLiteral("/bin/true");
    QVERIFY(db.saveRunner(rCustom));
    QCOMPARE(rm.runnerTagForId(rCustom.id), QStringLiteral("CUSTOM"));
  }

  void testRunnerManagerSecurityAndUninstall() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath("test_security.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager rm(&db, &settings, &dl);

    // Security: system runners must NEVER delete files
    const QString fakeSystemPath = tmpDir.filePath("system_proton");
    QDir().mkpath(fakeSystemPath);
    QFile sysFile(fakeSystemPath + QStringLiteral("/proton"));
    QVERIFY(sysFile.open(QIODevice::WriteOnly));
    sysFile.close();

    RunnerRecord sysRec;
    sysRec.id = QStringLiteral("sys-proton");
    sysRec.name = QStringLiteral("System Proton");
    sysRec.type = QStringLiteral("proton");
    sysRec.path = fakeSystemPath;
    sysRec.binaryPath = sysFile.fileName();
    sysRec.isSystem = true;
    db.saveRunner(sysRec);

    // Call uninstallRunner: should remove from DB, but KEEP files on disk
    QVERIFY(rm.uninstallRunner(sysRec.id));
    QVERIFY(!db.getRunner(sysRec.id).has_value());
    QVERIFY(QFileInfo::exists(fakeSystemPath + QStringLiteral("/proton")));

    // Security: user runner inside defaultRunnerLocation CAN delete files
    const QString runnerBase = settings.defaultRunnerLocation();
    const QString customInstall =
        runnerBase + QStringLiteral("/test_installed_proton");
    QDir().mkpath(customInstall);
    QFile userFile(customInstall + QStringLiteral("/proton"));
    QVERIFY(userFile.open(QIODevice::WriteOnly));
    userFile.close();

    RunnerRecord userRec;
    userRec.id = QStringLiteral("user-proton");
    userRec.name = QStringLiteral("User Proton");
    userRec.type = QStringLiteral("proton-ge");
    userRec.path = customInstall;
    userRec.binaryPath = userFile.fileName();
    userRec.isSystem = false;
    db.saveRunner(userRec);

    QVERIFY(rm.uninstallRunner(userRec.id));
    QVERIFY(!db.getRunner(userRec.id).has_value());
    QVERIFY(!QDir(customInstall).exists());
  }

  void testDownloadManagerListModelAndCancellation() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DownloadManager dl;

    QCOMPARE(dl.rowCount(), 0);
    QCOMPARE(dl.activeDownloadCount(), 0);

    const QString dest = tmpDir.filePath("test_dl.tar.gz");
    const QString taskId = dl.enqueueDownload(
        QStringLiteral("test-task-1"), QStringLiteral("Test Runner DL"),
        QUrl(QStringLiteral("https://127.0.0.1:9999/nonexistent.tar.gz")),
        dest);
    QCOMPARE(taskId, QStringLiteral("test-task-1"));
    QCOMPARE(dl.rowCount(), 1);
    QCOMPARE(dl.activeDownloadCount(), 1);
    QVERIFY(dl.isMediaDownloading(taskId));

    // Test QAbstractListModel data roles
    QModelIndex idx = dl.index(0, 0);
    QVERIFY(idx.isValid());
    QCOMPARE(dl.data(idx, DownloadManager::IdRole).toString(),
             QStringLiteral("test-task-1"));
    QCOMPARE(dl.data(idx, DownloadManager::TitleRole).toString(),
             QStringLiteral("Test Runner DL"));
    QCOMPARE(dl.data(idx, DownloadManager::IsPausedRole).toBool(), false);

    // Test cancel: should not crash, removes row, deletes part file
    dl.cancelDownload(taskId);
    QCOMPARE(dl.rowCount(), 0);
    QCOMPARE(dl.activeDownloadCount(), 0);
    QVERIFY(!dl.isMediaDownloading(taskId));
    QVERIFY(!QFile::exists(dest + QStringLiteral(".part")));
  }

  void testThemeColorsAndAmoledCustomization() {
    AppSettings settings;
    settings.resetBgColor();
    settings.resetSidebarColor();
    settings.setAccentColor(QColor(QStringLiteral("#d71920")));

    // 1. Test AMOLED Theme Mode (mode 3)
    settings.setThemeMode(3);
    QCOMPARE(settings.themeMode(), 3);
    QVERIFY(settings.isEffectiveDark());
    QCOMPARE(settings.bgColor(), QColor("#000000"));
    QCOMPARE(settings.sidebarColor(), QColor("#000000"));
    QCOMPARE(settings.surfaceContainerLowest(), QColor("#000000"));
    QCOMPARE(settings.surfaceColor(), settings.surfaceContainerLow());
    QCOMPARE(settings.surfaceAltColor(), settings.surfaceContainer());
    QCOMPARE(settings.inputColor(), settings.surfaceContainerHigh());
    QVERIFY(settings.surfaceContainerLow().lightness() >
            settings.surfaceContainerLowest().lightness());
    QVERIFY(settings.surfaceContainer().lightness() >
            settings.surfaceContainerLow().lightness());
    QVERIFY(settings.surfaceContainerHigh().lightness() >
            settings.surfaceContainer().lightness());
    QVERIFY(settings.surfaceContainerHighest().lightness() >
            settings.surfaceContainerHigh().lightness());

    // 2. Test Custom Background Color & Container Harmonization
    settings.setThemeMode(0); // Dark mode
    settings.setCustomBgColor("#123456");
    QCOMPARE(settings.customBgColor(), QString("#123456"));
    QCOMPARE(settings.bgColor(), QColor("#123456"));
    QCOMPARE(settings.surfaceContainerLowest(), QColor("#123456"));
    // Container colors harmonize with selected background color
    QCOMPARE(settings.surfaceColor().hue(), QColor("#123456").hue());
    QVERIFY(settings.surfaceColor().lightness() >
            QColor("#123456").lightness());
    QVERIFY(settings.surfaceAltColor().lightness() >
            settings.surfaceColor().lightness());

    // Reset Background Color & verify M3 Dark 5-tier tonal ramp
    settings.resetBgColor();
    QVERIFY(settings.customBgColor().isEmpty());
    QCOMPARE(settings.bgColor(), QColor("#0d0d11"));
    QCOMPARE(settings.surfaceContainerLowest(), QColor("#0e0c0c"));
    QCOMPARE(settings.surfaceContainerLow(), QColor("#181414"));
    QCOMPARE(settings.surfaceContainer(), QColor("#201a1a"));
    QCOMPARE(settings.surfaceContainerHigh(), QColor("#2b2323"));
    QCOMPARE(settings.surfaceContainerHighest(), QColor("#362c2c"));
    QCOMPARE(settings.surfaceColor(), settings.surfaceContainerLow());
    QCOMPARE(settings.surfaceAltColor(), settings.surfaceContainer());
    QCOMPARE(settings.inputColor(), settings.surfaceContainerHigh());

    // Verify M3 Light 5-tier tonal ramp
    settings.setThemeMode(1); // Light mode
    QVERIFY(!settings.isEffectiveDark());
    QCOMPARE(settings.surfaceContainerLowest(), QColor("#ffffff"));
    QCOMPARE(settings.surfaceContainerLow(), QColor("#f7f2f2"));
    QCOMPARE(settings.surfaceContainer(), QColor("#f1ecec"));
    QCOMPARE(settings.surfaceContainerHigh(), QColor("#ebe5e5"));
    QCOMPARE(settings.surfaceContainerHighest(), QColor("#e4dede"));
    QCOMPARE(settings.surfaceColor(), settings.surfaceContainerLow());
    QCOMPARE(settings.surfaceAltColor(), settings.surfaceContainer());
    QCOMPARE(settings.inputColor(), settings.surfaceContainerHigh());
    settings.setThemeMode(0);

    // 3. Test Sidebar Sync
    settings.setCustomBgColor("#000000");
    settings.setSyncSidebarColor(true);
    QVERIFY(settings.syncSidebarColor());
    QCOMPARE(settings.sidebarColor(), settings.bgColor());

    // 4. Test Independent Custom Sidebar Color
    settings.setSyncSidebarColor(false);
    settings.setCustomSidebarColor("#1e232d");
    // Explicitly setting custom sidebar color automatically sets sync to false
    QVERIFY(!settings.syncSidebarColor());
    QCOMPARE(settings.customSidebarColor(), QString("#1e232d"));
    QCOMPARE(settings.sidebarColor(), QColor("#1e232d"));

    // Reset Sidebar Color
    settings.resetSidebarColor();
    QVERIFY(settings.customSidebarColor().isEmpty());
    QCOMPARE(settings.sidebarColor(), QColor("#111116"));

    // 5. Test Accent Color invokable & onPrimary / secondaryContainer
    settings.setAccentColor(QColor("#d71920"));
    QCOMPARE(settings.onPrimary(), QColor("#ffffff"));
    QVERIFY(settings.secondaryContainer().isValid());
    QVERIFY(settings.onSecondaryContainer().lightnessF() >
            settings.secondaryContainer().lightnessF());

    settings.setAccentColor(QColor("#38bdf8"));
    QCOMPARE(settings.accentColor(), QColor("#38bdf8"));
    QVERIFY(settings.onPrimary().lightnessF() < 0.25f);

    settings.setAccentColor(QColor("#ec4899"));
    QCOMPARE(settings.accentColor(), QColor("#ec4899"));

    // Clean up
    settings.resetBgColor();
    settings.resetSidebarColor();
    settings.setSyncSidebarColor(false);
    settings.setAccentColor(QColor(QStringLiteral("#d71920")));
    settings.setThemeMode(0);
  }

  void testShowGameNameSetting() {
    AppSettings settings;
    settings.setShowGameName(false);
    QCOMPARE(settings.showGameName(), false);

    bool signalFired = false;
    QObject::connect(&settings, &AppSettings::cardStyleChanged,
                     [&]() { signalFired = true; });

    settings.setShowGameName(true);
    QCOMPARE(settings.showGameName(), true);
    QVERIFY(signalFired);

    settings.setShowGameName(false);
    QCOMPARE(settings.showGameName(), false);
  }

  void testGamepadAutoDetectionIconsAndInputNavigation() {
    // 1. Controller type auto-detection (PlayStation vs Xbox vs vendor IDs &
    // names)
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Unknown Pad"), 0, SDL_CONTROLLER_TYPE_PS4),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Unknown Pad"), 0, SDL_CONTROLLER_TYPE_PS5),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Sony Controller"), 0x054c,
                 SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("DualSense Wireless Controller"), 0,
                 SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("playstation"));
    QCOMPARE(
        ControllerManager::detectControllerTypeFromInfo(
            QStringLiteral("PS4 Controller"), 0, SDL_CONTROLLER_TYPE_UNKNOWN),
        QStringLiteral("playstation"));

    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Xbox Pad"), 0, SDL_CONTROLLER_TYPE_XBOXONE),
             QStringLiteral("xbox"));
    QCOMPARE(
        ControllerManager::detectControllerTypeFromInfo(
            QStringLiteral("Controller"), 0x045e, SDL_CONTROLLER_TYPE_UNKNOWN),
        QStringLiteral("xbox"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Xbox Wireless Controller"), 0,
                 SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("xbox"));
    QCOMPARE(
        ControllerManager::detectControllerTypeFromInfo(
            QStringLiteral("Generic Gamepad"), 0, SDL_CONTROLLER_TYPE_UNKNOWN),
        QStringLiteral("xbox"));

    // 2. Dynamic icons & controllerType override
    QTemporaryDir dir;
    QVERIFY(dir.isValid());
    DatabaseManager db(dir.filePath("gamepad_nav_test.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dlMgr;
    RunnerManager runnerMgr(&db, &settings, &dlMgr);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dlMgr);
    ControllerManager ctrlMgr(&db, &settings,
                              std::make_unique<MockUinputBackend>());
    SteamGridDbService sgdb(&settings, &dlMgr);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    GameManager gameMgr(&db, &settings, &runnerMgr, &prefixMgr, &sgdb,
                        &pipeline);
    UiController uiCtrl(&db, &settings, &dlMgr, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gameMgr);

    ctrlMgr.setControllerTypeOverride(QStringLiteral("playstation"));
    QCOMPARE(ctrlMgr.controllerType(), QStringLiteral("playstation"));
    QVERIFY(ctrlMgr.isPlayStation());
    QVERIFY(!ctrlMgr.isXbox());
    QCOMPARE(ctrlMgr.settingsIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/options.svg"));
    QCOMPARE(ctrlMgr.tabLeftIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/l1.svg"));
    QCOMPARE(ctrlMgr.tabLeftTriggerIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/l2.svg"));
    QCOMPARE(ctrlMgr.tabRightIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/r1.svg"));
    QCOMPARE(ctrlMgr.tabRightTriggerIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/ps/r2.svg"));

    ctrlMgr.setControllerTypeOverride(QStringLiteral("xbox"));
    QCOMPARE(ctrlMgr.controllerType(), QStringLiteral("xbox"));
    QVERIFY(!ctrlMgr.isPlayStation());
    QVERIFY(ctrlMgr.isXbox());
    QCOMPARE(ctrlMgr.settingsIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/xbox-menu.svg"));
    QCOMPARE(ctrlMgr.tabLeftIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/lb.svg"));
    QCOMPARE(ctrlMgr.tabLeftTriggerIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/lt.svg"));
    QCOMPARE(ctrlMgr.tabRightIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/rb.svg"));
    QCOMPARE(ctrlMgr.tabRightTriggerIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/xbox/rt.svg"));

    QCOMPARE(ctrlMgr.confirmIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-down.svg"));
    QCOMPARE(ctrlMgr.cancelIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"));
    QCOMPARE(ctrlMgr.optionsIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-left.svg"));
    QCOMPARE(ctrlMgr.searchIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"));
    QCOMPARE(ctrlMgr.dpadUpIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/dpad-up.svg"));
    QCOMPARE(ctrlMgr.leftAnalogIconSource(),
             QStringLiteral("qrc:/tsuki_app/icons/gamepad/left-analog.svg"));

    // 3. SDL button signals & trigger hysteresis + UiController activeInputType
    // switching
    QSignalSpy optionsSpy(&ctrlMgr, &ControllerManager::optionsActionRequested);
    QSignalSpy searchSpy(&ctrlMgr, &ControllerManager::searchActionRequested);
    QSignalSpy settingsSpy(&ctrlMgr,
                           &ControllerManager::settingsActionRequested);
    QSignalSpy tabLeftSpy(&ctrlMgr, &ControllerManager::tabLeftRequested);
    QSignalSpy tabRightSpy(&ctrlMgr, &ControllerManager::tabRightRequested);
    QSignalSpy inputSpy(&ctrlMgr, &ControllerManager::gamepadInputReceived);

    // Start in keyboard mode
    uiCtrl.setActiveInputType(QStringLiteral("keyboard"));
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("keyboard"));
    QVERIFY(!uiCtrl.isGamepadActive());

    // Simulate PlayStation gamepad press -> UiController switches
    // activeInputType to playstation
    ctrlMgr.setControllerTypeOverride(QStringLiteral("playstation"));
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_X);
    QCOMPARE(optionsSpy.count(), 1);
    QCOMPARE(inputSpy.count(), 1);
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("playstation"));
    QVERIFY(uiCtrl.isGamepadActive());
    QVERIFY(uiCtrl.isKeyboardNavActive());

    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_Y);
    QCOMPARE(searchSpy.count(), 1);

    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_START);
    QCOMPARE(settingsSpy.count(), 1);

    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);
    QCOMPARE(tabLeftSpy.count(), 1);
    QCOMPARE(tabRightSpy.count(), 1);

    // Trigger hysteresis: L2/R2 fire once above 16000, stay latched at 18000,
    // reset below 8000
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERLEFT, 20000);
    QCOMPARE(tabLeftSpy.count(), 2);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERLEFT, 18000);
    QCOMPARE(tabLeftSpy.count(), 2);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERLEFT, 4000);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERLEFT, 20000);
    QCOMPARE(tabLeftSpy.count(), 3);

    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 20000);
    QCOMPARE(tabRightSpy.count(), 2);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 18000);
    QCOMPARE(tabRightSpy.count(), 2);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 4000);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 20000);
    QCOMPARE(tabRightSpy.count(), 3);

    // Switch controller override to Xbox and trigger button -> activeInputType
    // tracks xbox
    ctrlMgr.setControllerTypeOverride(QStringLiteral("xbox"));
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_A);
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("xbox"));
    QVERIFY(uiCtrl.isGamepadActive());

    // Switching back to keyboard disables gamepad prompts
    uiCtrl.setActiveInputType(QStringLiteral("keyboard"));
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("keyboard"));
    QVERIFY(!uiCtrl.isGamepadActive());

    // While a game is running, controller input must not trigger Tsuki UI
    // navigation
    ctrlMgr.setGameRunning(true);
    QVERIFY(ctrlMgr.isGameRunning());
    const int settingsBefore = settingsSpy.count();
    const int tabLeftBefore = tabLeftSpy.count();
    const int tabRightBefore = tabRightSpy.count();
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_START);
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_A);
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERLEFT, 20000);
    ctrlMgr.handleAxisMotion(SDL_CONTROLLER_AXIS_TRIGGERRIGHT, 20000);
    QCOMPARE(settingsSpy.count(), settingsBefore);
    QCOMPARE(tabLeftSpy.count(), tabLeftBefore);
    QCOMPARE(tabRightSpy.count(), tabRightBefore);

    // Stopping the game re-enables UI controller navigation
    ctrlMgr.setGameRunning(false);
    QVERIFY(!ctrlMgr.isGameRunning());
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_START);
    QCOMPARE(settingsSpy.count(), settingsBefore + 1);
  }

  void testUiControllerInputSwitchingAndQmlNavigation() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath("test_ui_nav.db"));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    const QString gameId = gm.addGame("Test Game", "/games/test.exe");
    QVERIFY(!gameId.isEmpty());

    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm);

    QQuickWindow win;
    win.resize(1280, 820);

    // 1. KeyPress (Down, Space, Tab) activates keyboard nav and hides cursor
    QKeyEvent keyDown(QEvent::KeyPress, Qt::Key_Down, Qt::NoModifier);
    QCoreApplication::sendEvent(&win, &keyDown);
    QVERIFY(uiCtrl.isKeyboardNavActive());
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("keyboard"));
    QVERIFY(QGuiApplication::overrideCursor() != nullptr);
    QCOMPARE(QGuiApplication::overrideCursor()->shape(), Qt::BlankCursor);

    // 2. MouseMove with >= 2px delta immediately deactivates keyboard nav and
    // restores cursor
    QMouseEvent move1(QEvent::MouseMove, QPointF(100, 100), QPointF(100, 100),
                      Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&win, &move1);
    QVERIFY(!uiCtrl.isKeyboardNavActive());
    QVERIFY(QGuiApplication::overrideCursor() == nullptr);

    // 3. Space key re-activates keyboard nav
    QKeyEvent keySpace(QEvent::KeyPress, Qt::Key_Space, Qt::NoModifier,
                       QStringLiteral(" "));
    QCoreApplication::sendEvent(&win, &keySpace);
    QVERIFY(uiCtrl.isKeyboardNavActive());

    // 4. Wheel event immediately deactivates keyboard nav
    QWheelEvent wheel(QPointF(100, 100), QPointF(100, 100), QPoint(0, 0),
                      QPoint(0, 120), Qt::NoButton, Qt::NoModifier,
                      Qt::NoScrollPhase, false);
    QCoreApplication::sendEvent(&win, &wheel);
    QVERIFY(!uiCtrl.isKeyboardNavActive());

    // 5. Tab key activates keyboard nav
    QKeyEvent keyTab(QEvent::KeyPress, Qt::Key_Tab, Qt::NoModifier);
    QCoreApplication::sendEvent(&win, &keyTab);
    QVERIFY(uiCtrl.isKeyboardNavActive());

    // 6. Small MouseMove delta >= 2px after initial position deactivates again
    QMouseEvent move2(QEvent::MouseMove, QPointF(105, 105), QPointF(105, 105),
                      Qt::NoButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(&win, &move2);
    QVERIFY(!uiCtrl.isKeyboardNavActive());

    // 7. Load GameDetailPage.qml & SettingsPage.qml and verify zero QML errors
    // + M3TextField nav
    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QQmlComponent settingsComp(&engine, resolveQmlUrl(QStringLiteral(
                                            "src/qml/pages/SettingsPage.qml")));
    QVERIFY2(settingsComp.errors().isEmpty(),
             qPrintable(settingsComp.errorString()));
    QScopedPointer<QObject> settingsObj(settingsComp.create());
    QVERIFY(settingsObj != nullptr);
    auto *settingsItem = qobject_cast<QQuickItem *>(settingsObj.get());
    QVERIFY(settingsItem != nullptr);
    settingsItem->setParentItem(win.contentItem());
    settingsItem->setSize(QSizeF(1280, 820));

    QQmlComponent detailComp(&engine, resolveQmlUrl(QStringLiteral(
                                          "src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.errors().isEmpty(),
             qPrintable(detailComp.errorString()));
    QScopedPointer<QObject> detailObj(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), gameId}}));
    QVERIFY(detailObj != nullptr);
    auto *detailItem = qobject_cast<QQuickItem *>(detailObj.get());
    QVERIFY(detailItem != nullptr);
    detailItem->setParentItem(win.contentItem());
    detailItem->setSize(QSizeF(1280, 820));

    win.show();
    QCoreApplication::processEvents();

    // Navigate down from primaryActionBtn -> tabsBar -> titleField ->
    // exePathField Verifies titleField (M3TextField wrapper) does NOT freeze
    // isTextInputActive()
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();

    QVariant isEditingVar;
    QVERIFY(QMetaObject::invokeMethod(detailObj.get(), "isTextInputActive",
                                      Q_RETURN_ARG(QVariant, isEditingVar)));
    QVERIFY(!isEditingVar.toBool());

    // Must still be able to press Down past titleField onto exePathField!
    QObject *focusOnTitle = win.activeFocusItem();
    QVERIFY(focusOnTitle != nullptr);
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QObject *focusAfterDown = win.activeFocusItem();
    QVERIFY(focusAfterDown != nullptr);
    QVERIFY(focusAfterDown != focusOnTitle);

    // Move mouse >= 2px while detail page is open -> immediately hides keyboard
    // nav
    QMouseEvent moveHide(QEvent::MouseMove, QPointF(250, 250),
                         QPointF(250, 250), Qt::NoButton, Qt::NoButton,
                         Qt::NoModifier);
    QCoreApplication::sendEvent(&win, &moveHide);
    QVERIFY(!uiCtrl.isKeyboardNavActive());

    // 8. Verify showNavigationHud setting toggles NavigationHudBar showBar and
    // emits signal
    const bool origHud = settings.showNavigationHud();
    QSignalSpy behaviorSpy(&settings, &AppSettings::behaviorChanged);
    QQmlComponent hudComp(&engine,
                          resolveQmlUrl(QStringLiteral(
                              "src/qml/components/NavigationHudBar.qml")));
    QVERIFY2(hudComp.errors().isEmpty(), qPrintable(hudComp.errorString()));
    QScopedPointer<QObject> hudObj(hudComp.create());
    QVERIFY(hudObj != nullptr);

    settings.setShowNavigationHud(true);
    uiCtrl.setKeyboardNavActive(true);
    QCOMPARE(hudObj->property("showBar").toBool(), true);
    settings.setShowNavigationHud(false);
    QCOMPARE(hudObj->property("showBar").toBool(), false);
    QVERIFY(behaviorSpy.count() >= 1);
    settings.setShowNavigationHud(origHud);

    // 9. Verify RunnersView.qml compiles/loads cleanly with active downloads
    // navigation
    QQmlComponent runnersComp(&engine, resolveQmlUrl(QStringLiteral(
                                           "src/qml/pages/RunnersView.qml")));
    QVERIFY2(runnersComp.errors().isEmpty(),
             qPrintable(runnersComp.errorString()));
    QScopedPointer<QObject> runnersObj(runnersComp.create());
    QVERIFY(runnersObj != nullptr);
  }

  void testGamescopeSupportAndPipeline() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    // Backup global QSettings keys modified by this test
    QSettings rawSettings(QStringLiteral("Tsuki"),
                          QStringLiteral("TsukiLauncher"));
    const bool hadGsDefault =
        rawSettings.contains(QStringLiteral("performance/gamescope"));
    const QVariant oldGsDefault =
        rawSettings.value(QStringLiteral("performance/gamescope"));
    const bool hadGsCfg =
        rawSettings.contains(QStringLiteral("performance/gamescopeConfig"));
    const QVariant oldGsCfg =
        rawSettings.value(QStringLiteral("performance/gamescopeConfig"));
    const QByteArray oldPath = qgetenv("PATH");

    auto restoreEnv = qScopeGuard([&]() {
      if (hadGsDefault)
        rawSettings.setValue(QStringLiteral("performance/gamescope"),
                             oldGsDefault);
      else
        rawSettings.remove(QStringLiteral("performance/gamescope"));
      if (hadGsCfg)
        rawSettings.setValue(QStringLiteral("performance/gamescopeConfig"),
                             oldGsCfg);
      else
        rawSettings.remove(QStringLiteral("performance/gamescopeConfig"));
      qputenv("PATH", oldPath);
    });

    rawSettings.remove(QStringLiteral("performance/gamescope"));
    rawSettings.remove(QStringLiteral("performance/gamescopeConfig"));

    // 1. GamescopeConfig JSON round-trip and normalization bounds
    GameRecord rec;
    rec.id = QStringLiteral("gs-json-test");
    rec.gamescopeState = 1;
    rec.gamescope.inheritGlobal = false;
    rec.gamescope.windowMode = QStringLiteral("borderless");
    rec.gamescope.outputWidth = 2560;
    rec.gamescope.outputHeight = 1440;
    rec.gamescope.internalWidth = 1920;
    rec.gamescope.internalHeight = 1080;
    rec.gamescope.filter = QStringLiteral("fsr");
    rec.gamescope.fsrSharpness = 99; // Should clamp to 20
    rec.gamescope.scaler = QStringLiteral("integer");
    rec.gamescope.fpsLimit = 120;
    rec.gamescope.unfocusedFpsLimit = 30;
    rec.gamescope.adaptiveSync = true;
    rec.gamescope.hdrEnabled = true;
    rec.gamescope.forceGrabCursor = true;
    rec.gamescope.mouseSensitivity = 9.0; // Should clamp to 5.0
    rec.gamescope.mangoapp = false;
    rec.gamescope.backend = QStringLiteral("wayland");
    rec.gamescope.exposeWayland = true;
    rec.gamescope.extraArgs = QStringLiteral(" --rt ");
    rec.gamescope.normalize();

    QCOMPARE(rec.gamescope.fsrSharpness, 20);
    QCOMPARE(rec.gamescope.mouseSensitivity, 5.0);
    QCOMPARE(rec.gamescope.extraArgs, QStringLiteral("--rt"));

    GameRecord restored;
    restored.applyLaunchConfigJson(rec.launchConfigToJson());
    QCOMPARE(restored.gamescopeState, 1);
    QVERIFY(restored.gamescope == rec.gamescope);

    // 2. AppSettings global Gamescope default is false by default & persists
    // cleanly
    AppSettings settings;
    QCOMPARE(settings.gamescopeDefault(), false);
    settings.setGamescopeDefault(true);
    QVariantMap customGlobal = settings.defaultGamescopeConfig();
    customGlobal[QStringLiteral("windowMode")] = QStringLiteral("borderless");
    customGlobal[QStringLiteral("fpsLimit")] = 60;
    settings.setDefaultGamescopeConfig(customGlobal);

    AppSettings reloadedSettings;
    QCOMPARE(reloadedSettings.gamescopeDefault(), true);
    QCOMPARE(reloadedSettings.defaultGamescopeConfig()
                 .value(QStringLiteral("windowMode"))
                 .toString(),
             QStringLiteral("borderless"));
    QCOMPARE(reloadedSettings.defaultGamescopeConfig()
                 .value(QStringLiteral("fpsLimit"))
                 .toInt(),
             60);

    reloadedSettings.resetDefaultGamescopeConfig();
    QCOMPARE(reloadedSettings.defaultGamescopeConfig()
                 .value(QStringLiteral("windowMode"))
                 .toString(),
             QStringLiteral("fullscreen"));
    settings.setGamescopeDefault(false);

    // 3. Create deterministic mock executables in temporary bin dir
    const QString mockBinDir = tmpDir.filePath(QStringLiteral("mock_bin"));
    QVERIFY(QDir().mkpath(mockBinDir));
    auto makeExec = [&](const QString &name) -> QString {
      const QString p = mockBinDir + QLatin1Char('/') + name;
      QFile f(p);
      if (!f.open(QIODevice::WriteOnly))
        return QString();
      f.write("#!/bin/sh\nexit 0\n");
      f.close();
      if (!QFile::setPermissions(p, QFile::ReadOwner | QFile::WriteOwner |
                                        QFile::ExeOwner | QFile::ReadGroup |
                                        QFile::ExeGroup)) {
        return QString();
      }
      return p;
    };
    const QString mockGamescope = makeExec(QStringLiteral("gamescope"));
    const QString mockMangohud = makeExec(QStringLiteral("mangohud"));
    const QString mockGamemode = makeExec(QStringLiteral("gamemoderun"));
    const QString nativeGameBin = makeExec(QStringLiteral("native_game"));
    QVERIFY(!mockGamescope.isEmpty());
    QVERIFY(!mockMangohud.isEmpty());
    QVERIFY(!mockGamemode.isEmpty());
    QVERIFY(!nativeGameBin.isEmpty());

    qputenv("PATH", mockBinDir.toUtf8() + ":" + oldPath);

    DatabaseManager db(tmpDir.filePath(QStringLiteral("gs.db")));
    QVERIFY(db.initialize());
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    SteamGridDbService sgdb(&settings, &dl);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    // 4. DiagnosticsManager reports gamescope availability
    QVERIFY(diagMgr.gamescopeAvailable());
    bool foundGsCheck = false;
    for (const QVariant &item : diagMgr.systemChecks()) {
      const QVariantMap m = item.toMap();
      if (m.value(QStringLiteral("name"))
              .toString()
              .contains(QStringLiteral("Gamescope"), Qt::CaseInsensitive)) {
        foundGsCheck = true;
        QCOMPARE(m.value(QStringLiteral("ok")).toBool(), true);
        QVERIFY(m.value(QStringLiteral("detail"))
                    .toString()
                    .contains(mockGamescope));
      }
    }
    QVERIFY(foundGsCheck);

    // 5. GameManager::updateGameDetails persists ONLY Gamescope changes
    const QString winGameId = gm.addGame(QStringLiteral("Proton Title"),
                                         QStringLiteral("/games/win.exe"));
    QVERIFY(!winGameId.isEmpty());
    QVariantMap gsMap;
    gsMap[QStringLiteral("inheritGlobal")] = false;
    gsMap[QStringLiteral("windowMode")] = QStringLiteral("fullscreen");
    gsMap[QStringLiteral("outputWidth")] = 1920;
    gsMap[QStringLiteral("outputHeight")] = 1080;
    gsMap[QStringLiteral("internalWidth")] = 1280;
    gsMap[QStringLiteral("internalHeight")] = 720;
    gsMap[QStringLiteral("filter")] = QStringLiteral("fsr");
    gsMap[QStringLiteral("fsrSharpness")] = 3;
    gsMap[QStringLiteral("scaler")] = QStringLiteral("integer");
    gsMap[QStringLiteral("fpsLimit")] = 60;
    gsMap[QStringLiteral("unfocusedFpsLimit")] = 15;
    gsMap[QStringLiteral("adaptiveSync")] = true;
    gsMap[QStringLiteral("hdrEnabled")] = true;
    gsMap[QStringLiteral("forceGrabCursor")] = true;
    gsMap[QStringLiteral("mouseSensitivity")] = 1.4;
    gsMap[QStringLiteral("mangoapp")] = true;
    gsMap[QStringLiteral("backend")] = QStringLiteral("wayland");
    gsMap[QStringLiteral("exposeWayland")] = true;
    gsMap[QStringLiteral("extraArgs")] = QStringLiteral("--rt -O \"DP-1\"");

    QVERIFY(gm.updateGameDetails(
        winGameId, QVariantMap{{QStringLiteral("gamescopeState"), 1},
                               {QStringLiteral("gamescope"), gsMap},
                               {QStringLiteral("mangohudState"), 1},
                               {QStringLiteral("gamemodeState"), 1},
                               {QStringLiteral("virtualDesktop"), true}}));

    auto winGameOpt = db.getGame(winGameId);
    QVERIFY(winGameOpt.has_value());
    QCOMPARE(winGameOpt->gamescopeState, 1);
    QCOMPARE(winGameOpt->gamescope.inheritGlobal, false);
    QCOMPARE(winGameOpt->gamescope.filter, QStringLiteral("fsr"));
    QCOMPARE(winGameOpt->gamescope.fsrSharpness, 3);
    QCOMPARE(winGameOpt->gamescope.hdrEnabled, true);

    // 6. LaunchPipeline Wine/Proton plan with Gamescope + MangoApp + GameMode +
    // HDR
    RunnerRecord protonRunner;
    protonRunner.id = QStringLiteral("proton-ge");
    protonRunner.name = QStringLiteral("GE-Proton");
    protonRunner.type = QStringLiteral("proton-ge");
    protonRunner.binaryPath = QStringLiteral("/opt/proton-ge/proton");
    PrefixRecord prefix;
    prefix.id = QStringLiteral("pfx-1");
    prefix.path = tmpDir.filePath(QStringLiteral("pfx"));
    prefix.arch = QStringLiteral("win64");

    const LaunchPlan gsPlan =
        pipeline.buildLaunchPlan(*winGameOpt, protonRunner, prefix);
    QVERIFY(gsPlan.usesGamescope);
    QCOMPARE(gsPlan.program, mockGamemode);
    QCOMPARE(gsPlan.environment.value(QStringLiteral("DXVK_HDR")),
             QStringLiteral("1"));
    QVERIFY(!gsPlan.environment.contains(
        QStringLiteral("MANGOHUD"))); // --mangoapp replaces MANGOHUD=1

    const int gsIdx = gsPlan.arguments.indexOf(mockGamescope);
    const int sepIdx = gsPlan.arguments.indexOf(QStringLiteral("--"));
    const int protonIdx = gsPlan.arguments.indexOf(protonRunner.binaryPath);
    QVERIFY(gsIdx >= 0);
    QVERIFY(sepIdx > gsIdx);
    QVERIFY(protonIdx == sepIdx + 1);
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--mangoapp")));
    QVERIFY(!gsPlan.arguments.contains(mockMangohud));
    QVERIFY(!gsPlan.arguments.contains(QStringLiteral(
        "explorer"))); // Virtual desktop suppressed under Gamescope
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-f")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-W")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("1920")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-w")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("1280")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-F")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("fsr")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--fsr-sharpness")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-S")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("integer")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-r")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("60")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-o")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("15")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--adaptive-sync")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--hdr-enabled")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--force-grab-cursor")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-s")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("1.4")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--backend")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("wayland")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--expose-wayland")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--rt")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("-O")));
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("DP-1")));

    // 7. Disabling mangoapp falls back to external mangohud after '--'
    GameRecord extMangoGame = *winGameOpt;
    extMangoGame.gamescope.mangoapp = false;
    const LaunchPlan extPlan =
        pipeline.buildLaunchPlan(extMangoGame, protonRunner, prefix);
    QCOMPARE(extPlan.environment.value(QStringLiteral("MANGOHUD")),
             QStringLiteral("1"));
    QVERIFY(!extPlan.arguments.contains(QStringLiteral("--mangoapp")));
    const int extSep = extPlan.arguments.indexOf(QStringLiteral("--"));
    const int extMango = extPlan.arguments.indexOf(mockMangohud);
    const int extProton = extPlan.arguments.indexOf(protonRunner.binaryPath);
    QVERIFY(extSep >= 0);
    QCOMPARE(extMango, extSep + 1);
    QCOMPARE(extProton, extSep + 2);

    // 7b. Bare '--' in extraArgs is stripped while surrounding flags stay
    // intact
    GameRecord sepStripGame = *winGameOpt;
    sepStripGame.gamescope.extraArgs = QStringLiteral("--rt -- -O \"DP-1\"");
    const LaunchPlan sepStripPlan =
        pipeline.buildLaunchPlan(sepStripGame, protonRunner, prefix);
    QCOMPARE(sepStripPlan.arguments.count(QStringLiteral("--")), 1);
    const int strippedSepIdx =
        sepStripPlan.arguments.indexOf(QStringLiteral("--"));
    QVERIFY(strippedSepIdx >
            sepStripPlan.arguments.indexOf(QStringLiteral("--rt")));
    QVERIFY(strippedSepIdx >
            sepStripPlan.arguments.indexOf(QStringLiteral("-O")));
    QVERIFY(strippedSepIdx >
            sepStripPlan.arguments.indexOf(QStringLiteral("DP-1")));

    // 8. Native Linux game inheriting global Gamescope default (-1 &
    // inheritGlobal=true)
    const QString nativeId =
        gm.addNativeGame(QStringLiteral("Native Game"), nativeGameBin,
                         tmpDir.path(), QStringLiteral("--test-flag"));
    QVERIFY(!nativeId.isEmpty());
    auto nativeOpt = db.getGame(nativeId);
    QVERIFY(nativeOpt.has_value());

    settings.setGamescopeDefault(false);
    const LaunchPlan nativeOff = pipeline.buildNativeLaunchPlan(*nativeOpt);
    QVERIFY(!nativeOff.usesGamescope);
    QCOMPARE(nativeOff.program, nativeGameBin);

    settings.setGamescopeDefault(true);
    QVariantMap borderlessDef = settings.defaultGamescopeConfig();
    borderlessDef[QStringLiteral("windowMode")] = QStringLiteral("borderless");
    settings.setDefaultGamescopeConfig(borderlessDef);
    const LaunchPlan nativeOn = pipeline.buildNativeLaunchPlan(*nativeOpt);
    QVERIFY(nativeOn.usesGamescope);
    QCOMPARE(nativeOn.program, mockGamescope);
    QVERIFY(nativeOn.arguments.contains(QStringLiteral("-b")));
    QVERIFY(nativeOn.arguments.contains(nativeGameBin));
    QVERIFY(nativeOn.arguments.contains(QStringLiteral("--test-flag")));

    // 9. Missing gamescope binary fails clearly via launchGame()
    qputenv("PATH", "");
    diagMgr.runSystemDiagnostics();
    QVERIFY(!diagMgr.gamescopeAvailable());

    QSignalSpy failedSpy(&pipeline, &LaunchPipeline::gameLaunchFailed);
    QVERIFY(!pipeline.launchGame(nativeId));
    QCOMPARE(failedSpy.count(), 1);
    QVERIFY(failedSpy.at(0).at(1).toString().contains(
        QStringLiteral("gamescope"), Qt::CaseInsensitive));
  }

  void testGamescopeQmlUiAndNavigation() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    QSettings rawSettings(QStringLiteral("Tsuki"),
                          QStringLiteral("TsukiLauncher"));
    const bool hadGsDefault =
        rawSettings.contains(QStringLiteral("performance/gamescope"));
    const QVariant oldGsDefault =
        rawSettings.value(QStringLiteral("performance/gamescope"));
    const bool hadGsCfg =
        rawSettings.contains(QStringLiteral("performance/gamescopeConfig"));
    const QVariant oldGsCfg =
        rawSettings.value(QStringLiteral("performance/gamescopeConfig"));
    auto restore = qScopeGuard([&]() {
      if (hadGsDefault)
        rawSettings.setValue(QStringLiteral("performance/gamescope"),
                             oldGsDefault);
      else
        rawSettings.remove(QStringLiteral("performance/gamescope"));
      if (hadGsCfg)
        rawSettings.setValue(QStringLiteral("performance/gamescopeConfig"),
                             oldGsCfg);
      else
        rawSettings.remove(QStringLiteral("performance/gamescopeConfig"));
    });
    rawSettings.remove(QStringLiteral("performance/gamescope"));
    rawSettings.remove(QStringLiteral("performance/gamescopeConfig"));

    DatabaseManager db(tmpDir.filePath(QStringLiteral("gs_qml.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    const QString gameId = gm.addGame(QStringLiteral("Hollow Knight"),
                                      QStringLiteral("/games/hk.exe"));
    QVERIFY(!gameId.isEmpty());

    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm);

    QQuickWindow win;
    win.resize(1280, 820);

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    // Load SettingsPage and confirm Gamescope rows are present and indexed
    // cleanly
    QQmlComponent settingsComp(&engine, resolveQmlUrl(QStringLiteral(
                                            "src/qml/pages/SettingsPage.qml")));
    QVERIFY2(settingsComp.errors().isEmpty(),
             qPrintable(settingsComp.errorString()));
    QScopedPointer<QObject> settingsObj(settingsComp.create());
    QVERIFY(settingsObj != nullptr);
    QVERIFY(settingsObj->findChild<QQuickItem *>(
                QStringLiteral("gamescopeDefaultRow")) != nullptr);
    QVERIFY(settingsObj->findChild<QQuickItem *>(
                QStringLiteral("gamescopeDefaultsConfigRow")) != nullptr);

    // Load GameDetailPage and switch to Tab 2 (Performance & Controller)
    QQmlComponent detailComp(&engine, resolveQmlUrl(QStringLiteral(
                                          "src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.errors().isEmpty(),
             qPrintable(detailComp.errorString()));
    QScopedPointer<QObject> detailObj(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), gameId}}));
    QVERIFY(detailObj != nullptr);
    auto *detailItem = qobject_cast<QQuickItem *>(detailObj.get());
    QVERIFY(detailItem != nullptr);
    detailItem->setParentItem(win.contentItem());
    detailItem->setSize(QSizeF(1280, 820));

    win.show();
    QCoreApplication::processEvents();

    detailObj->setProperty("activeTab", 2);
    QCoreApplication::processEvents();

    auto *gsToggle =
        detailItem->findChild<QQuickItem *>(QStringLiteral("gamescopeToggle"));
    auto *gsCustomizeBtn = detailItem->findChild<QQuickItem *>(
        QStringLiteral("gamescopeCustomizeBtn"));
    auto *gsDialog =
        detailObj->findChild<QObject *>(QStringLiteral("gamescopeDialog"));
    QVERIFY(gsToggle != nullptr);
    QVERIFY(gsCustomizeBtn != nullptr);
    QVERIFY(gsDialog != nullptr);

    // Disabled by default -> Customize button stays hidden
    QCOMPARE(gsToggle->property("checked").toBool(), false);
    QCOMPARE(gsCustomizeBtn->isVisible(), false);

    // Activate keyboard nav & toggle Gamescope ON -> Customize button appears &
    // DB persists
    uiCtrl.setKeyboardNavActive(true);
    gsToggle->forceActiveFocus();
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();

    QCOMPARE(gsToggle->property("checked").toBool(), true);
    QCOMPARE(gsCustomizeBtn->isVisible(), true);
    QCOMPARE(db.getGame(gameId)->gamescopeState, 1);

    // Left D-Pad/arrow moves cleanly onto Customize button; Return opens
    // GamescopeDialog
    QTest::keyClick(&win, Qt::Key_Left);
    QCoreApplication::processEvents();
    QCOMPARE(win.activeFocusItem(), gsCustomizeBtn);

    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();
    QTRY_COMPARE(gsDialog->property("visible").toBool(), true);
    QVERIFY(gsDialog->property("enter").value<QObject *>() != nullptr);
    QVERIFY(gsDialog->property("exit").value<QObject *>() != nullptr);
    QTRY_COMPARE(gsDialog->property("opened").toBool(), true);

    QVariant popupOpenVar;
    QVERIFY(QMetaObject::invokeMethod(detailObj.get(), "isAnyPopupOpen",
                                      Q_RETURN_ARG(QVariant, popupOpenVar)));
    QCOMPARE(popupOpenVar.toBool(), true);

    // Verify dialog styling, icons, right-aligned options, and keyboard/gamepad
    // nav inside dialog
    auto *dialogBg = gsDialog->property("background").value<QQuickItem *>();
    QVERIFY(dialogBg != nullptr);
    QCOMPARE(dialogBg->objectName(), QStringLiteral("gamescopeDialogBg"));
    QCOMPARE(dialogBg->property("radius").toDouble(), 12.0);

    auto *presetBtn = gsDialog->findChild<QQuickItem *>(
        QStringLiteral("gamescopePresetBorderlessBtn"));
    auto *windowSeg = gsDialog->findChild<QQuickItem *>(
        QStringLiteral("gamescopeWindowModeSeg"));
    auto *outCombo = gsDialog->findChild<QQuickItem *>(
        QStringLiteral("gamescopeOutputResCombo"));
    auto *outWField = gsDialog->findChild<QQuickItem *>(
        QStringLiteral("gamescopeOutputWField"));
    auto *sharpSlider = gsDialog->findChild<QQuickItem *>(
        QStringLiteral("gamescopeSharpnessSlider"));
    auto *adaptiveToggle = gsDialog->findChild<QQuickItem *>(
        QStringLiteral("gamescopeAdaptiveSyncToggle"));
    auto *cancelBtn =
        gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeCancelBtn"));
    auto *saveBtn =
        gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeSaveBtn"));
    QVERIFY(presetBtn != nullptr);
    QVERIFY(windowSeg != nullptr);
    QVERIFY(outCombo != nullptr);
    QVERIFY(outWField != nullptr);
    QVERIFY(sharpSlider != nullptr);
    QVERIFY(adaptiveToggle != nullptr);
    QVERIFY(cancelBtn != nullptr);
    QVERIFY(saveBtn != nullptr);

    const bool initiallyConnected = ctrlMgr.isConnected();
    QVERIFY(!uiCtrl.isGamepadActive());
    QCOMPARE(cancelBtn->property("iconSource").toString(), QString());
    QCOMPARE(saveBtn->property("iconSource").toString(),
             QStringLiteral("qrc:/tsuki_app/icons/actions/check.svg"));

    const int virtualJoyIdx =
        SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER, 2, 11, 1);
    bool virtualAttached = (virtualJoyIdx >= 0);
    auto detachVirtual = qScopeGuard([&]() {
      if (virtualAttached) {
        SDL_JoystickDetachVirtual(virtualJoyIdx);
        ctrlMgr.refreshControllers();
        QCoreApplication::processEvents();
      }
    });
    if (virtualAttached) {
      ctrlMgr.refreshControllers();
      QCoreApplication::processEvents();
      QVERIFY(ctrlMgr.isConnected());

      // Keyboard navigation with controller plugged in must still hide gamepad
      // button icons
      QVERIFY(uiCtrl.isKeyboardNavActive());
      QVERIFY(!uiCtrl.isGamepadActive());
      QCOMPARE(cancelBtn->property("iconSource").toString(), QString());
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/actions/check.svg"));

      // Switching to gamepad navigation shows gamepad icons on Cancel and Save
      uiCtrl.setActiveInputType(QStringLiteral("xbox"));
      uiCtrl.setKeyboardNavActive(true);
      QCoreApplication::processEvents();
      QVERIFY(uiCtrl.isGamepadActive());
      QCOMPARE(
          cancelBtn->property("iconSource").toString(),
          QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"));
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"));

      // Mouse navigation hides gamepad icons even while controller stays
      // connected
      QMouseEvent mouseMove(QEvent::MouseMove, QPointF(240, 240),
                            QPointF(240, 240), Qt::NoButton, Qt::NoButton,
                            Qt::NoModifier);
      QCoreApplication::sendEvent(&win, &mouseMove);
      QCoreApplication::processEvents();
      QVERIFY(!uiCtrl.isKeyboardNavActive());
      QVERIFY(!uiCtrl.isGamepadActive());
      QCOMPARE(cancelBtn->property("iconSource").toString(), QString());
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/actions/check.svg"));

      // Switching back to gamepad restores icons, then keyboard press hides
      // them again
      uiCtrl.setActiveInputType(QStringLiteral("playstation"));
      uiCtrl.setKeyboardNavActive(true);
      QCoreApplication::processEvents();
      QCOMPARE(
          cancelBtn->property("iconSource").toString(),
          QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"));
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"));

      QTest::keyClick(&win, Qt::Key_Up);
      QCoreApplication::processEvents();
      QVERIFY(uiCtrl.isKeyboardNavActive());
      QVERIFY(!uiCtrl.isGamepadActive());
      QCOMPARE(cancelBtn->property("iconSource").toString(), QString());
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/actions/check.svg"));

      if (!initiallyConnected) {
        SDL_JoystickDetachVirtual(virtualJoyIdx);
        virtualAttached = false;
        ctrlMgr.refreshControllers();
        QCoreApplication::processEvents();
        QVERIFY(!ctrlMgr.isConnected());
        QCOMPARE(cancelBtn->property("iconSource").toString(), QString());
        QCOMPARE(saveBtn->property("iconSource").toString(),
                 QStringLiteral("qrc:/tsuki_app/icons/actions/check.svg"));
      }
    }

    QCoreApplication::processEvents();
    auto verifyRightAlignedInCol = [](QQuickItem *ctrl, const char *name) {
      auto *row = ctrl ? ctrl->parentItem() : nullptr;
      auto *col = row ? row->parentItem() : nullptr;
      QVERIFY2(row != nullptr && col != nullptr, name);
      QTRY_VERIFY2(col->width() > 300.0, name);
      QTRY_VERIFY2(qAbs(row->width() - col->width()) < 1.0, name);
      QTRY_VERIFY2(qAbs((ctrl->x() + ctrl->width()) - row->width()) < 1.0,
                   name);
    };
    verifyRightAlignedInCol(outCombo, "gamescopeOutputResCombo");
    verifyRightAlignedInCol(adaptiveToggle, "gamescopeAdaptiveSyncToggle");

    QTRY_COMPARE(win.activeFocusItem(), presetBtn);

    // Navigate Down onto M3SegmentedButton (Window Mode) & switch to Borderless
    // via Right arrow
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QCOMPARE(win.activeFocusItem(), windowSeg);
    QTest::keyClick(&win, Qt::Key_Right);
    QCoreApplication::processEvents();
    QCOMPARE(gsDialog->property("windowMode").toString(),
             QStringLiteral("borderless"));

    // Navigate Down onto Output Resolution combo -> open popup -> Esc closes
    // popup NOT dialog
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QCOMPARE(win.activeFocusItem(), outCombo);

    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();
    auto *outPopup = outCombo->property("popup").value<QObject *>();
    QVERIFY(outPopup != nullptr);
    QTRY_COMPARE(outPopup->property("visible").toBool(), true);
    QTest::keyClick(&win, Qt::Key_Escape);
    QCoreApplication::processEvents();
    QTRY_COMPARE(outPopup->property("visible").toBool(), false);
    QCOMPARE(gsDialog->property("visible").toBool(), true);

    // Switching presets then selecting "Custom…" keeps custom resolution fields
    // synced (no stale text)
    outCombo->setProperty("selectedIndex", 3);
    QMetaObject::invokeMethod(outCombo, "selected", Q_ARG(int, 3));
    const int preset3W = gsDialog->property("outputWidth").toInt();
    QVERIFY(preset3W > 0);
    outCombo->setProperty("selectedIndex", 7);
    QMetaObject::invokeMethod(outCombo, "selected", Q_ARG(int, 7));
    QCoreApplication::processEvents();
    QCOMPARE(outWField->property("text").toString(), QString::number(preset3W));

    outCombo->setProperty("selectedIndex", 1);
    QMetaObject::invokeMethod(outCombo, "selected", Q_ARG(int, 1));
    const int preset1W = gsDialog->property("outputWidth").toInt();
    QVERIFY(preset1W > 0 && preset1W != preset3W);
    outCombo->setProperty("selectedIndex", 7);
    QMetaObject::invokeMethod(outCombo, "selected", Q_ARG(int, 7));
    QCoreApplication::processEvents();
    QCOMPARE(outWField->property("text").toString(), QString::number(preset1W));

    QMetaObject::invokeMethod(outCombo, "forceActiveFocus");
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QTRY_COMPARE(win.activeFocusItem(), outWField);

    // Apply 720p->1080p FSR preset, verify sharpness slider alignment,
    // Left/Right + Down exits slider, then Save immediately writes to database
    QVERIFY(QMetaObject::invokeMethod(
        gsDialog, "applyPreset",
        Q_ARG(QVariant, QVariant(QStringLiteral("fsr720")))));
    QCoreApplication::processEvents();
    verifyRightAlignedInCol(sharpSlider, "gamescopeSharpnessSlider");
    QObject *innerSlider = sharpSlider->property("slider").value<QObject *>();
    QVERIFY(innerSlider != nullptr);
    qobject_cast<QQuickItem *>(innerSlider)->forceActiveFocus();
    QCoreApplication::processEvents();
    QCOMPARE(gsDialog->property("fsrSharpness").toInt(), 3);
    QTest::keyClick(&win, Qt::Key_Right);
    QCoreApplication::processEvents();
    QCOMPARE(gsDialog->property("fsrSharpness").toInt(), 4);
    QTest::keyClick(&win, Qt::Key_Left);
    QCoreApplication::processEvents();
    QCOMPARE(gsDialog->property("fsrSharpness").toInt(), 3);
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QVERIFY(win.activeFocusItem() != innerSlider);

    saveBtn->forceActiveFocus();
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();

    QTRY_COMPARE(gsDialog->property("visible").toBool(), false);
    auto savedOpt = db.getGame(gameId);
    QVERIFY(savedOpt.has_value());
    QCOMPARE(savedOpt->gamescopeState, 1);
    QCOMPARE(savedOpt->gamescope.inheritGlobal, false);
    QCOMPARE(savedOpt->gamescope.outputWidth, 1920);
    QCOMPARE(savedOpt->gamescope.outputHeight, 1080);
    QCOMPARE(savedOpt->gamescope.internalWidth, 1280);
    QCOMPARE(savedOpt->gamescope.internalHeight, 720);
    QCOMPARE(savedOpt->gamescope.filter, QStringLiteral("fsr"));
    QCOMPARE(savedOpt->gamescope.fsrSharpness, 3);

    // Re-open dialog and verify gamepad Y button saves and closes via
    // searchActionRequested
    gsCustomizeBtn->forceActiveFocus();
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();
    QTRY_COMPARE(gsDialog->property("opened").toBool(), true);
    gsDialog->setProperty("hdrEnabled", true);
    QCoreApplication::processEvents();
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_Y);
    QCoreApplication::processEvents();
    QTRY_COMPARE(gsDialog->property("visible").toBool(), false);
    savedOpt = db.getGame(gameId);
    QVERIFY(savedOpt.has_value());
    QCOMPARE(savedOpt->gamescope.hdrEnabled, true);
  }

  void testM3FontsSymbolsAndComponents() {
    for (const char *resPath : {":/tsuki_app/fonts/Rubik-Regular.ttf",
                                ":/tsuki_app/fonts/Rubik-Medium.ttf",
                                ":/tsuki_app/fonts/Rubik-SemiBold.ttf",
                                ":/tsuki_app/fonts/Rubik-Bold.ttf"}) {
      QVERIFY2(QFile::exists(QString::fromLatin1(resPath)), resPath);
    }
    QVERIFY(!QFile::exists(
        QStringLiteral(":/tsuki_app/fonts/MaterialSymbolsRounded.ttf")));
    QVERIFY(!QFile::exists(
        QStringLiteral(":/tsuki_app/fonts/JetBrainsMonoNerdFont-Regular.ttf")));

    AppSettings::registerApplicationFonts();
    QCOMPARE(QGuiApplication::font().family(), QStringLiteral("Rubik"));

    const QStringList families = QFontDatabase::families();
    QVERIFY2(families.contains(QStringLiteral("Rubik")),
             "Bundled Rubik font family must be registered");
    QVERIFY2(
        families.contains(QStringLiteral("JetBrains Mono NF")) ||
            !QFont::substitutes(QStringLiteral("JetBrains Mono NF")).isEmpty(),
        "JetBrains Mono NF family or fallback substitution must be registered");
    if (families.contains(QStringLiteral("JetBrains Mono NF")) ||
        families.contains(QStringLiteral("JetBrainsMono Nerd Font")) ||
        families.contains(QStringLiteral("JetBrainsMono NF"))) {
      QFontInfo jbInfo(QFont(QStringLiteral("JetBrains Mono NF")));
      QVERIFY2(jbInfo.family().contains(QStringLiteral("JetBrains"),
                                        Qt::CaseInsensitive),
               qPrintable(QStringLiteral("Resolved JetBrains font: ") +
                          jbInfo.family()));
    }

    AppSettings settings;
    settings.setAccentColor(QColor(QStringLiteral("#d71920")));
    settings.setThemeMode(0); // Dark mode
    QVERIFY(settings.isEffectiveDark());
    QVERIFY(settings.secondaryContainer().saturation() > 0);
    QVERIFY(settings.onSecondaryContainer().lightness() >
            settings.secondaryContainer().lightness());

    settings.setThemeMode(1); // Light mode
    QVERIFY(!settings.isEffectiveDark());
    QVERIFY(settings.onSecondaryContainer().lightness() <
            settings.secondaryContainer().lightness());
    settings.setThemeMode(0);

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             QVariant());

    const QString componentsDir = QStringLiteral(TSUKI_SOURCE_DIR) +
                                  QStringLiteral("/src/qml/components/");

    // Verify YIcon resolves Material symbol names (+ filled state) to bundled
    // SVGs
    QQmlComponent yiconComp(
        &engine,
        QUrl::fromLocalFile(componentsDir + QStringLiteral("YIcon.qml")));
    QVERIFY2(yiconComp.errorString().isEmpty(),
             qPrintable(yiconComp.errorString()));
    std::unique_ptr<QObject> yicon(yiconComp.create());
    QVERIFY(yicon != nullptr);

    auto findYIconImage = [&yicon]() -> QQuickItem * {
      for (QObject *child : yicon->children()) {
        if (child->inherits("QQuickImage")) {
          return qobject_cast<QQuickItem *>(child);
        }
      }
      return nullptr;
    };
    for (QObject *child : yicon->children()) {
      QVERIFY2(!child->inherits("QQuickText"),
               "YIcon must render SVG images instead of Material Symbols text");
    }

    QQuickItem *rawImg = findYIconImage();
    QVERIFY(rawImg != nullptr);

    yicon->setProperty("symbol", QStringLiteral("play_arrow"));
    yicon->setProperty("filled", false);
    QCoreApplication::processEvents();
    QCOMPARE(rawImg->property("source").toUrl().toString(),
             QStringLiteral("qrc:/tsuki_app/icons/actions/play_arrow.svg"));

    yicon->setProperty("filled", true);
    QCoreApplication::processEvents();
    QCOMPARE(rawImg->property("source").toUrl().toString(),
             QStringLiteral("qrc:/tsuki_app/icons/actions/play.svg"));

    // Verify every symbol used across QML resolves to an existing QRC SVG
    for (const char *sym : {"add",
                            "arrow_back",
                            "article",
                            "auto_awesome",
                            "build",
                            "check",
                            "close",
                            "colorize",
                            "delete",
                            "desktop_windows",
                            "download",
                            "folder_open",
                            "grid_view",
                            "info",
                            "keyboard_arrow_down",
                            "menu",
                            "menu_open",
                            "open_in_new",
                            "palette",
                            "person",
                            "play_arrow",
                            "refresh",
                            "shortcut",
                            "sort",
                            "speed",
                            "stop",
                            "terminal",
                            "tune"}) {
      for (bool filled : {false, true}) {
        yicon->setProperty("symbol", QString::fromLatin1(sym));
        yicon->setProperty("filled", filled);
        const QString resolved = yicon->property("resolvedSource").toString();
        QVERIFY2(resolved.startsWith(QStringLiteral("qrc:/tsuki_app/icons/")),
                 qPrintable(QString::fromLatin1(sym)));
        const QString qrcPath =
            QStringLiteral(":") + resolved.mid(QStringLiteral("qrc:").length());
        QVERIFY2(QFile::exists(qrcPath), qPrintable(qrcPath));
      }
    }

    // Verify M3Button, Toggle, StyledCombo, and M3TextField compile and apply
    // M3 tokens
    for (const QString &file :
         {QStringLiteral("M3Button.qml"), QStringLiteral("Toggle.qml"),
          QStringLiteral("StyledCombo.qml"),
          QStringLiteral("M3TextField.qml")}) {
      QQmlComponent comp(&engine, QUrl::fromLocalFile(componentsDir + file));
      QVERIFY2(comp.errorString().isEmpty(), qPrintable(comp.errorString()));
      std::unique_ptr<QObject> obj(comp.create());
      QVERIFY(obj != nullptr);
      if (file == QStringLiteral("StyledCombo.qml")) {
        QCOMPARE(obj->property("implicitHeight").toInt(), 40);
      } else if (file == QStringLiteral("Toggle.qml")) {
        QCOMPARE(obj->property("implicitWidth").toInt(), 52);
        QCOMPARE(obj->property("implicitHeight").toInt(), 32);
      } else if (file == QStringLiteral("M3Button.qml")) {
        obj->setProperty("iconSymbol", QStringLiteral("tune"));
        QCOMPARE(obj->property("iconSymbol").toString(),
                 QStringLiteral("tune"));
      }
    }
  }

  void testGameDetailPageDelayedCallbackLifecycleNoErrors() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath(QStringLiteral("detail_lifecycle.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    const QString nativeGameId = gm.addNativeGame(
        QStringLiteral("Celeste"), QStringLiteral("/usr/bin/true"));
    QVERIFY(!nativeGameId.isEmpty());

    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm);

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QStringList qmlErrors;
    QObject::connect(
        &engine, &QQmlEngine::warnings, &engine,
        [&qmlErrors](const QList<QQmlError> &warnings) {
          for (const QQmlError &w : warnings) {
            const QString msg = w.toString();
            if (msg.contains(QStringLiteral("ReferenceError")) ||
                msg.contains(QStringLiteral("TypeError")) ||
                msg.contains(QStringLiteral("syncActiveTabPill")) ||
                msg.contains(QStringLiteral("tabsBar"))) {
              qmlErrors.append(msg);
            }
          }
        });

    QQmlComponent detailComp(&engine, resolveQmlUrl(QStringLiteral(
                                          "src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.errors().isEmpty(),
             qPrintable(detailComp.errorString()));

    QQuickWindow win;
    win.resize(1280, 820);
    win.show();

    // 1. Opening GameDetailPage for a native game triggers tabList rebuild
    // immediately after child tab creation
    QScopedPointer<QObject> detailObj(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), nativeGameId}}));
    QVERIFY(detailObj != nullptr);
    auto *detailItem = qobject_cast<QQuickItem *>(detailObj.get());
    QVERIFY(detailItem != nullptr);
    detailItem->setParentItem(win.contentItem());
    detailItem->setSize(QSizeF(1280, 820));

    QCoreApplication::processEvents();
    QTest::qWait(30);
    QVERIFY2(qmlErrors.isEmpty(),
             qPrintable(qmlErrors.join(QLatin1Char('\n'))));

    bool checkedEnvTitleColor = false;
    for (QQuickItem *item : detailItem->findChildren<QQuickItem *>()) {
      if (item->property("text").toString() ==
          QStringLiteral("Environment Variables")) {
        QCOMPARE(item->property("color").value<QColor>(),
                 settings.accentColor());
        checkedEnvTitleColor = true;
        break;
      }
    }
    QVERIFY(checkedEnvTitleColor);

    // Destroy page while tab switch & immediate teardown occur (simulating fast
    // stack.pop())
    detailObj->setProperty("activeTab", 2);
    detailObj.reset();
    QCoreApplication::processEvents();
    QTest::qWait(30);
    QVERIFY2(qmlErrors.isEmpty(),
             qPrintable(qmlErrors.join(QLatin1Char('\n'))));

    // 2. Create and immediately destroy before event-loop flush
    std::unique_ptr<QObject> ephemeral(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), nativeGameId}}));
    QVERIFY(ephemeral != nullptr);
    ephemeral.reset();
    QCoreApplication::processEvents();
    QTest::qWait(30);
    QVERIFY2(qmlErrors.isEmpty(),
             qPrintable(qmlErrors.join(QLatin1Char('\n'))));
  }

  void testSettingsPageTabsDynamicPillsAndCrossTabSearch() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    QSettings rawSettings(QStringLiteral("Tsuki"),
                          QStringLiteral("TsukiLauncher"));
    const bool hadThemeMode =
        rawSettings.contains(QStringLiteral("appearance/themeMode"));
    const QVariant oldThemeMode =
        rawSettings.value(QStringLiteral("appearance/themeMode"));
    const bool hadCustomSb =
        rawSettings.contains(QStringLiteral("appearance/customSidebarColor"));
    const QVariant oldCustomSb =
        rawSettings.value(QStringLiteral("appearance/customSidebarColor"));
    const bool hadSyncSb =
        rawSettings.contains(QStringLiteral("appearance/syncSidebarColor"));
    const QVariant oldSyncSb =
        rawSettings.value(QStringLiteral("appearance/syncSidebarColor"));
    auto restoreTheme = qScopeGuard([&]() {
      if (hadThemeMode)
        rawSettings.setValue(QStringLiteral("appearance/themeMode"),
                             oldThemeMode);
      else
        rawSettings.remove(QStringLiteral("appearance/themeMode"));
      if (hadCustomSb)
        rawSettings.setValue(QStringLiteral("appearance/customSidebarColor"),
                             oldCustomSb);
      else
        rawSettings.remove(QStringLiteral("appearance/customSidebarColor"));
      if (hadSyncSb)
        rawSettings.setValue(QStringLiteral("appearance/syncSidebarColor"),
                             oldSyncSb);
      else
        rawSettings.remove(QStringLiteral("appearance/syncSidebarColor"));
    });
    rawSettings.remove(QStringLiteral("appearance/themeMode"));

    DatabaseManager db(tmpDir.filePath(QStringLiteral("settings_qml.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    // Default appearance mode must be System (2)
    QCOMPARE(settings.themeMode(), 2);

    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm);

    QVERIFY(!settings.configDirPath().isEmpty());
    QVERIFY(!settings.dataDirPath().isEmpty());
    QVERIFY(!settings.logsDirPath().isEmpty());

    QQuickWindow win;
    win.resize(1280, 820);
    win.show();
    QVERIFY(QTest::qWaitForWindowExposed(&win));

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QStringList relevantWarnings;
    QObject::connect(
        &engine, &QQmlEngine::warnings, &win,
        [&](const QList<QQmlError> &warnings) {
          for (const QQmlError &err : warnings) {
            const QString text = err.toString();
            if (text.contains(QStringLiteral("SettingsPage")) ||
                text.contains(QStringLiteral("SettingTile")) ||
                text.contains(QStringLiteral("SettingsSection")) ||
                text.contains(QStringLiteral("M3PillGroup")) ||
                text.contains(QStringLiteral("M3ToolTip")) ||
                text.contains(QStringLiteral("ThemePreviewCards")) ||
                text.contains(QStringLiteral("Binding loop")) ||
                text.contains(QStringLiteral("ReferenceError")) ||
                text.contains(QStringLiteral("TypeError")) ||
                text.contains(QStringLiteral("recursive rearrange")) ||
                text.contains(QStringLiteral("Detected anchors")) ||
                text.contains(QStringLiteral("Invalid property assignment"))) {
              relevantWarnings << text;
            }
          }
        });

    // 1. M3PillGroup component behavior
    QQmlComponent pillComp(&engine, resolveQmlUrl(QStringLiteral(
                                        "src/qml/components/M3PillGroup.qml")));
    QVERIFY2(pillComp.isReady(), qPrintable(pillComp.errorString()));
    QVariantList pillModel{
        QVariantMap{{QStringLiteral("label"), QStringLiteral("Off")},
                    {QStringLiteral("val"), 0}},
        QVariantMap{{QStringLiteral("label"), QStringLiteral("Hover")},
                    {QStringLiteral("val"), 1}},
        QVariantMap{{QStringLiteral("label"), QStringLiteral("Always")},
                    {QStringLiteral("val"), 2}},
    };
    std::unique_ptr<QObject> pillObj(pillComp.createWithInitialProperties(
        {{QStringLiteral("model"), pillModel},
         {QStringLiteral("selectedValue"), 0}}));
    QVERIFY(pillObj != nullptr);
    auto *pillItem = qobject_cast<QQuickItem *>(pillObj.get());
    QVERIFY(pillItem != nullptr);
    pillItem->setParentItem(win.contentItem());
    QCoreApplication::processEvents();
    QCOMPARE(pillObj->property("selectedIndex").toInt(), 0);
    auto verifyPillCornerSymmetry = [](QQuickItem *rootPill) {
      QList<QQuickItem *> stack{rootPill};
      int rectCount = 0;
      while (!stack.isEmpty()) {
        QQuickItem *cur = stack.takeLast();
        for (QQuickItem *ch : cur->childItems()) {
          stack.append(ch);
          if (ch->metaObject()->indexOfProperty("topLeftRadius") < 0)
            continue;
          ++rectCount;
          const qreal tl = ch->property("topLeftRadius").toReal();
          const qreal bl = ch->property("bottomLeftRadius").toReal();
          const qreal tr = ch->property("topRightRadius").toReal();
          const qreal br = ch->property("bottomRightRadius").toReal();
          QVERIFY2(
              qAbs(tl - bl) < 0.05 && qAbs(tr - br) < 0.05,
              qPrintable(QStringLiteral(
                             "Asymmetric pill corners: TL=%1 BL=%2 TR=%3 BR=%4")
                             .arg(tl)
                             .arg(bl)
                             .arg(tr)
                             .arg(br)));
        }
      }
      QVERIFY(rectCount >= 3);
    };
    QVERIFY(QMetaObject::invokeMethod(pillObj.get(), "adjustRight"));
    QTest::qWait(
        40); // Mid-transition: top and bottom corners must animate in lockstep
    verifyPillCornerSymmetry(pillItem);
    QCOMPARE(pillObj->property("selectedIndex").toInt(), 1);
    QCOMPARE(pillObj->property("selectedValue").toInt(), 1);
    QVERIFY(QMetaObject::invokeMethod(pillObj.get(), "adjustLeft"));
    QTest::qWait(40);
    verifyPillCornerSymmetry(pillItem);
    QTest::qWait(200);
    verifyPillCornerSymmetry(pillItem);
    QCOMPARE(pillObj->property("selectedIndex").toInt(), 0);
    pillObj.reset();

    // Verify wrapped M3PillGroup also keeps symmetric corner transitions
    std::unique_ptr<QObject> wrapPillObj(pillComp.createWithInitialProperties(
        {{QStringLiteral("model"), pillModel},
         {QStringLiteral("selectedValue"), 0},
         {QStringLiteral("wrap"), true},
         {QStringLiteral("width"), 220}}));
    QVERIFY(wrapPillObj != nullptr);
    auto *wrapPillItem = qobject_cast<QQuickItem *>(wrapPillObj.get());
    QVERIFY(wrapPillItem != nullptr);
    wrapPillItem->setParentItem(win.contentItem());
    QCoreApplication::processEvents();
    QVERIFY(QMetaObject::invokeMethod(wrapPillObj.get(), "adjustRight"));
    QTest::qWait(40);
    verifyPillCornerSymmetry(wrapPillItem);
    QTest::qWait(200);
    verifyPillCornerSymmetry(wrapPillItem);
    wrapPillObj.reset();

    // 2. ThemePreviewCards component behavior
    QQmlComponent cardsComp(&engine,
                            resolveQmlUrl(QStringLiteral(
                                "src/qml/components/ThemePreviewCards.qml")));
    QVERIFY2(cardsComp.isReady(), qPrintable(cardsComp.errorString()));
    std::unique_ptr<QObject> cardsObj(cardsComp.createWithInitialProperties(
        {{QStringLiteral("selectedMode"), 0}}));
    QVERIFY(cardsObj != nullptr);
    auto *cardsItem = qobject_cast<QQuickItem *>(cardsObj.get());
    QVERIFY(cardsItem != nullptr);
    cardsItem->setParentItem(win.contentItem());
    QCoreApplication::processEvents();
    QVERIFY(QMetaObject::invokeMethod(cardsObj.get(), "adjustRight"));
    QCoreApplication::processEvents();
    QCOMPARE(cardsObj->property("selectedMode").toInt(), 1);
    QVERIFY(QMetaObject::invokeMethod(cardsObj.get(), "adjustLeft"));
    QCoreApplication::processEvents();
    QCOMPARE(cardsObj->property("selectedMode").toInt(), 0);
    cardsObj.reset();

    // 3. SettingsSection, SettingTile & M3ToolTip standalone instantiation
    QQmlComponent sectionComp(
        &engine, resolveQmlUrl(
                     QStringLiteral("src/qml/components/SettingsSection.qml")));
    QVERIFY2(sectionComp.isReady(), qPrintable(sectionComp.errorString()));
    std::unique_ptr<QObject> sectionObj(sectionComp.createWithInitialProperties(
        {{QStringLiteral("sectionTitle"), QStringLiteral("Sample Section")},
         {QStringLiteral("infoTip"), QStringLiteral("Tooltip info")}}));
    QVERIFY(sectionObj != nullptr);
    qobject_cast<QQuickItem *>(sectionObj.get())
        ->setParentItem(win.contentItem());

    QQmlComponent tileComp(&engine, resolveQmlUrl(QStringLiteral(
                                        "src/qml/components/SettingTile.qml")));
    QVERIFY2(tileComp.isReady(), qPrintable(tileComp.errorString()));
    std::unique_ptr<QObject> tileObj(tileComp.createWithInitialProperties(
        {{QStringLiteral("label"), QStringLiteral("Sample Option")},
         {QStringLiteral("infoTip"), QStringLiteral("Helpful hint")},
         {QStringLiteral("badgeText"), QStringLiteral("NEW")}}));
    QVERIFY(tileObj != nullptr);
    auto *tileItem = qobject_cast<QQuickItem *>(tileObj.get());
    tileItem->setParentItem(win.contentItem());
    tileItem->setWidth(420);

    QQmlComponent tipComp(&engine, resolveQmlUrl(QStringLiteral(
                                       "src/qml/components/M3ToolTip.qml")));
    QVERIFY2(tipComp.isReady(), qPrintable(tipComp.errorString()));
    std::unique_ptr<QObject> tipObj(tipComp.createWithInitialProperties(
        {{QStringLiteral("text"), QStringLiteral("Clean M3 tooltip hint")},
         {QStringLiteral("visible"), true}}));
    QVERIFY(tipObj != nullptr);
    tipObj->setParent(tileItem);
    QCoreApplication::processEvents();
    auto *standaloneTitle = tileObj->findChild<QQuickItem *>(
        QStringLiteral("settingTileTitleLabel"));
    QVERIFY(standaloneTitle != nullptr);
    QTRY_VERIFY(standaloneTitle->width() > 0);
    QTRY_COMPARE(standaloneTitle->property("truncated").toBool(), false);
    tipObj.reset();
    tileObj.reset();
    sectionObj.reset();

    // 4. SettingsPage full 6-tab layout, rail sidebar color sync, no truncated
    // labels, keyboard cycling, and cross-tab search
#if !TSUKI_VERSION_OVERRIDDEN
    QCOMPARE(QStringLiteral(TSUKI_VERSION),
             QStringLiteral(TSUKI_PROJECT_VERSION));
#endif
    const QString prevAppVersion = QCoreApplication::applicationVersion();
    const auto restoreAppVersion = qScopeGuard(
        [&]() { QCoreApplication::setApplicationVersion(prevAppVersion); });
    QCoreApplication::setApplicationVersion(QStringLiteral(TSUKI_VERSION));

    QQmlComponent settingsComp(&engine, resolveQmlUrl(QStringLiteral(
                                            "src/qml/pages/SettingsPage.qml")));
    QVERIFY2(settingsComp.isReady(), qPrintable(settingsComp.errorString()));
    std::unique_ptr<QObject> settingsObj(settingsComp.create());
    QVERIFY(settingsObj != nullptr);
    auto *settingsItem = qobject_cast<QQuickItem *>(settingsObj.get());
    QVERIFY(settingsItem != nullptr);
    settingsItem->setParentItem(win.contentItem());
    settingsItem->setSize(QSizeF(win.width(), win.height()));
    QCoreApplication::processEvents();
    QTest::qWait(30);

    const QVariantList tabMeta = settingsObj->property("tabMeta").toList();
    QCOMPARE(tabMeta.size(), 6);
    QCOMPARE(settingsObj->property("activeTab").toInt(), 0);
    QCOMPARE(settingsObj->property("railCollapsed").toBool(), false);
    settingsObj->setProperty("railCollapsed", true);
    QCOMPARE(settingsObj->property("railCollapsed").toBool(), true);
    settingsObj->setProperty("railCollapsed", false);

    // Settings sidebar adapts dynamically to AppSettings::sidebarColor
    auto *navRailItem =
        settingsObj->findChild<QQuickItem *>(QStringLiteral("settingsNavRail"));
    QVERIFY(navRailItem != nullptr);
    settings.setSyncSidebarColor(false);
    settings.setCustomSidebarColor(QStringLiteral("#1e232d"));
    QTRY_COMPARE(navRailItem->property("color").value<QColor>(),
                 QColor(QStringLiteral("#1e232d")));
    settings.setSyncSidebarColor(true);
    QTRY_COMPARE(navRailItem->property("color").value<QColor>(),
                 settings.bgColor());
    settings.setSyncSidebarColor(false);
    settings.resetSidebarColor();

    // Visit every tab at desktop (1280x820) and minimum window width (960x540):
    // verify zero layout/anchor loops AND zero truncated setting tile labels
    for (const QSizeF &sz : {QSizeF(1280, 820), QSizeF(960, 540)}) {
      settingsItem->setSize(sz);
      for (int t = 0; t < 6; ++t) {
        QVERIFY(QMetaObject::invokeMethod(settingsObj.get(), "selectTab",
                                          Q_ARG(QVariant, QVariant(t))));
        QCoreApplication::processEvents();
        QCOMPARE(settingsObj->property("activeTab").toInt(), t);
        const auto titleLabels = settingsObj->findChildren<QQuickItem *>(
            QStringLiteral("settingTileTitleLabel"));
        for (QQuickItem *lbl : titleLabels) {
          if (lbl->isVisible()) {
            // Wait for Qt Quick layout polish after tab visibility transitions
            QTRY_VERIFY2(
                lbl->width() > 0 && !lbl->property("truncated").toBool(),
                qPrintable(
                    QStringLiteral("Truncated label on tab %1 (%2x%3): %4")
                        .arg(t)
                        .arg(sz.width())
                        .arg(sz.height())
                        .arg(lbl->property("text").toString())));
          }
        }
      }
    }
    settingsItem->setSize(QSizeF(win.width(), win.height()));
    QVERIFY(QMetaObject::invokeMethod(settingsObj.get(), "selectTab",
                                      Q_ARG(QVariant, QVariant(0))));
    QCoreApplication::processEvents();

    // Verify About tab version, author & GitHub/Repository controls
    auto *aboutVerLbl = settingsObj->findChild<QQuickItem *>(
        QStringLiteral("aboutVersionLabel"));
    QVERIFY(aboutVerLbl != nullptr);
    QCOMPARE(aboutVerLbl->property("text").toString(),
             QStringLiteral("v") + QStringLiteral(TSUKI_VERSION));
    QVERIFY(settingsObj->findChild<QQuickItem *>(
                QStringLiteral("aboutAuthorRow")) != nullptr);
    auto *ghAccBtn = settingsObj->findChild<QQuickItem *>(
        QStringLiteral("githubAccountBtn"));
    auto *ghRepoBtn =
        settingsObj->findChild<QQuickItem *>(QStringLiteral("githubRepoBtn"));
    QVERIFY(ghAccBtn != nullptr);
    QVERIFY(ghRepoBtn != nullptr);
    QCOMPARE(ghAccBtn->property("text").toString(),
             QStringLiteral("@muzammilshafique"));
    QCOMPARE(ghRepoBtn->property("text").toString(),
             QStringLiteral("Repository"));

    // Bracket keys [ / ] cycle tabs smoothly (including wrap-around 0 -> 5)
    settingsItem->forceActiveFocus();
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_BracketRight);
    QCoreApplication::processEvents();
    QCOMPARE(settingsObj->property("activeTab").toInt(), 1);
    QTest::keyClick(&win, Qt::Key_BracketLeft);
    QCoreApplication::processEvents();
    QCOMPARE(settingsObj->property("activeTab").toInt(), 0);
    QTest::keyClick(&win, Qt::Key_BracketLeft);
    QCoreApplication::processEvents();
    QCOMPARE(settingsObj->property("activeTab").toInt(), 5);
    QVERIFY(QMetaObject::invokeMethod(settingsObj.get(), "selectTab",
                                      Q_ARG(QVariant, QVariant(0))));
    QCoreApplication::processEvents();

    // Verify catalog indexing across all 6 tabs and preserved objectNames
    QVERIFY(QMetaObject::invokeMethod(settingsObj.get(), "buildIndex"));
    const QVariantList catalog =
        settingsObj->property("settingsCatalog").toList();
    QVERIFY(catalog.size() >= 15);
    QSet<int> indexedTabs;
    for (const QVariant &entryVar : catalog) {
      indexedTabs.insert(
          entryVar.toMap().value(QStringLiteral("tabIdx")).toInt());
    }
    QCOMPARE(indexedTabs.size(), 6);

    QVERIFY(settingsObj->findChild<QQuickItem *>(
                QStringLiteral("gamescopeDefaultRow")) != nullptr);
    QVERIFY(settingsObj->findChild<QQuickItem *>(
                QStringLiteral("gamescopeDefaultsConfigRow")) != nullptr);

    // Cross-tab search jump from tab 0 (Style) -> tab 2 (Performance)
    QVERIFY(QMetaObject::invokeMethod(
        settingsObj.get(), "updateSearchResults",
        Q_ARG(QVariant, QVariant(QStringLiteral("gamescope")))));
    QCoreApplication::processEvents();
    const QVariantList results =
        settingsObj->property("searchResults").toList();
    QVERIFY(!results.isEmpty());
    QVariantMap gsMatch;
    for (const QVariant &rVar : results) {
      const QVariantMap rMap = rVar.toMap();
      if (rMap.value(QStringLiteral("tabIdx")).toInt() == 2) {
        gsMatch = rMap;
        break;
      }
    }
    QVERIFY(!gsMatch.isEmpty());
    QObject *targetRowObj =
        gsMatch.value(QStringLiteral("item")).value<QObject *>();
    QVERIFY(targetRowObj != nullptr);
    QVERIFY(QMetaObject::invokeMethod(
        settingsObj.get(), "scrollToSetting",
        Q_ARG(QVariant, QVariant::fromValue(targetRowObj)),
        Q_ARG(QVariant, QVariant(2))));
    QCoreApplication::processEvents();
    QTest::qWait(30);
    QCOMPARE(settingsObj->property("activeTab").toInt(), 2);

    // Clean teardown while jump timer/effects have settled
    settingsObj.reset();
    QCoreApplication::processEvents();
    QTest::qWait(30);

    // Ephemeral create + immediate destroy before event-loop flush
    std::unique_ptr<QObject> ephemeralSettings(settingsComp.create());
    QVERIFY(ephemeralSettings != nullptr);
    ephemeralSettings.reset();
    QCoreApplication::processEvents();
    QTest::qWait(30);

    QVERIFY2(relevantWarnings.isEmpty(),
             qPrintable(relevantWarnings.join(QLatin1Char('\n'))));
  }

  void testFabMenuAndCompactAddGameDialog() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    QSettings rawSettings(QStringLiteral("Tsuki"),
                          QStringLiteral("TsukiLauncher"));
    const bool hasThemeMode =
        rawSettings.contains(QStringLiteral("appearance/themeMode"));
    const QVariant oldThemeMode =
        rawSettings.value(QStringLiteral("appearance/themeMode"));
    const auto restoreSettings = qScopeGuard([&]() {
      if (hasThemeMode)
        rawSettings.setValue(QStringLiteral("appearance/themeMode"),
                             oldThemeMode);
      else
        rawSettings.remove(QStringLiteral("appearance/themeMode"));
    });

    DatabaseManager db(tmpDir.filePath(QStringLiteral("fab_add_dialog.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm);

    QQuickWindow win;
    win.resize(1280, 820);
    win.show();
    QVERIFY(QTest::qWaitForWindowExposed(&win));

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QStringList relevantWarnings;
    QObject::connect(
        &engine, &QQmlEngine::warnings, &win,
        [&](const QList<QQmlError> &warnings) {
          for (const QQmlError &err : warnings) {
            const QString text = err.toString();
            if (text.contains(QStringLiteral("M3FabMenu")) ||
                text.contains(QStringLiteral("AddGameDialog")) ||
                text.contains(QStringLiteral("TopBar")) ||
                text.contains(QStringLiteral("Binding loop")) ||
                text.contains(QStringLiteral("ReferenceError")) ||
                text.contains(QStringLiteral("TypeError")) ||
                text.contains(QStringLiteral("recursive rearrange")) ||
                text.contains(QStringLiteral("Detected anchors"))) {
              relevantWarnings << text;
            }
          }
        });

    // 1. M3FabMenu open/close and platform selection
    QQmlComponent fabComp(&engine, resolveQmlUrl(QStringLiteral(
                                       "src/qml/components/M3FabMenu.qml")));
    QVERIFY2(fabComp.isReady(), qPrintable(fabComp.errorString()));
    std::unique_ptr<QObject> fabObj(fabComp.create());
    QVERIFY(fabObj != nullptr);
    auto *fabItem = qobject_cast<QQuickItem *>(fabObj.get());
    QVERIFY(fabItem != nullptr);
    fabItem->setParentItem(win.contentItem());
    fabItem->setPosition(QPointF(1100, 24));
    QCoreApplication::processEvents();

    QSignalSpy fabSpy(fabObj.get(), SIGNAL(itemSelected(QString)));
    QCOMPARE(fabObj->property("isMenuOpen").toBool(), false);
    QCOMPARE(fabObj->property("isExpanded").toBool(), false);
    QTRY_VERIFY(qAbs(fabItem->implicitWidth() - 40.0) <= 0.5);
    QVERIFY(fabObj->property("expandedWidth").toReal() > 60.0);

    QVERIFY(QMetaObject::invokeMethod(fabObj.get(), "openMenu"));
    QTRY_COMPARE(fabObj->property("isMenuOpen").toBool(), true);
    QCOMPARE(fabObj->property("isExpanded").toBool(), true);
    QTRY_VERIFY(fabItem->implicitWidth() > 60.0);
    QVERIFY(QMetaObject::invokeMethod(fabObj.get(), "activateItem",
                                      Q_ARG(QVariant, QVariant(0))));
    QTRY_COMPARE(fabSpy.count(), 1);
    QCOMPARE(fabSpy.at(0).at(0).toString(), QStringLiteral("windows"));
    QTRY_COMPARE(fabObj->property("isMenuOpen").toBool(), false);
    QCOMPARE(fabObj->property("isExpanded").toBool(), false);
    QTRY_VERIFY(qAbs(fabItem->implicitWidth() - 40.0) <= 0.5);

    QVERIFY(QMetaObject::invokeMethod(fabObj.get(), "openMenu"));
    QTRY_COMPARE(fabObj->property("isMenuOpen").toBool(), true);
    QVERIFY(QMetaObject::invokeMethod(fabObj.get(), "activateItem",
                                      Q_ARG(QVariant, QVariant(1))));
    QTRY_COMPARE(fabSpy.count(), 2);
    QCOMPARE(fabSpy.at(1).at(0).toString(), QStringLiteral("linux"));
    QTRY_COMPARE(fabObj->property("isMenuOpen").toBool(), false);
    QTRY_VERIFY(qAbs(fabItem->implicitWidth() - 40.0) <= 0.5);
    fabObj.reset();

    // Background focus sentinel to verify AddGameDialog never leaks directional
    // keys
    QQmlComponent bgSentinelComp(&engine);
    bgSentinelComp.setData("import QtQuick\n"
                           "FocusScope {\n"
                           "    width: 200; height: 200\n"
                           "    property int leakedKeys: 0\n"
                           "    Keys.onPressed: (event) => { leakedKeys++; "
                           "event.accepted = true }\n"
                           "}\n",
                           QUrl());
    QVERIFY2(bgSentinelComp.isReady(),
             qPrintable(bgSentinelComp.errorString()));
    std::unique_ptr<QObject> bgSentinelObj(bgSentinelComp.create());
    QVERIFY(bgSentinelObj != nullptr);
    auto *bgSentinel = qobject_cast<QQuickItem *>(bgSentinelObj.get());
    QVERIFY(bgSentinel != nullptr);
    bgSentinel->setParentItem(win.contentItem());
    bgSentinel->forceActiveFocus();
    QCoreApplication::processEvents();
    QCOMPARE(bgSentinel->hasActiveFocus(), true);

    // 2. AddGameDialog compact Settings aesthetic, no internal platform
    // switcher, adaptive height
    QQmlComponent dialogComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/components/AddGameDialog.qml")));
    QVERIFY2(dialogComp.isReady(), qPrintable(dialogComp.errorString()));
    std::unique_ptr<QObject> dialogObj(dialogComp.create());
    QVERIFY(dialogObj != nullptr);
    dialogObj->setProperty("parent", QVariant::fromValue(win.contentItem()));
    QCoreApplication::processEvents();

    QVERIFY(QMetaObject::invokeMethod(
        dialogObj.get(), "resetAndOpen",
        Q_ARG(QVariant, QVariant(QStringLiteral("windows")))));
    auto *contentItem =
        dialogObj->property("contentItem").value<QQuickItem *>();
    QVERIFY(contentItem != nullptr);
    auto *winExeField =
        contentItem->findChild<QQuickItem *>(QStringLiteral("addGameExeField"));
    auto *winBrowseBtn = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameBrowseExeBtn"));
    auto *winTitleField = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameTitleField"));
    auto *winWorkDirField = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameWorkDirField"));
    auto *winCancelBtn = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameCancelBtn"));
    QVERIFY(winExeField && winBrowseBtn && winTitleField && winWorkDirField &&
            winCancelBtn);

    // Focus must enter AddGameDialog immediately and stay inside after the
    // enter transition finishes
    QTRY_COMPARE(winExeField->hasActiveFocus(), true);
    QTest::qWait(220);
    QCOMPARE(dialogObj->property("opened").toBool(), true);
    QCOMPARE(winExeField->hasActiveFocus(), true);
    QCOMPARE(dialogObj->property("platform").toString(),
             QStringLiteral("windows"));

    // Keyboard/gamepad navigation inside Windows dialog without leaking keys to
    // background
    QTest::keyClick(&win, Qt::Key_Up);
    QCoreApplication::processEvents();
    QCOMPARE(winExeField->hasActiveFocus(), true);

    QTest::keyClick(&win, Qt::Key_Right);
    QCoreApplication::processEvents();
    QCOMPARE(winBrowseBtn->hasActiveFocus(), true);

    QTest::keyClick(&win, Qt::Key_Left);
    QCoreApplication::processEvents();
    QCOMPARE(winExeField->hasActiveFocus(), true);

    // Enter edit mode via Return on M3TextField, then Down exits edit mode and
    // moves to Title
    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();
    QCOMPARE(winExeField->property("isEditing").toBool(), true);
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QCOMPARE(winTitleField->hasActiveFocus(), true);

    for (int i = 0; i < 5; ++i) {
      QTest::keyClick(&win, Qt::Key_Down);
      QCoreApplication::processEvents();
    }
    QCOMPARE(winWorkDirField->hasActiveFocus(), true);
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QCOMPARE(winCancelBtn->hasActiveFocus(), true);
    QCOMPARE(bgSentinel->property("leakedKeys").toInt(), 0);

    // Platform selector must not exist inside the dialog (chosen exclusively
    // from FAB menu)
    QVERIFY(contentItem->findChild<QQuickItem *>(
                QStringLiteral("platformSeg")) == nullptr);

    auto *headerLbl = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameHeaderTitle"));
    auto *winCard = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameWindowsCard"));
    QVERIFY(headerLbl != nullptr);
    QVERIFY(winCard != nullptr);
    QCOMPARE(headerLbl->property("text").toString(),
             QStringLiteral("Add Windows Game"));
    QCOMPARE(winCard->isVisible(), true);
    const qreal windowsDialogHeight = dialogObj->property("height").toReal();

    QTest::keyClick(&win, Qt::Key_Escape);
    QTRY_COMPARE(dialogObj->property("visible").toBool(), false);

    QVERIFY(QMetaObject::invokeMethod(
        dialogObj.get(), "resetAndOpen",
        Q_ARG(QVariant, QVariant(QStringLiteral("linux")))));
    QTRY_COMPARE(dialogObj->property("opened").toBool(), true);
    QCOMPARE(dialogObj->property("platform").toString(),
             QStringLiteral("linux"));
    QCOMPARE(headerLbl->property("text").toString(),
             QStringLiteral("Add Linux Game"));
    QCOMPARE(winCard->isVisible(), false);
    const qreal linuxDialogHeight = dialogObj->property("height").toReal();
    QVERIFY2(linuxDialogHeight < windowsDialogHeight,
             qPrintable(
                 QStringLiteral(
                     "Expected Linux dialog height (%1) < Windows height (%2)")
                     .arg(linuxDialogHeight)
                     .arg(windowsDialogHeight)));

    // Submitting Linux native game creates native game entry and closes popup
    auto *exeField =
        contentItem->findChild<QQuickItem *>(QStringLiteral("addGameExeField"));
    auto *titleField = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameTitleField"));
    auto *submitBtn = contentItem->findChild<QQuickItem *>(
        QStringLiteral("addGameSubmitBtn"));
    QVERIFY(exeField != nullptr && titleField != nullptr &&
            submitBtn != nullptr);
    exeField->setProperty(
        "text", QStringLiteral("/opt/games/hollow_knight/hollow.x86_64"));
    titleField->setProperty("text", QStringLiteral("Hollow Knight Native"));
    QCoreApplication::processEvents();
    QCOMPARE(submitBtn->isEnabled(), true);
    QVERIFY(QMetaObject::invokeMethod(submitBtn, "clicked"));
    QTRY_COMPARE(dialogObj->property("visible").toBool(), false);
    const auto addedGames = db.getAllGames();
    QCOMPARE(addedGames.size(), 1);
    QCOMPARE(addedGames.first().platform, QStringLiteral("linux"));
    QCOMPARE(addedGames.first().title, QStringLiteral("Hollow Knight Native"));
    dialogObj.reset();
    bgSentinelObj.reset();

    // 3. TopBar top-right FAB integration
    QQmlComponent topBarComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/home/TopBar.qml")));
    QVERIFY2(topBarComp.isReady(), qPrintable(topBarComp.errorString()));
    std::unique_ptr<QObject> topBarObj(topBarComp.create());
    QVERIFY(topBarObj != nullptr);
    auto *topBarItem = qobject_cast<QQuickItem *>(topBarObj.get());
    QVERIFY(topBarItem != nullptr);
    topBarItem->setParentItem(win.contentItem());
    topBarItem->setSize(QSizeF(1060, 84));
    QCoreApplication::processEvents();

    auto *topFab =
        topBarObj->findChild<QQuickItem *>(QStringLiteral("topBarAddFabMenu"));
    QVERIFY(topFab != nullptr);
    QSignalSpy topAddSpy(topBarObj.get(), SIGNAL(addGameRequested(QString)));
    QVERIFY(QMetaObject::invokeMethod(topBarObj.get(), "openAddMenu"));
    QTRY_COMPARE(topBarObj->property("isAddMenuOpen").toBool(), true);
    QVERIFY(QMetaObject::invokeMethod(topFab, "activateItem",
                                      Q_ARG(QVariant, QVariant(1))));
    QTRY_COMPARE(topAddSpy.count(), 1);
    QCOMPARE(topAddSpy.at(0).at(0).toString(), QStringLiteral("linux"));
    QTRY_COMPARE(topBarObj->property("isAddMenuOpen").toBool(), false);

    topBarObj.reset();
    QCoreApplication::processEvents();
    QTest::qWait(30);

    QVERIFY2(relevantWarnings.isEmpty(),
             qPrintable(relevantWarnings.join(QLatin1Char('\n'))));
  }

  void testEpicManifestParserBinaryAndChunkDecompression() {
    auto writeU32 = [](QByteArray &buf, quint32 v) {
      char b[4];
      qToLittleEndian<quint32>(v, reinterpret_cast<uchar *>(b));
      buf.append(b, 4);
    };
    auto writeI32 = [](QByteArray &buf, qint32 v) {
      char b[4];
      qToLittleEndian<qint32>(v, reinterpret_cast<uchar *>(b));
      buf.append(b, 4);
    };
    auto writeU64 = [](QByteArray &buf, quint64 v) {
      char b[8];
      qToLittleEndian<quint64>(v, reinterpret_cast<uchar *>(b));
      buf.append(b, 8);
    };
    auto writeI64 = [](QByteArray &buf, qint64 v) {
      char b[8];
      qToLittleEndian<qint64>(v, reinterpret_cast<uchar *>(b));
      buf.append(b, 8);
    };
    auto writeFString = [&](QByteArray &buf, const QString &s) {
      if (s.isEmpty()) {
        writeI32(buf, 0);
        return;
      }
      QByteArray u8 = s.toUtf8();
      u8.append('\0');
      writeI32(buf, static_cast<qint32>(u8.size()));
      buf.append(u8);
    };

    const QByteArray chunkPayload("HELLO_TSUKI_EPIC");
    const QByteArray chunkSha1 =
        QCryptographicHash::hash(chunkPayload, QCryptographicHash::Sha1);

    QByteArray fguidBytes(16, '\0');
    qToLittleEndian<quint32>(0x11223344u,
                             reinterpret_cast<uchar *>(fguidBytes.data()));
    qToLittleEndian<quint32>(0x55667788u,
                             reinterpret_cast<uchar *>(fguidBytes.data() + 4));
    qToLittleEndian<quint32>(0x99AABBCBu,
                             reinterpret_cast<uchar *>(fguidBytes.data() + 8));
    qToLittleEndian<quint32>(0xDDEEFF00u,
                             reinterpret_cast<uchar *>(fguidBytes.data() + 12));

    // Build uncompressed manifest body
    QByteArray body;

    // 1. FManifestMeta
    QByteArray metaFields;
    writeI32(metaFields, 18);                 // featureLevel -> ChunksV4
    metaFields.append(char(0));               // isFileData
    writeU32(metaFields, 99u);                // appId
    writeFString(metaFields, "Celeste");      // appName
    writeFString(metaFields, "1.4.0.0");      // buildVersion
    writeFString(metaFields, "Celeste.exe");  // launchExe
    writeFString(metaFields, "-windowed");    // launchCommand
    writeU32(metaFields, 0u);                 // prereqIds count
    writeFString(metaFields, "");             // prereqName
    writeFString(metaFields, "");             // prereqPath
    writeFString(metaFields, "");             // prereqArgs

    QByteArray metaSection;
    writeU32(metaSection, static_cast<quint32>(5 + metaFields.size()));
    metaSection.append(char(0)); // dataVersion
    metaSection.append(metaFields);
    body.append(metaSection);

    // 2. FChunkDataList (1 chunk)
    QByteArray chunkFields;
    writeI32(chunkFields, 1); // count
    chunkFields.append(fguidBytes);
    writeU64(chunkFields, 0x0102030405060708ULL); // rolling hash
    chunkFields.append(chunkSha1);                // 20-byte SHA1
    chunkFields.append(char(3));                  // groupNum = 03
    writeU32(chunkFields, 16u);                   // windowSize
    writeI64(chunkFields, 64);                    // fileSize

    QByteArray chunkSection;
    writeU32(chunkSection, static_cast<quint32>(5 + chunkFields.size()));
    chunkSection.append(char(0)); // dataVersion
    chunkSection.append(chunkFields);
    body.append(chunkSection);

    // 3. FFileManifestList (1 executable file)
    QByteArray fileFields;
    writeI32(fileFields, 1);                 // fileCount
    writeFString(fileFields, "Celeste.exe"); // filename
    writeFString(fileFields, "");            // symlinkTarget
    fileFields.append(chunkSha1);            // file sha1
    fileFields.append(char(0x04));           // metaFlags (executable)
    writeU32(fileFields, 0u);                // installTags count
    writeU32(fileFields, 1u);                // chunkParts count
    writeU32(fileFields, 28u);               // partSize
    fileFields.append(fguidBytes);           // chunkGuid
    writeU32(fileFields, 0u);                // offset
    writeU32(fileFields, static_cast<quint32>(chunkPayload.size())); // size

    QByteArray fileSection;
    writeU32(fileSection, static_cast<quint32>(5 + fileFields.size()));
    fileSection.append(char(0)); // dataVersion
    fileSection.append(fileFields);
    body.append(fileSection);

    // Compress body with zlib
    uLongf compBound = compressBound(static_cast<uLong>(body.size()));
    QByteArray compBody(static_cast<int>(compBound), '\0');
    QCOMPARE(compress2(reinterpret_cast<Bytef *>(compBody.data()), &compBound,
                       reinterpret_cast<const Bytef *>(body.constData()),
                       static_cast<uLong>(body.size()), Z_DEFAULT_COMPRESSION),
             Z_OK);
    compBody.resize(static_cast<int>(compBound));

    const QByteArray bodySha1 =
        QCryptographicHash::hash(body, QCryptographicHash::Sha1);

    // Header (41 bytes)
    QByteArray rawManifest;
    writeU32(rawManifest, 0x44BEC00Cu);
    writeU32(rawManifest, 41u);
    writeU32(rawManifest, static_cast<quint32>(body.size()));
    writeU32(rawManifest, static_cast<quint32>(compBody.size()));
    rawManifest.append(bodySha1);
    rawManifest.append(char(0x01)); // zlib compressed
    writeU32(rawManifest, 18u);
    rawManifest.append(compBody);

    EpicManifest parsed;
    QString parseErr;
    QVERIFY2(EpicManifestParser::parse(rawManifest, parsed, &parseErr),
             qPrintable(parseErr));
    QVERIFY(parsed.isValid);
    QCOMPARE(parsed.appName, QStringLiteral("Celeste"));
    QCOMPARE(parsed.buildVersion, QStringLiteral("1.4.0.0"));
    QCOMPARE(parsed.launchExe, QStringLiteral("Celeste.exe"));
    QCOMPARE(parsed.launchCommand, QStringLiteral("-windowed"));
    QCOMPARE(parsed.chunksSubdir(), QStringLiteral("ChunksV4"));
    QCOMPARE(parsed.chunks.size(), 1);
    QCOMPARE(parsed.files.size(), 1);
    QVERIFY(parsed.files.first().isExecutable());
    QCOMPARE(parsed.totalInstallSize, static_cast<qint64>(chunkPayload.size()));
    QCOMPARE(parsed.totalDownloadSize, static_cast<qint64>(64));
    QCOMPARE(parsed.chunks.first().relativeChunkPath(parsed.chunksSubdir()),
             QStringLiteral("ChunksV4/03/0102030405060708_112233445566778899AABBCBDDEEFF00.chunk"));

    // Build synthetic 0xB1FE3AA2 chunk and decompress + verify SHA-1
    uLongf cChunkBound = compressBound(static_cast<uLong>(chunkPayload.size()));
    QByteArray compChunk(static_cast<int>(cChunkBound), '\0');
    QCOMPARE(compress2(reinterpret_cast<Bytef *>(compChunk.data()), &cChunkBound,
                       reinterpret_cast<const Bytef *>(chunkPayload.constData()),
                       static_cast<uLong>(chunkPayload.size()), Z_DEFAULT_COMPRESSION),
             Z_OK);
    compChunk.resize(static_cast<int>(cChunkBound));

    QByteArray rawChunk;
    writeU32(rawChunk, 0xB1FE3AA2u);
    writeU32(rawChunk, 2u);   // header version 2
    writeU32(rawChunk, 61u);  // header size (41 + 20)
    writeU32(rawChunk, static_cast<quint32>(compChunk.size()));
    rawChunk.append(fguidBytes);
    writeU64(rawChunk, 0x0102030405060708ULL);
    rawChunk.append(char(0x01)); // zlib compressed
    rawChunk.append(chunkSha1);
    rawChunk.append(compChunk);

    QByteArray outChunk;
    QString chunkErr;
    QVERIFY2(EpicManifestParser::decompressChunk(rawChunk, chunkSha1, outChunk,
                                                 &chunkErr),
             qPrintable(chunkErr));
    QCOMPARE(outChunk, chunkPayload);

    // Tampered SHA-1 must fail verification
    QByteArray badSha = chunkSha1;
    badSha[0] = static_cast<char>(badSha[0] ^ 0xFF);
    QVERIFY(!EpicManifestParser::decompressChunk(rawChunk, badSha, outChunk,
                                                 &chunkErr));

    // Also test JSON fallback manifest parsing
    const QByteArray jsonManifest =
        "{\"ManifestFileVersion\":\"18\","
        "\"AppNameString\":\"AlanWake\","
        "\"BuildVersionString\":\"1.0.1\","
        "\"LaunchExeString\":\"AlanWake.exe\","
        "\"LaunchCommand\":\"-nointro\","
        "\"FileManifestList\":[{\"Filename\":\"AlanWake.exe\","
        "\"bIsUnixExecutable\":true,"
        "\"FileChunkParts\":[{\"Guid\":\"AABBCCDD\",\"Offset\":\"0\",\"Size\":\"1024\"}]}],"
        "\"ChunkHashList\":{\"AABBCCDD\":\"00000000000000FF\"},"
        "\"DataGroupList\":{\"AABBCCDD\":\"02\"},"
        "\"ChunkFilesizeList\":{\"AABBCCDD\":\"512\"}}";
    EpicManifest jsonParsed;
    QVERIFY2(EpicManifestParser::parse(jsonManifest, jsonParsed, &parseErr),
             qPrintable(parseErr));
    QCOMPARE(jsonParsed.appName, QStringLiteral("AlanWake"));
    QCOMPARE(jsonParsed.launchExe, QStringLiteral("AlanWake.exe"));
    QCOMPARE(jsonParsed.totalInstallSize, static_cast<qint64>(1024));
    QCOMPARE(jsonParsed.totalDownloadSize, static_cast<qint64>(512));
  }

  void testEpicAuthCodeDatabaseAndGameLifecycle() {
    // 1. Auth code extraction variants
    QCOMPARE(EpicService::extractAuthCode(QStringLiteral("abc123def456")),
             QStringLiteral("abc123def456"));
    QCOMPARE(
        EpicService::extractAuthCode(QStringLiteral(
            "{\"redirectUrl\":\"https://localhost/cb?code=fromurl\",\"authorizationCode\":\"jsoncode789\",\"sid\":null}")),
        QStringLiteral("jsoncode789"));
    QCOMPARE(
        EpicService::extractAuthCode(QStringLiteral(
            "https://www.epicgames.com/id/api/redirect?code=urlcode456")),
        QStringLiteral("urlcode456"));
    QCOMPARE(EpicService::extractAuthCode(QStringLiteral("  \"quoted99\"  ")),
             QStringLiteral("quoted99"));

    // 2. Database + GameManager + EpicService + LaunchPipeline integration
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());
    DatabaseManager db(tmpDir.filePath(QStringLiteral("epic_test.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    EpicService epicSvc(&db, &settings, &runnerMgr, &prefixMgr, &sgdb);
    pipeline.setEpicService(&epicSvc);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    epicSvc.setGameManager(&gm);

    // Seed Epic library cache
    EpicLibraryItem item;
    item.appName = QStringLiteral("CelesteApp");
    item.namespaceId = QStringLiteral("ns1");
    item.catalogItemId = QStringLiteral("cat1");
    item.title = QStringLiteral("Celeste");
    item.developer = QStringLiteral("Maddy Makes Games");
    item.description = QStringLiteral("Climb Celeste Mountain.");
    item.downloadSize = 1024 * 1024 * 500;
    item.installSize = 1024 * 1024 * 1200;
    item.lastSynced = 1700000000;
    QVERIFY(db.saveEpicLibraryItems({item}));
    epicSvc.libraryModel()->reload();

    QCOMPARE(epicSvc.libraryModel()->rowCount(), 1);
    QCOMPARE(epicSvc.libraryModel()->get(0).value(QStringLiteral("isInstalled")).toBool(),
             false);

    // Regression: constructing EpicService against a DB with >= 2 cached Epic items
    // triggers std::sort -> getDownloadState() in constructor; must not access uninitialized m_downloads.
    EpicLibraryItem item2;
    item2.appName = QStringLiteral("LimboApp");
    item2.namespaceId = QStringLiteral("ns2");
    item2.catalogItemId = QStringLiteral("cat2");
    item2.title = QStringLiteral("LIMBO");
    item2.lastSynced = 1700000001;
    QVERIFY(db.saveEpicLibraryItems({item, item2}));
    {
      EpicService restartedSvc(&db, &settings, &runnerMgr, &prefixMgr, &sgdb);
      QCOMPARE(restartedSvc.libraryModel()->rowCount(), 2);
    }
    QVERIFY(db.saveEpicLibraryItems({item}));
    QVERIFY(db.clearEpicLibrary());
    QVERIFY(db.saveEpicLibraryItems({item}));
    epicSvc.libraryModel()->reload();

    // Create dummy installed game directory & executable on disk
    const QString installDir = tmpDir.filePath(QStringLiteral("Games/Celeste"));
    QVERIFY(QDir().mkpath(installDir));
    const QString exePath = installDir + QStringLiteral("/Celeste.exe");
    QFile exeFile(exePath);
    QVERIFY(exeFile.open(QIODevice::WriteOnly));
    exeFile.write("MZ\x90\x00");
    exeFile.close();

    // Register Epic game with Default prefix & Default runner ("")
    const QString gameId = gm.registerEpicGame(
        item.appName, item.namespaceId, item.catalogItemId, item.title, exePath,
        installDir, QStringLiteral("-windowed"), QStringLiteral("1.4.0.0"),
        QString(), QStringLiteral("default-prefix"));
    QVERIFY(!gameId.isEmpty());
    QCOMPARE(gm.model()->rowCount(), 1);
    QCOMPARE(gm.model()->get(0).value(QStringLiteral("isEpic")).toBool(), true);
    QCOMPARE(gm.model()->get(0).value(QStringLiteral("prefixId")).toString(),
             QStringLiteral("default-prefix"));
    QCOMPARE(gm.model()->get(0).value(QStringLiteral("runnerId")).toString(),
             QString());
    QCOMPARE(epicSvc.libraryModel()->get(0).value(QStringLiteral("isInstalled")).toBool(),
             true);
    QCOMPARE(epicSvc.libraryModel()->get(0).value(QStringLiteral("installedGameId")).toString(),
             gameId);

    // Verify Epic launch args generation
    auto loadedGame = db.getGame(gameId);
    QVERIFY(loadedGame.has_value());
    QVERIFY(loadedGame->isEpic());
    const QStringList epicArgs = LaunchPipeline::buildEpicLaunchArgs(
        *loadedGame, QStringLiteral("excode123"), QStringLiteral("acc42"),
        QStringLiteral("PlayerOne"));
    QVERIFY(epicArgs.contains(QStringLiteral("-AUTH_PASSWORD=excode123")));
    QVERIFY(epicArgs.contains(QStringLiteral("-AUTH_TYPE=exchangecode")));
    QVERIFY(epicArgs.contains(QStringLiteral("-epicapp=CelesteApp")));
    QVERIFY(epicArgs.contains(QStringLiteral("-EpicPortal")));
    QVERIFY(epicArgs.contains(QStringLiteral("-epicusername=PlayerOne")));

    RunnerRecord protonRunner;
    protonRunner.id = QStringLiteral("runner-proton");
    protonRunner.name = QStringLiteral("Proton-GE");
    protonRunner.type = QStringLiteral("proton-ge");
    protonRunner.path = QStringLiteral("/opt/proton-ge");
    protonRunner.binaryPath = QStringLiteral("/opt/proton-ge/proton");
    auto defPfx = db.getPrefix(QStringLiteral("default-prefix"));
    QVERIFY(defPfx.has_value());
    const LaunchPlan plan =
        pipeline.buildLaunchPlan(*loadedGame, protonRunner, *defPfx, epicArgs);
    QVERIFY(plan.arguments.contains(QStringLiteral("-AUTH_PASSWORD=excode123")));
    QVERIFY(plan.arguments.contains(QStringLiteral("-windowed")));

    // Remove Epic game WITH deleteGameFiles = true -> deletes folder on disk, keeps in Epic account cache
    QVERIFY(gm.removeGame(gameId, false, true));
    QVERIFY(!QDir(installDir).exists());
    QCOMPARE(gm.model()->rowCount(), 0);
    QCOMPARE(epicSvc.libraryModel()->rowCount(), 1);
    QCOMPARE(epicSvc.libraryModel()->get(0).value(QStringLiteral("isInstalled")).toBool(),
             false);
  }

  void testEpicQmlUiAndNavigation() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    QSettings rawSettings(QStringLiteral("Tsuki"),
                          QStringLiteral("TsukiLauncher"));
    const bool hadEpicBadge =
        rawSettings.contains(QStringLiteral("appearance/showEpicBadge"));
    const QVariant oldEpicBadge =
        rawSettings.value(QStringLiteral("appearance/showEpicBadge"));
    const auto restoreEpicSettings = qScopeGuard([&]() {
      if (hadEpicBadge)
        rawSettings.setValue(QStringLiteral("appearance/showEpicBadge"),
                             oldEpicBadge);
      else
        rawSettings.remove(QStringLiteral("appearance/showEpicBadge"));
    });

    DatabaseManager db(tmpDir.filePath(QStringLiteral("epic_qml.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    settings.setShowEpicBadge(true);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    EpicService epicSvc(&db, &settings, &runnerMgr, &prefixMgr, &sgdb);
    pipeline.setEpicService(&epicSvc);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    epicSvc.setGameManager(&gm);
    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm, &epicSvc);

    EpicLibraryItem item;
    item.appName = QStringLiteral("HadesApp");
    item.namespaceId = QStringLiteral("ns2");
    item.catalogItemId = QStringLiteral("cat2");
    item.title = QStringLiteral("Hades");
    item.developer = QStringLiteral("Supergiant Games");
    item.downloadSize = 1024LL * 1024 * 1024 * 5;
    item.installSize = 1024LL * 1024 * 1024 * 15;
    QVERIFY(db.saveEpicLibraryItems({item}));
    epicSvc.libraryModel()->reload();

    QQuickWindow win;
    win.resize(1280, 820);
    win.show();
    QVERIFY(QTest::qWaitForWindowExposed(&win));

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QStringList qmlErrors;
    QObject::connect(
        &engine, &QQmlEngine::warnings, &win,
        [&](const QList<QQmlError> &warnings) {
          for (const QQmlError &err : warnings) {
            const QString txt = err.toString();
            if (txt.contains(QStringLiteral("ReferenceError")) ||
                txt.contains(QStringLiteral("TypeError")) ||
                txt.contains(QStringLiteral("Binding loop")) ||
                txt.contains(QStringLiteral("Required property"))) {
              qmlErrors << txt;
            }
          }
        });

    // 1. Sidebar 3rd tab is "Epic Games" (replacing "Recent")
    QQmlComponent sidebarComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/home/Sidebar.qml")));
    QVERIFY2(sidebarComp.isReady(), qPrintable(sidebarComp.errorString()));
    std::unique_ptr<QObject> sidebarObj(sidebarComp.create());
    QVERIFY(sidebarObj != nullptr);
    const QVariantList navModel = sidebarObj->property("navModel").toList();
    QVERIFY(navModel.size() >= 3);
    QCOMPARE(navModel.at(2).toMap().value(QStringLiteral("name")).toString(),
             QStringLiteral("Epic Games"));
    QCOMPARE(navModel.at(2).toMap().value(QStringLiteral("section")).toString(),
             QStringLiteral("epic"));
    for (const QVariant &v : navModel) {
      QVERIFY(v.toMap().value(QStringLiteral("name")).toString() !=
              QStringLiteral("Recent"));
    }
    sidebarObj.reset();

    // 2. HomePage cycles to "epic" on 3rd tab
    QQmlComponent homeComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/home/HomePage.qml")));
    QVERIFY2(homeComp.isReady(), qPrintable(homeComp.errorString()));
    std::unique_ptr<QObject> homeObj(homeComp.create());
    QVERIFY(homeObj != nullptr);
    qobject_cast<QQuickItem *>(homeObj.get())->setParentItem(win.contentItem());
    qobject_cast<QQuickItem *>(homeObj.get())->setSize(QSizeF(1280, 820));
    QCoreApplication::processEvents();
    QCOMPARE(homeObj->property("activeSection").toString(),
             QStringLiteral("library"));
    QVERIFY(QMetaObject::invokeMethod(homeObj.get(), "cycleTab",
                                      Q_ARG(QVariant, QVariant(1))));
    QVERIFY(QMetaObject::invokeMethod(homeObj.get(), "cycleTab",
                                      Q_ARG(QVariant, QVariant(1))));
    QCOMPARE(homeObj->property("activeSection").toString(),
             QStringLiteral("epic"));
    homeObj.reset();

    // 3. EpicLibraryView loads cleanly
    QQmlComponent epicViewComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/pages/EpicLibraryView.qml")));
    QVERIFY2(epicViewComp.isReady(), qPrintable(epicViewComp.errorString()));
    std::unique_ptr<QObject> epicViewObj(epicViewComp.create());
    QVERIFY(epicViewObj != nullptr);
    qobject_cast<QQuickItem *>(epicViewObj.get())
        ->setParentItem(win.contentItem());
    qobject_cast<QQuickItem *>(epicViewObj.get())->setSize(QSizeF(1060, 820));
    QCoreApplication::processEvents();
    QVERIFY(epicViewObj->findChild<QQuickItem *>(
                QStringLiteral("epicOpenBrowserBtn")) != nullptr);
    QVERIFY(epicViewObj->findChild<QQuickItem *>(
                QStringLiteral("epicTokenField")) != nullptr);
    QVERIFY(epicViewObj->findChild<QQuickItem *>(
                QStringLiteral("epicSignInBtn")) != nullptr);
    epicViewObj.reset();

    // 4. EpicDownloadDialog defaults to Default prefix and Default runner
    QQmlComponent dlDlgComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/components/EpicDownloadDialog.qml")));
    QVERIFY2(dlDlgComp.isReady(), qPrintable(dlDlgComp.errorString()));
    std::unique_ptr<QObject> dlDlgObj(dlDlgComp.create());
    QVERIFY(dlDlgObj != nullptr);
    dlDlgObj->setProperty("parent", QVariant::fromValue(win.contentItem()));
    QVERIFY(QMetaObject::invokeMethod(
        dlDlgObj.get(), "openForApp",
        Q_ARG(QVariant, QVariant(QStringLiteral("HadesApp")))));
    QCoreApplication::processEvents();
    QCOMPARE(dlDlgObj->property("useDedicatedPrefix").toBool(), false);
    QCOMPARE(dlDlgObj->property("runnerIndex").toInt(), 0);
    const auto pfxList = prefixMgr.prefixesVariant();
    const int selPfxIdx = dlDlgObj->property("existingPrefixIndex").toInt();
    QVERIFY(selPfxIdx >= 0 && selPfxIdx < pfxList.size());
    QCOMPARE(pfxList.at(selPfxIdx).toMap().value(QStringLiteral("id")).toString(),
             QStringLiteral("default-prefix"));
    dlDlgObj.reset();

    // 5. GameDetailPage uninstalled Epic mode -> Download button & Overview card
    QQmlComponent detailComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.isReady(), qPrintable(detailComp.errorString()));
    std::unique_ptr<QObject> detailObj(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), QString()},
         {QStringLiteral("epicAppName"), QStringLiteral("HadesApp")}}));
    QVERIFY(detailObj != nullptr);
    qobject_cast<QQuickItem *>(detailObj.get())->setParentItem(win.contentItem());
    qobject_cast<QQuickItem *>(detailObj.get())->setSize(QSizeF(1280, 820));
    QCoreApplication::processEvents();
    QCOMPARE(detailObj->property("isUninstalledEpic").toBool(), true);
    auto *primaryBtn = detailObj->findChild<QQuickItem *>(
        QStringLiteral("detailPrimaryActionBtn"));
    QVERIFY(primaryBtn != nullptr);
    QCOMPARE(primaryBtn->property("text").toString(),
             QStringLiteral("Download"));
    auto *overviewCard = detailObj->findChild<QQuickItem *>(
        QStringLiteral("epicOverviewCard"));
    QVERIFY(overviewCard != nullptr);
    QCOMPARE(overviewCard->isVisible(), true);
    detailObj.reset();

    // 6. MediaGrid Epic badge visibility obeys appSettings.showEpicBadge
    const QString hadesDir = tmpDir.filePath(QStringLiteral("Games/Hades"));
    QVERIFY(QDir().mkpath(hadesDir));
    const QString hadesExe = hadesDir + QStringLiteral("/Hades.exe");
    QFile f(hadesExe);
    QVERIFY(f.open(QIODevice::WriteOnly));
    f.write("MZ\x90\x00");
    f.close();
    const QString hadesGameId = gm.registerEpicGame(
        item.appName, item.namespaceId, item.catalogItemId, item.title, hadesExe,
        hadesDir);
    QVERIFY(!hadesGameId.isEmpty());

    QQmlComponent gridComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/home/MediaGrid.qml")));
    QVERIFY2(gridComp.isReady(), qPrintable(gridComp.errorString()));
    std::unique_ptr<QObject> gridObj(gridComp.createWithInitialProperties(
        {{QStringLiteral("model"), QVariant::fromValue(gm.model())}}));
    QVERIFY(gridObj != nullptr);
    qobject_cast<QQuickItem *>(gridObj.get())->setParentItem(win.contentItem());
    qobject_cast<QQuickItem *>(gridObj.get())->setSize(QSizeF(1000, 720));
    QCoreApplication::processEvents();
    auto findVisualChild = [](QQuickItem *rootItem,
                              const QString &objName) -> QQuickItem * {
      if (!rootItem) return nullptr;
      QList<QQuickItem *> stack{rootItem};
      while (!stack.isEmpty()) {
        QQuickItem *cur = stack.takeLast();
        if (cur->objectName() == objName) return cur;
        for (QQuickItem *ch : cur->childItems()) {
          stack.append(ch);
        }
      }
      return nullptr;
    };
    gm.model()->setFilterType(-1);
    QCOMPARE(gm.model()->rowCount(), 1);
    QQuickItem *gridItem = qobject_cast<QQuickItem *>(gridObj.get());
    QQuickItem *epicBadge = nullptr;
    QTRY_VERIFY((epicBadge = findVisualChild(
                     gridItem, QStringLiteral("epicCardBadge"))) != nullptr);
    QTRY_COMPARE(epicBadge->isVisible(), true);
    settings.setShowEpicBadge(false);
    QTRY_COMPARE(epicBadge->isVisible(), false);
    gridObj.reset();

    // 7. RemoveGameDialog removes installed Epic game files from disk
    QQmlComponent remComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/components/RemoveGameDialog.qml")));
    QVERIFY2(remComp.isReady(), qPrintable(remComp.errorString()));
    std::unique_ptr<QObject> remObj(remComp.create());
    QVERIFY(remObj != nullptr);
    remObj->setProperty("parent", QVariant::fromValue(win.contentItem()));
    QVERIFY(QMetaObject::invokeMethod(
        remObj.get(), "openDialog",
        Q_ARG(QVariant, QVariant(hadesGameId)),
        Q_ARG(QVariant, QVariant(QStringLiteral("Hades"))),
        Q_ARG(QVariant, QVariant(QStringLiteral("default-prefix")))));
    QCoreApplication::processEvents();
    QCOMPARE(remObj->property("isEpicGame").toBool(), true);
    auto *remContent = remObj->property("contentItem").value<QQuickItem *>();
    QVERIFY(remContent != nullptr);
    auto *remConfirmBtn =
        remContent->findChild<QQuickItem *>(QStringLiteral("removeConfirmBtn"));
    QVERIFY(remConfirmBtn != nullptr);
    QVERIFY(QMetaObject::invokeMethod(remConfirmBtn, "clicked"));
    QCoreApplication::processEvents();
    QVERIFY(!QDir(hadesDir).exists());
    remObj.reset();

    QVERIFY2(qmlErrors.isEmpty(),
             qPrintable(qmlErrors.join(QLatin1Char('\n'))));
  }

  void testEpicImportCopyMoveInPlaceAndRemoveToggle() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    DatabaseManager db(tmpDir.filePath(QStringLiteral("epic_import.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr,
                            &diagMgr);
    EpicService epicSvc(&db, &settings, &runnerMgr, &prefixMgr, &sgdb);
    pipeline.setEpicService(&epicSvc);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    epicSvc.setGameManager(&gm);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm, &epicSvc);

    EpicLibraryItem gw;
    gw.appName = QStringLiteral("GhostwireApp");
    gw.namespaceId = QStringLiteral("ns_gw");
    gw.catalogItemId = QStringLiteral("cat_gw");
    gw.title = QStringLiteral("Ghostwire Tokyo");
    QVERIFY(db.saveEpicLibraryItems({gw}));
    epicSvc.libraryModel()->reload();

    // Create Heroic-style pre-downloaded game tree
    const QString heroicDir =
        tmpDir.filePath(QStringLiteral("Heroic/GhostwireTokyo"));
    const QString subBin = heroicDir + QStringLiteral("/Snowfall/Binaries/Win64");
    QVERIFY(QDir().mkpath(subBin));
    const QString shippingExe =
        subBin + QStringLiteral("/GhostwireTokyo-Win64-Shipping.exe");
    {
      QFile ef(shippingExe);
      QVERIFY(ef.open(QIODevice::WriteOnly));
      ef.write(QByteArray(4096, 'G'));
      ef.close();
    }
    const QString pakFile = heroicDir + QStringLiteral("/Snowfall/data.pak");
    {
      QFile pf(pakFile);
      QVERIFY(pf.open(QIODevice::WriteOnly));
      pf.write(QByteArray(8192, 'P'));
      pf.close();
    }

    const QString targetBase = tmpDir.filePath(QStringLiteral("TsukiEpic"));
    QVERIFY(QDir().mkpath(targetBase));

    const QVariantMap info =
        epicSvc.inspectImportSource(gw.appName, heroicDir, targetBase);
    QCOMPARE(info.value(QStringLiteral("valid")).toBool(), true);
    QCOMPARE(info.value(QStringLiteral("fileCount")).toInt(), 2);
    QVERIFY(info.value(QStringLiteral("suggestedExe"))
                .toString()
                .endsWith(QStringLiteral("GhostwireTokyo-Win64-Shipping.exe")));

    // 1. Copy mode keeps source untouched and registers in targetBase/Ghostwire Tokyo
    QSignalSpy finSpy(&epicSvc, &EpicService::downloadFinished);
    epicSvc.importGame(gw.appName, heroicDir, QStringLiteral("copy"),
                       targetBase, QString(), QStringLiteral("default-prefix"));
    QTRY_COMPARE_WITH_TIMEOUT(finSpy.count(), 1, 5000);
    const QString copiedGameId = finSpy.takeFirst().at(1).toString();
    QVERIFY(!copiedGameId.isEmpty());
    QVERIFY(QDir(heroicDir).exists());
    const QString expectedCopyDir = targetBase + QStringLiteral("/Ghostwire Tokyo");
    QVERIFY(QFileInfo::exists(
        expectedCopyDir +
        QStringLiteral("/Snowfall/Binaries/Win64/GhostwireTokyo-Win64-Shipping.exe")));
    QCOMPARE(db.getGame(copiedGameId)->epicInPlaceImported, false);

    // Verify RemoveGameDialog defaults deleteEpicFilesToggle=true on copied game,
    // and unchecking preserves disk files
    QQuickWindow win;
    win.resize(1280, 820);
    win.show();
    QVERIFY(QTest::qWaitForWindowExposed(&win));

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QQmlComponent remComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/components/RemoveGameDialog.qml")));
    QVERIFY2(remComp.isReady(), qPrintable(remComp.errorString()));
    std::unique_ptr<QObject> remObj(remComp.create());
    remObj->setProperty("parent", QVariant::fromValue(win.contentItem()));
    QVERIFY(QMetaObject::invokeMethod(
        remObj.get(), "openDialog",
        Q_ARG(QVariant, QVariant(copiedGameId)),
        Q_ARG(QVariant, QVariant(QStringLiteral("Ghostwire Tokyo"))),
        Q_ARG(QVariant, QVariant(QStringLiteral("default-prefix")))));
    QCoreApplication::processEvents();
    auto *remContent = remObj->property("contentItem").value<QQuickItem *>();
    QVERIFY(remContent != nullptr);
    auto *delToggle = remContent->findChild<QQuickItem *>(
        QStringLiteral("deleteEpicFilesToggle"));
    QVERIFY(delToggle != nullptr);
    QCOMPARE(delToggle->property("checked").toBool(), true);
    delToggle->setProperty("checked", false);
    auto *remBtn =
        remContent->findChild<QQuickItem *>(QStringLiteral("removeConfirmBtn"));
    QVERIFY(QMetaObject::invokeMethod(remBtn, "clicked"));
    QCoreApplication::processEvents();
    QVERIFY(QDir(expectedCopyDir).exists());
    QVERIFY(QDir(expectedCopyDir).removeRecursively());

    // 2. Move mode relocates source -> destination and deletes original folder
    epicSvc.importGame(gw.appName, heroicDir, QStringLiteral("move"),
                       targetBase, QString(), QStringLiteral("default-prefix"));
    QTRY_COMPARE_WITH_TIMEOUT(finSpy.count(), 1, 5000);
    const QString movedId = finSpy.takeFirst().at(1).toString();
    QVERIFY(!movedId.isEmpty());
    QVERIFY(!QDir(heroicDir).exists());
    QVERIFY(QDir(expectedCopyDir).exists());
    QCOMPARE(db.getGame(movedId)->epicInPlaceImported, false);
    QVERIFY(gm.removeGame(movedId, false, false));

    // 3. Keep-in-place mode registers folder directly, and RemoveGameDialog defaults toggle OFF
    epicSvc.importGame(gw.appName, expectedCopyDir, QStringLiteral("in_place"));
    QTRY_COMPARE_WITH_TIMEOUT(finSpy.count(), 1, 5000);
    const QString inPlaceId = finSpy.takeFirst().at(1).toString();
    QVERIFY(!inPlaceId.isEmpty());
    QCOMPARE(db.getGame(inPlaceId)->epicInPlaceImported, true);
    QCOMPARE(db.getGame(inPlaceId)->epicInstallDir, expectedCopyDir);

    QVERIFY(QMetaObject::invokeMethod(
        remObj.get(), "openDialog",
        Q_ARG(QVariant, QVariant(inPlaceId)),
        Q_ARG(QVariant, QVariant(QStringLiteral("Ghostwire Tokyo"))),
        Q_ARG(QVariant, QVariant(QStringLiteral("default-prefix")))));
    QCoreApplication::processEvents();
    QCOMPARE(delToggle->property("checked").toBool(), false);
    QVERIFY(QMetaObject::invokeMethod(remBtn, "clicked"));
    QCoreApplication::processEvents();
    QVERIFY(QDir(expectedCopyDir).exists());
    remObj.reset();

    // 4. QML UI: GameDetailPage shows dropdown next to Download & EpicImportDialog defaults to Copy
    QQmlComponent detailComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.isReady(), qPrintable(detailComp.errorString()));
    std::unique_ptr<QObject> detailObj(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), QString()},
         {QStringLiteral("epicAppName"), QStringLiteral("GhostwireApp")}}));
    QVERIFY(detailObj != nullptr);
    qobject_cast<QQuickItem *>(detailObj.get())->setParentItem(win.contentItem());
    qobject_cast<QQuickItem *>(detailObj.get())->setSize(QSizeF(1280, 820));
    QCoreApplication::processEvents();
    auto *dropBtn = detailObj->findChild<QQuickItem *>(
        QStringLiteral("detailActionsDropdownBtn"));
    QVERIFY(dropBtn != nullptr);
    QCOMPARE(dropBtn->isVisible(), true);
    detailObj.reset();

    QQmlComponent impComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/components/EpicImportDialog.qml")));
    QVERIFY2(impComp.isReady(), qPrintable(impComp.errorString()));
    std::unique_ptr<QObject> impObj(impComp.create());
    QVERIFY(impObj != nullptr);
    impObj->setProperty("parent", QVariant::fromValue(win.contentItem()));
    QVERIFY(QMetaObject::invokeMethod(
        impObj.get(), "openForApp",
        Q_ARG(QVariant, QVariant(QStringLiteral("GhostwireApp")))));
    QCoreApplication::processEvents();
    QCOMPARE(impObj->property("transferMode").toString(), QStringLiteral("copy"));
    QCOMPARE(impObj->property("runnerIndex").toInt(), 0);
    QCOMPARE(impObj->property("useDedicatedPrefix").toBool(), false);
    impObj.reset();
  }

  void testMultiplayerRuntimesEosOverlayAndPrefixRegistry() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    const QByteArray oldXdgDataHome = qgetenv("XDG_DATA_HOME");
    const bool hadXdgDataHome = qEnvironmentVariableIsSet("XDG_DATA_HOME");
    qputenv("XDG_DATA_HOME", tmpDir.path().toUtf8());
    const auto restoreXdg = qScopeGuard([&]() {
      if (hadXdgDataHome)
        qputenv("XDG_DATA_HOME", oldXdgDataHome);
      else
        qunsetenv("XDG_DATA_HOME");
    });

    // 1. GameRecord launch config round-trip for online/multiplayer flags
    GameRecord rec;
    rec.id = QStringLiteral("epic-gw");
    rec.epicInPlaceImported = true;
    rec.enableEosOverlay = true;
    rec.enableEacRuntime = true;
    rec.enableBattlEyeRuntime = true;
    const QString cfgJson = rec.launchConfigToJson();
    GameRecord restored;
    restored.applyLaunchConfigJson(cfgJson);
    QCOMPARE(restored.epicInPlaceImported, true);
    QCOMPARE(restored.enableEosOverlay, true);
    QCOMPARE(restored.enableEacRuntime, true);
    QCOMPARE(restored.enableBattlEyeRuntime, true);

    // 2. PrefixManager::configureEosOverlayRegistry updates user.reg safely
    const QString fakePrefix = tmpDir.filePath(QStringLiteral("FakePrefix"));
    QVERIFY(QDir().mkpath(fakePrefix));
    {
      QFile regFile(fakePrefix + QStringLiteral("/user.reg"));
      QVERIFY(regFile.open(QIODevice::WriteOnly | QIODevice::Text));
      regFile.write("WINE REGISTRY Version 2\n\n[Software\\\\Wine\\\\AppDefaults]\n\"Version\"=\"win10\"\n");
      regFile.close();
    }
    const QString overlayDir = AppSettings::toolsDir() + QStringLiteral("/eos_overlay");
    QVERIFY(QDir().mkpath(overlayDir));
    {
      QFile marker(overlayDir + QStringLiteral("/EOSOverlayRenderer-Win64-Shipping.exe"));
      QVERIFY(marker.open(QIODevice::WriteOnly));
      marker.write("MZ");
      marker.close();
    }
    {
      QFile vf(overlayDir + QStringLiteral("/.tsuki_eos_version"));
      QVERIFY(vf.open(QIODevice::WriteOnly | QIODevice::Text));
      vf.write("1.16.0");
      vf.close();
    }

    QVERIFY(PrefixManager::configureEosOverlayRegistry(fakePrefix, overlayDir, true));
    {
      QFile regFile(fakePrefix + QStringLiteral("/user.reg"));
      QVERIFY(regFile.open(QIODevice::ReadOnly | QIODevice::Text));
      const QString content = QString::fromUtf8(regFile.readAll());
      QVERIFY(content.contains(QStringLiteral("[Software\\\\Wine\\\\AppDefaults]")));
      QVERIFY(content.contains(QStringLiteral("[Software\\\\Epic Games\\\\EOS]")));
      QVERIFY(content.contains(QStringLiteral("\"OverlayPath\"=\"Z:") + overlayDir + QLatin1Char('"')));
    }
    QVERIFY(PrefixManager::configureEosOverlayRegistry(fakePrefix, QString(), false));
    {
      QFile regFile(fakePrefix + QStringLiteral("/user.reg"));
      QVERIFY(regFile.open(QIODevice::ReadOnly | QIODevice::Text));
      const QString content = QString::fromUtf8(regFile.readAll());
      QVERIFY(content.contains(QStringLiteral("[Software\\\\Wine\\\\AppDefaults]")));
      QVERIFY(!content.contains(QStringLiteral("OverlayPath")));
    }

    // 3. Space-safe symlink + EAC/BattlEye runtime resolution + LaunchPipeline injection
    const QString spacedDir = tmpDir.filePath(QStringLiteral("Steam/Proton EasyAntiCheat Runtime"));
    QVERIFY(QDir().mkpath(spacedDir));
    const QString safeLink = RunnerManager::ensureSpaceSafeRuntimePath(spacedDir, QStringLiteral("test_eac_link"));
    QVERIFY(!safeLink.contains(QLatin1Char(' ')));
    QVERIFY(QFileInfo(safeLink).isSymLink());

    const QString eacDir = AppSettings::toolsDir() + QStringLiteral("/runtimes/eac_runtime");
    const QString beDir = AppSettings::toolsDir() + QStringLiteral("/runtimes/battleye_runtime");
    QVERIFY(QDir().mkpath(eacDir + QStringLiteral("/v2/lib64")));
    QVERIFY(QDir().mkpath(beDir + QStringLiteral("/v2/lib64")));
    QCOMPARE(RunnerManager::resolveEacRuntimePath(), QDir::cleanPath(eacDir));
    QCOMPARE(RunnerManager::resolveBattlEyeRuntimePath(), QDir::cleanPath(beDir));

    DatabaseManager db(tmpDir.filePath(QStringLiteral("mp_test.db")));
    QVERIFY(db.initialize());
    AppSettings settings;
    settings.setDatabaseManager(&db);
    DownloadManager dl;
    RunnerManager runnerMgr(&db, &settings, &dl);
    PrefixManager prefixMgr(&db, &settings, &runnerMgr);
    WinetricksManager wtMgr(&db, &settings, &runnerMgr, &dl);
    ControllerManager ctrlMgr(&db, &settings);
    SteamGridDbService sgdb(&settings, &dl);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr, &diagMgr);
    EpicService epicSvc(&db, &settings, &runnerMgr, &prefixMgr, &sgdb);
    pipeline.setEpicService(&epicSvc);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
    epicSvc.setGameManager(&gm);
    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm, &epicSvc);

    QCOMPARE(epicSvc.isEosOverlayInstalled(), true);
    QCOMPARE(epicSvc.eosOverlayVersion(), QStringLiteral("1.16.0"));
    QCOMPARE(runnerMgr.eacRuntimeAvailable(), true);
    QCOMPARE(runnerMgr.battleyeRuntimeAvailable(), true);

    const QString gameDir = tmpDir.filePath(QStringLiteral("Games/GW"));
    QVERIFY(QDir().mkpath(gameDir));
    const QString exePath = gameDir + QStringLiteral("/Game.exe");
    {
      QFile ef(exePath);
      QVERIFY(ef.open(QIODevice::WriteOnly));
      ef.write("MZ");
      ef.close();
    }
    const QString gameId = gm.registerEpicGame(
        QStringLiteral("GWApp"), QStringLiteral("ns"), QStringLiteral("cat"),
        QStringLiteral("Ghostwire"), exePath, gameDir);
    QVERIFY(!gameId.isEmpty());
    QVERIFY(gm.updateGameDetails(
        gameId, {{QStringLiteral("enableEosOverlay"), true},
                 {QStringLiteral("enableEacRuntime"), true},
                 {QStringLiteral("enableBattlEyeRuntime"), true}}));

    const auto loadedOpt = db.getGame(gameId);
    QVERIFY(loadedOpt.has_value());
    RunnerRecord protonRunner;
    protonRunner.id = QStringLiteral("p-test");
    protonRunner.name = QStringLiteral("GE-Proton Test");
    protonRunner.type = QStringLiteral("proton");
    protonRunner.binaryPath = QStringLiteral("/usr/bin/true");
    PrefixRecord pfx;
    pfx.id = QStringLiteral("default-prefix");
    pfx.name = QStringLiteral("Default");
    pfx.path = fakePrefix;
    const LaunchPlan plan = pipeline.buildLaunchPlan(*loadedOpt, protonRunner, pfx);
    QCOMPARE(plan.environment.value(QStringLiteral("PROTON_EAC_RUNTIME")),
             QDir::cleanPath(eacDir));
    QCOMPARE(plan.environment.value(QStringLiteral("PROTON_BATTLEYE_RUNTIME")),
             QDir::cleanPath(beDir));

    // 4. QML toggles on GameDetailPage load and persist multiplayer options
    QQuickWindow win;
    win.resize(1280, 820);
    win.show();
    QVERIFY(QTest::qWaitForWindowExposed(&win));

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QQmlComponent detailComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.isReady(), qPrintable(detailComp.errorString()));
    std::unique_ptr<QObject> detailObj(detailComp.createWithInitialProperties(
        {{QStringLiteral("gameId"), gameId},
         {QStringLiteral("epicAppName"), QStringLiteral("GWApp")}}));
    QVERIFY(detailObj != nullptr);
    qobject_cast<QQuickItem *>(detailObj.get())->setParentItem(win.contentItem());
    qobject_cast<QQuickItem *>(detailObj.get())->setSize(QSizeF(1280, 820));
    QCoreApplication::processEvents();

    auto *eosTgl =
        detailObj->findChild<QQuickItem *>(QStringLiteral("eosOverlayToggle"));
    auto *eacTgl =
        detailObj->findChild<QQuickItem *>(QStringLiteral("eacRuntimeToggle"));
    auto *beTgl = detailObj->findChild<QQuickItem *>(
        QStringLiteral("battleyeRuntimeToggle"));
    QVERIFY(eosTgl != nullptr);
    QVERIFY(eacTgl != nullptr);
    QVERIFY(beTgl != nullptr);
    QCOMPARE(eosTgl->property("checked").toBool(), true);
    QCOMPARE(eacTgl->property("checked").toBool(), true);
    QCOMPARE(beTgl->property("checked").toBool(), true);
    detailObj.reset();
  }
};

QTEST_MAIN(TestTsuki)
#include "test_tsuki.moc"
