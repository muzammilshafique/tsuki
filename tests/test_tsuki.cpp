#include "../src/core/AppSettings.h"
#include "../src/core/DatabaseManager.h"
#include "../src/services/ControllerManager.h"
#include "../src/services/DiagnosticsManager.h"
#include "../src/services/DownloadManager.h"
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
#include <QKeyEvent>
#include <QMouseEvent>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
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
  candidates << QStringLiteral(TSUKI_SOURCE_DIR) + QLatin1Char('/') + relativePath;
#endif
  candidates << QDir::currentPath() + QLatin1Char('/') + relativePath
             << QCoreApplication::applicationDirPath() + QStringLiteral("/../") + relativePath
             << QFileInfo(QString::fromUtf8(__FILE__)).absolutePath() + QStringLiteral("/../") + relativePath;
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
    const QByteArray script =
        QByteArray("#!/bin/sh\n"
                   "setsid sleep 30 >/dev/null 2>&1 &\n"
                   "CPID=$!\n"
                   "echo \"$CPID\" > \"") +
        pidFile.toUtf8() +
        QByteArray(".tmp\"\n"
                   "mv \"") +
        pidFile.toUtf8() +
        QByteArray(".tmp\" \"") +
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
      if (pid <= 1) return false;
      if (::kill(static_cast<pid_t>(pid), 0) != 0) return false;
      QFile statFile(QStringLiteral("/proc/%1/stat").arg(pid));
      if (!statFile.open(QIODevice::ReadOnly)) return false;
      const QByteArray data = statFile.readAll();
      const int rparen = data.lastIndexOf(')');
      if (rparen < 0) return false;
      const QList<QByteArray> fields = data.mid(rparen + 1).trimmed().split(' ');
      if (fields.isEmpty()) return false;
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

    // 1. Test AMOLED Theme Mode (mode 3)
    settings.setThemeMode(3);
    QCOMPARE(settings.themeMode(), 3);
    QVERIFY(settings.isEffectiveDark());
    QCOMPARE(settings.bgColor(), QColor("#000000"));
    QCOMPARE(settings.sidebarColor(), QColor("#000000"));
    QCOMPARE(settings.surfaceColor(), QColor("#0d0d10"));
    QCOMPARE(settings.inputColor(), QColor("#141417"));

    // 2. Test Custom Background Color
    // 2. Test Custom Background Color & Container Harmonization
    settings.setThemeMode(0); // Dark mode
    settings.setCustomBgColor("#123456");
    QCOMPARE(settings.customBgColor(), QString("#123456"));
    QCOMPARE(settings.bgColor(), QColor("#123456"));
    // Container colors harmonize with selected background color
    QCOMPARE(settings.surfaceColor().hue(), QColor("#123456").hue());
    QVERIFY(settings.surfaceColor().lightness() >
            QColor("#123456").lightness());
    QVERIFY(settings.surfaceAltColor().lightness() >
            settings.surfaceColor().lightness());

    // Reset Background Color
    settings.resetBgColor();
    QVERIFY(settings.customBgColor().isEmpty());
    QCOMPARE(settings.bgColor(), QColor("#0d0d11"));
    QCOMPARE(settings.surfaceColor(), QColor("#16161d"));

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

    // 5. Test Accent Color invokable
    settings.setAccentColor(QColor("#ec4899"));
    QCOMPARE(settings.accentColor(), QColor("#ec4899"));

    // Clean up
    settings.resetBgColor();
    settings.resetSidebarColor();
    settings.setSyncSidebarColor(false);
    settings.setThemeMode(0);
  }

  void testShowGameNameSetting() {
    AppSettings settings;
    settings.setShowGameName(false);
    QCOMPARE(settings.showGameName(), false);

    bool signalFired = false;
    QObject::connect(&settings, &AppSettings::cardStyleChanged, [&]() {
      signalFired = true;
    });

    settings.setShowGameName(true);
    QCOMPARE(settings.showGameName(), true);
    QVERIFY(signalFired);

    settings.setShowGameName(false);
    QCOMPARE(settings.showGameName(), false);
  }

  void testGamepadAutoDetectionIconsAndInputNavigation() {
    // 1. Controller type auto-detection (PlayStation vs Xbox vs vendor IDs & names)
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Unknown Pad"), 0, SDL_CONTROLLER_TYPE_PS4),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Unknown Pad"), 0, SDL_CONTROLLER_TYPE_PS5),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Sony Controller"), 0x054c, SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("DualSense Wireless Controller"), 0, SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("playstation"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("PS4 Controller"), 0, SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("playstation"));

    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Xbox Pad"), 0, SDL_CONTROLLER_TYPE_XBOXONE),
             QStringLiteral("xbox"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Controller"), 0x045e, SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("xbox"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
                 QStringLiteral("Xbox Wireless Controller"), 0, SDL_CONTROLLER_TYPE_UNKNOWN),
             QStringLiteral("xbox"));
    QCOMPARE(ControllerManager::detectControllerTypeFromInfo(
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
    ControllerManager ctrlMgr(&db, &settings, std::make_unique<MockUinputBackend>());
    SteamGridDbService sgdb(&settings, &dlMgr);
    DiagnosticsManager diagMgr(&db, &settings, &runnerMgr, &prefixMgr);
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr, &diagMgr);
    GameManager gameMgr(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);
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

    // 3. SDL button signals & trigger hysteresis + UiController activeInputType switching
    QSignalSpy optionsSpy(&ctrlMgr, &ControllerManager::optionsActionRequested);
    QSignalSpy searchSpy(&ctrlMgr, &ControllerManager::searchActionRequested);
    QSignalSpy settingsSpy(&ctrlMgr, &ControllerManager::settingsActionRequested);
    QSignalSpy tabLeftSpy(&ctrlMgr, &ControllerManager::tabLeftRequested);
    QSignalSpy tabRightSpy(&ctrlMgr, &ControllerManager::tabRightRequested);
    QSignalSpy inputSpy(&ctrlMgr, &ControllerManager::gamepadInputReceived);

    // Start in keyboard mode
    uiCtrl.setActiveInputType(QStringLiteral("keyboard"));
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("keyboard"));
    QVERIFY(!uiCtrl.isGamepadActive());

    // Simulate PlayStation gamepad press -> UiController switches activeInputType to playstation
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

    // Trigger hysteresis: L2/R2 fire once above 16000, stay latched at 18000, reset below 8000
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

    // Switch controller override to Xbox and trigger button -> activeInputType tracks xbox
    ctrlMgr.setControllerTypeOverride(QStringLiteral("xbox"));
    ctrlMgr.handleButtonPress(SDL_CONTROLLER_BUTTON_A);
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("xbox"));
    QVERIFY(uiCtrl.isGamepadActive());

    // Switching back to keyboard disables gamepad prompts
    uiCtrl.setActiveInputType(QStringLiteral("keyboard"));
    QCOMPARE(uiCtrl.activeInputType(), QStringLiteral("keyboard"));
    QVERIFY(!uiCtrl.isGamepadActive());

    // While a game is running, controller input must not trigger Tsuki UI navigation
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

    // 2. MouseMove with >= 2px delta immediately deactivates keyboard nav and restores cursor
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

    // 7. Load GameDetailPage.qml & SettingsPage.qml and verify zero QML errors + M3TextField nav
    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"),
                                             &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"),
                                             &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"),
                                             &uiCtrl);

    QQmlComponent settingsComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/pages/SettingsPage.qml")));
    QVERIFY2(settingsComp.errors().isEmpty(),
             qPrintable(settingsComp.errorString()));
    QScopedPointer<QObject> settingsObj(settingsComp.create());
    QVERIFY(settingsObj != nullptr);
    auto *settingsItem = qobject_cast<QQuickItem *>(settingsObj.get());
    QVERIFY(settingsItem != nullptr);
    settingsItem->setParentItem(win.contentItem());
    settingsItem->setSize(QSizeF(1280, 820));

    QQmlComponent detailComp(
        &engine,
        resolveQmlUrl(QStringLiteral("src/qml/pages/GameDetailPage.qml")));
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

    // Navigate down from primaryActionBtn -> tabsBar -> titleField -> exePathField
    // Verifies titleField (M3TextField wrapper) does NOT freeze isTextInputActive()
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

    // Move mouse >= 2px while detail page is open -> immediately hides keyboard nav
    QMouseEvent moveHide(QEvent::MouseMove, QPointF(250, 250),
                         QPointF(250, 250), Qt::NoButton, Qt::NoButton,
                         Qt::NoModifier);
    QCoreApplication::sendEvent(&win, &moveHide);
    QVERIFY(!uiCtrl.isKeyboardNavActive());

    // 8. Verify showNavigationHud setting toggles NavigationHudBar showBar and emits signal
    const bool origHud = settings.showNavigationHud();
    QSignalSpy behaviorSpy(&settings, &AppSettings::behaviorChanged);
    QQmlComponent hudComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/components/NavigationHudBar.qml")));
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

    // 9. Verify RunnersView.qml compiles/loads cleanly with active downloads navigation
    QQmlComponent runnersComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/pages/RunnersView.qml")));
    QVERIFY2(runnersComp.errors().isEmpty(), qPrintable(runnersComp.errorString()));
    QScopedPointer<QObject> runnersObj(runnersComp.create());
    QVERIFY(runnersObj != nullptr);
  }

  void testGamescopeSupportAndPipeline() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    // Backup global QSettings keys modified by this test
    QSettings rawSettings(QStringLiteral("Tsuki"), QStringLiteral("TsukiLauncher"));
    const bool hadGsDefault = rawSettings.contains(QStringLiteral("performance/gamescope"));
    const QVariant oldGsDefault = rawSettings.value(QStringLiteral("performance/gamescope"));
    const bool hadGsCfg = rawSettings.contains(QStringLiteral("performance/gamescopeConfig"));
    const QVariant oldGsCfg = rawSettings.value(QStringLiteral("performance/gamescopeConfig"));
    const QByteArray oldPath = qgetenv("PATH");

    auto restoreEnv = qScopeGuard([&]() {
      if (hadGsDefault) rawSettings.setValue(QStringLiteral("performance/gamescope"), oldGsDefault);
      else rawSettings.remove(QStringLiteral("performance/gamescope"));
      if (hadGsCfg) rawSettings.setValue(QStringLiteral("performance/gamescopeConfig"), oldGsCfg);
      else rawSettings.remove(QStringLiteral("performance/gamescopeConfig"));
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

    // 2. AppSettings global Gamescope default is false by default & persists cleanly
    AppSettings settings;
    QCOMPARE(settings.gamescopeDefault(), false);
    settings.setGamescopeDefault(true);
    QVariantMap customGlobal = settings.defaultGamescopeConfig();
    customGlobal[QStringLiteral("windowMode")] = QStringLiteral("borderless");
    customGlobal[QStringLiteral("fpsLimit")] = 60;
    settings.setDefaultGamescopeConfig(customGlobal);

    AppSettings reloadedSettings;
    QCOMPARE(reloadedSettings.gamescopeDefault(), true);
    QCOMPARE(reloadedSettings.defaultGamescopeConfig().value(QStringLiteral("windowMode")).toString(),
             QStringLiteral("borderless"));
    QCOMPARE(reloadedSettings.defaultGamescopeConfig().value(QStringLiteral("fpsLimit")).toInt(), 60);

    reloadedSettings.resetDefaultGamescopeConfig();
    QCOMPARE(reloadedSettings.defaultGamescopeConfig().value(QStringLiteral("windowMode")).toString(),
             QStringLiteral("fullscreen"));
    settings.setGamescopeDefault(false);

    // 3. Create deterministic mock executables in temporary bin dir
    const QString mockBinDir = tmpDir.filePath(QStringLiteral("mock_bin"));
    QVERIFY(QDir().mkpath(mockBinDir));
    auto makeExec = [&](const QString& name) -> QString {
      const QString p = mockBinDir + QLatin1Char('/') + name;
      QFile f(p);
      if (!f.open(QIODevice::WriteOnly)) return QString();
      f.write("#!/bin/sh\nexit 0\n");
      f.close();
      if (!QFile::setPermissions(p, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner |
                                        QFile::ReadGroup | QFile::ExeGroup)) {
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
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr, &diagMgr);
    SteamGridDbService sgdb(&settings, &dl);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    // 4. DiagnosticsManager reports gamescope availability
    QVERIFY(diagMgr.gamescopeAvailable());
    bool foundGsCheck = false;
    for (const QVariant& item : diagMgr.systemChecks()) {
      const QVariantMap m = item.toMap();
      if (m.value(QStringLiteral("name")).toString().contains(QStringLiteral("Gamescope"), Qt::CaseInsensitive)) {
        foundGsCheck = true;
        QCOMPARE(m.value(QStringLiteral("ok")).toBool(), true);
        QVERIFY(m.value(QStringLiteral("detail")).toString().contains(mockGamescope));
      }
    }
    QVERIFY(foundGsCheck);

    // 5. GameManager::updateGameDetails persists ONLY Gamescope changes
    const QString winGameId = gm.addGame(QStringLiteral("Proton Title"), QStringLiteral("/games/win.exe"));
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

    QVERIFY(gm.updateGameDetails(winGameId, QVariantMap{
        {QStringLiteral("gamescopeState"), 1},
        {QStringLiteral("gamescope"), gsMap},
        {QStringLiteral("mangohudState"), 1},
        {QStringLiteral("gamemodeState"), 1},
        {QStringLiteral("virtualDesktop"), true}
    }));

    auto winGameOpt = db.getGame(winGameId);
    QVERIFY(winGameOpt.has_value());
    QCOMPARE(winGameOpt->gamescopeState, 1);
    QCOMPARE(winGameOpt->gamescope.inheritGlobal, false);
    QCOMPARE(winGameOpt->gamescope.filter, QStringLiteral("fsr"));
    QCOMPARE(winGameOpt->gamescope.fsrSharpness, 3);
    QCOMPARE(winGameOpt->gamescope.hdrEnabled, true);

    // 6. LaunchPipeline Wine/Proton plan with Gamescope + MangoApp + GameMode + HDR
    RunnerRecord protonRunner;
    protonRunner.id = QStringLiteral("proton-ge");
    protonRunner.name = QStringLiteral("GE-Proton");
    protonRunner.type = QStringLiteral("proton-ge");
    protonRunner.binaryPath = QStringLiteral("/opt/proton-ge/proton");
    PrefixRecord prefix;
    prefix.id = QStringLiteral("pfx-1");
    prefix.path = tmpDir.filePath(QStringLiteral("pfx"));
    prefix.arch = QStringLiteral("win64");

    const LaunchPlan gsPlan = pipeline.buildLaunchPlan(*winGameOpt, protonRunner, prefix);
    QVERIFY(gsPlan.usesGamescope);
    QCOMPARE(gsPlan.program, mockGamemode);
    QCOMPARE(gsPlan.environment.value(QStringLiteral("DXVK_HDR")), QStringLiteral("1"));
    QVERIFY(!gsPlan.environment.contains(QStringLiteral("MANGOHUD"))); // --mangoapp replaces MANGOHUD=1

    const int gsIdx = gsPlan.arguments.indexOf(mockGamescope);
    const int sepIdx = gsPlan.arguments.indexOf(QStringLiteral("--"));
    const int protonIdx = gsPlan.arguments.indexOf(protonRunner.binaryPath);
    QVERIFY(gsIdx >= 0);
    QVERIFY(sepIdx > gsIdx);
    QVERIFY(protonIdx == sepIdx + 1);
    QVERIFY(gsPlan.arguments.contains(QStringLiteral("--mangoapp")));
    QVERIFY(!gsPlan.arguments.contains(mockMangohud));
    QVERIFY(!gsPlan.arguments.contains(QStringLiteral("explorer"))); // Virtual desktop suppressed under Gamescope
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
    const LaunchPlan extPlan = pipeline.buildLaunchPlan(extMangoGame, protonRunner, prefix);
    QCOMPARE(extPlan.environment.value(QStringLiteral("MANGOHUD")), QStringLiteral("1"));
    QVERIFY(!extPlan.arguments.contains(QStringLiteral("--mangoapp")));
    const int extSep = extPlan.arguments.indexOf(QStringLiteral("--"));
    const int extMango = extPlan.arguments.indexOf(mockMangohud);
    const int extProton = extPlan.arguments.indexOf(protonRunner.binaryPath);
    QVERIFY(extSep >= 0);
    QCOMPARE(extMango, extSep + 1);
    QCOMPARE(extProton, extSep + 2);

    // 7b. Bare '--' in extraArgs is stripped while surrounding flags stay intact
    GameRecord sepStripGame = *winGameOpt;
    sepStripGame.gamescope.extraArgs = QStringLiteral("--rt -- -O \"DP-1\"");
    const LaunchPlan sepStripPlan = pipeline.buildLaunchPlan(sepStripGame, protonRunner, prefix);
    QCOMPARE(sepStripPlan.arguments.count(QStringLiteral("--")), 1);
    const int strippedSepIdx = sepStripPlan.arguments.indexOf(QStringLiteral("--"));
    QVERIFY(strippedSepIdx > sepStripPlan.arguments.indexOf(QStringLiteral("--rt")));
    QVERIFY(strippedSepIdx > sepStripPlan.arguments.indexOf(QStringLiteral("-O")));
    QVERIFY(strippedSepIdx > sepStripPlan.arguments.indexOf(QStringLiteral("DP-1")));

    // 8. Native Linux game inheriting global Gamescope default (-1 & inheritGlobal=true)
    const QString nativeId = gm.addNativeGame(QStringLiteral("Native Game"), nativeGameBin, tmpDir.path(), QStringLiteral("--test-flag"));
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
    QVERIFY(failedSpy.at(0).at(1).toString().contains(QStringLiteral("gamescope"), Qt::CaseInsensitive));
  }

  void testGamescopeQmlUiAndNavigation() {
    QTemporaryDir tmpDir;
    QVERIFY(tmpDir.isValid());

    QSettings rawSettings(QStringLiteral("Tsuki"), QStringLiteral("TsukiLauncher"));
    const bool hadGsDefault = rawSettings.contains(QStringLiteral("performance/gamescope"));
    const QVariant oldGsDefault = rawSettings.value(QStringLiteral("performance/gamescope"));
    const bool hadGsCfg = rawSettings.contains(QStringLiteral("performance/gamescopeConfig"));
    const QVariant oldGsCfg = rawSettings.value(QStringLiteral("performance/gamescopeConfig"));
    auto restore = qScopeGuard([&]() {
      if (hadGsDefault) rawSettings.setValue(QStringLiteral("performance/gamescope"), oldGsDefault);
      else rawSettings.remove(QStringLiteral("performance/gamescope"));
      if (hadGsCfg) rawSettings.setValue(QStringLiteral("performance/gamescopeConfig"), oldGsCfg);
      else rawSettings.remove(QStringLiteral("performance/gamescopeConfig"));
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
    LaunchPipeline pipeline(&db, &settings, &runnerMgr, &prefixMgr, &ctrlMgr, &diagMgr);
    GameManager gm(&db, &settings, &runnerMgr, &prefixMgr, &sgdb, &pipeline);

    const QString gameId = gm.addGame(QStringLiteral("Hollow Knight"), QStringLiteral("/games/hk.exe"));
    QVERIFY(!gameId.isEmpty());

    UiController uiCtrl(&db, &settings, &dl, &runnerMgr, &prefixMgr, &wtMgr,
                        &ctrlMgr, &sgdb, &pipeline, &diagMgr, &gm);

    QQuickWindow win;
    win.resize(1280, 820);

    QQmlEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"), &settings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"), &dl);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"), &uiCtrl);

    // Load SettingsPage and confirm Gamescope rows are present and indexed cleanly
    QQmlComponent settingsComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/pages/SettingsPage.qml")));
    QVERIFY2(settingsComp.errors().isEmpty(), qPrintable(settingsComp.errorString()));
    QScopedPointer<QObject> settingsObj(settingsComp.create());
    QVERIFY(settingsObj != nullptr);
    QVERIFY(settingsObj->findChild<QQuickItem *>(QStringLiteral("gamescopeDefaultRow")) != nullptr);
    QVERIFY(settingsObj->findChild<QQuickItem *>(QStringLiteral("gamescopeDefaultsConfigRow")) != nullptr);

    // Load GameDetailPage and switch to Tab 2 (Performance & Controller)
    QQmlComponent detailComp(
        &engine, resolveQmlUrl(QStringLiteral("src/qml/pages/GameDetailPage.qml")));
    QVERIFY2(detailComp.errors().isEmpty(), qPrintable(detailComp.errorString()));
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

    auto *gsToggle = detailItem->findChild<QQuickItem *>(QStringLiteral("gamescopeToggle"));
    auto *gsCustomizeBtn = detailItem->findChild<QQuickItem *>(QStringLiteral("gamescopeCustomizeBtn"));
    auto *gsDialog = detailObj->findChild<QObject *>(QStringLiteral("gamescopeDialog"));
    QVERIFY(gsToggle != nullptr);
    QVERIFY(gsCustomizeBtn != nullptr);
    QVERIFY(gsDialog != nullptr);

    // Disabled by default -> Customize button stays hidden
    QCOMPARE(gsToggle->property("checked").toBool(), false);
    QCOMPARE(gsCustomizeBtn->isVisible(), false);

    // Activate keyboard nav & toggle Gamescope ON -> Customize button appears & DB persists
    uiCtrl.setKeyboardNavActive(true);
    gsToggle->forceActiveFocus();
    QCoreApplication::processEvents();
    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();

    QCOMPARE(gsToggle->property("checked").toBool(), true);
    QCOMPARE(gsCustomizeBtn->isVisible(), true);
    QCOMPARE(db.getGame(gameId)->gamescopeState, 1);

    // Left D-Pad/arrow moves cleanly onto Customize button; Return opens GamescopeDialog
    QTest::keyClick(&win, Qt::Key_Left);
    QCoreApplication::processEvents();
    QCOMPARE(win.activeFocusItem(), gsCustomizeBtn);

    QTest::keyClick(&win, Qt::Key_Return);
    QCoreApplication::processEvents();
    QTRY_COMPARE(gsDialog->property("visible").toBool(), true);

    QVariant popupOpenVar;
    QVERIFY(QMetaObject::invokeMethod(detailObj.get(), "isAnyPopupOpen",
                                      Q_RETURN_ARG(QVariant, popupOpenVar)));
    QCOMPARE(popupOpenVar.toBool(), true);

    // Verify dialog styling, icons, right-aligned options, and keyboard/gamepad nav inside dialog
    auto *dialogBg = gsDialog->property("background").value<QQuickItem *>();
    QVERIFY(dialogBg != nullptr);
    QCOMPARE(dialogBg->objectName(), QStringLiteral("gamescopeDialogBg"));
    QCOMPARE(dialogBg->property("radius").toDouble(), 12.0);

    auto *presetBtn = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopePresetBorderlessBtn"));
    auto *windowSeg = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeWindowModeSeg"));
    auto *outCombo = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeOutputResCombo"));
    auto *outWField = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeOutputWField"));
    auto *sharpSlider = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeSharpnessSlider"));
    auto *adaptiveToggle = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeAdaptiveSyncToggle"));
    auto *cancelBtn = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeCancelBtn"));
    auto *saveBtn = gsDialog->findChild<QQuickItem *>(QStringLiteral("gamescopeSaveBtn"));
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

    const int virtualJoyIdx = SDL_JoystickAttachVirtual(SDL_JOYSTICK_TYPE_GAMECONTROLLER, 2, 11, 1);
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

      // Keyboard navigation with controller plugged in must still hide gamepad button icons
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
      QCOMPARE(cancelBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-right.svg"));
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/gamepad/gamepad-up.svg"));

      // Mouse navigation hides gamepad icons even while controller stays connected
      QMouseEvent mouseMove(QEvent::MouseMove, QPointF(240, 240), QPointF(240, 240),
                            Qt::NoButton, Qt::NoButton, Qt::NoModifier);
      QCoreApplication::sendEvent(&win, &mouseMove);
      QCoreApplication::processEvents();
      QVERIFY(!uiCtrl.isKeyboardNavActive());
      QVERIFY(!uiCtrl.isGamepadActive());
      QCOMPARE(cancelBtn->property("iconSource").toString(), QString());
      QCOMPARE(saveBtn->property("iconSource").toString(),
               QStringLiteral("qrc:/tsuki_app/icons/actions/check.svg"));

      // Switching back to gamepad restores icons, then keyboard press hides them again
      uiCtrl.setActiveInputType(QStringLiteral("playstation"));
      uiCtrl.setKeyboardNavActive(true);
      QCoreApplication::processEvents();
      QCOMPARE(cancelBtn->property("iconSource").toString(),
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
      QTRY_VERIFY2(qAbs((ctrl->x() + ctrl->width()) - row->width()) < 1.0, name);
    };
    verifyRightAlignedInCol(outCombo, "gamescopeOutputResCombo");
    verifyRightAlignedInCol(adaptiveToggle, "gamescopeAdaptiveSyncToggle");

    QTRY_COMPARE(win.activeFocusItem(), presetBtn);

    // Navigate Down onto M3SegmentedButton (Window Mode) & switch to Borderless via Right arrow
    QTest::keyClick(&win, Qt::Key_Down);
    QCoreApplication::processEvents();
    QCOMPARE(win.activeFocusItem(), windowSeg);
    QTest::keyClick(&win, Qt::Key_Right);
    QCoreApplication::processEvents();
    QCOMPARE(gsDialog->property("windowMode").toString(), QStringLiteral("borderless"));

    // Navigate Down onto Output Resolution combo -> open popup -> Esc closes popup NOT dialog
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

    // Switching presets then selecting "Custom…" keeps custom resolution fields synced (no stale text)
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

    // Apply 720p->1080p FSR preset, verify sharpness slider alignment, Left/Right + Down exits slider, then Save immediately writes to database
    QVERIFY(QMetaObject::invokeMethod(gsDialog, "applyPreset", Q_ARG(QVariant, QVariant(QStringLiteral("fsr720")))));
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

    // Re-open dialog and verify gamepad Y button saves and closes via searchActionRequested
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
};

QTEST_MAIN(TestTsuki)
#include "test_tsuki.moc"
