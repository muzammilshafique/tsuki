#include "core/AppSettings.h"
#include "core/DatabaseManager.h"
#include "services/DownloadManager.h"
#include "services/RunnerManager.h"
#include "services/PrefixManager.h"
#include "services/WinetricksManager.h"
#include "services/ControllerManager.h"
#include "services/SteamGridDbService.h"
#include "services/LaunchPipeline.h"
#include "services/DiagnosticsManager.h"
#include "services/GameManager.h"
#include "ui/UiController.h"

#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QCommandLineParser>
#include <QIcon>
#include <QTimer>

int main(int argc, char* argv[]) {
    QApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("Tsuki"));
    app.setApplicationName(QStringLiteral("TsukiLauncher"));
    app.setApplicationDisplayName(QStringLiteral("Tsuki"));
    app.setApplicationVersion(QStringLiteral("1.0.0"));
    app.setWindowIcon(QIcon(QStringLiteral(":/tsuki_app/icons/brand/tsuki.svg")));

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Tsuki — Native Linux Game Launcher (Wine & Proton)"));
    parser.addHelpOption();
    parser.addVersionOption();

    QCommandLineOption launchOption(
        {QStringLiteral("l"), QStringLiteral("launch")},
        QStringLiteral("Launch a game directly by its ID (used by desktop shortcuts)."),
        QStringLiteral("gameId"));
    QCommandLineOption smokeTestOption(
        QStringLiteral("smoke-test"),
        QStringLiteral("Initialize QML engine and exit cleanly after 400ms for CI verification."));
    parser.addOption(launchOption);
    parser.addOption(smokeTestOption);
    parser.process(app);

    Tsuki::AppSettings appSettings;
    Tsuki::DatabaseManager dbManager;
    dbManager.initialize();

    Tsuki::DownloadManager downloadManager;
    Tsuki::RunnerManager runnerManager(&dbManager, &appSettings, &downloadManager);
    Tsuki::PrefixManager prefixManager(&dbManager, &appSettings, &runnerManager);
    Tsuki::WinetricksManager winetricksManager(&dbManager, &appSettings, &runnerManager, &downloadManager);
    Tsuki::ControllerManager controllerManager(&dbManager, &appSettings);
    Tsuki::SteamGridDbService steamGridDbService(&appSettings, &downloadManager);
    Tsuki::DiagnosticsManager diagnosticsManager(&dbManager, &appSettings, &runnerManager, &prefixManager);
    Tsuki::LaunchPipeline launchPipeline(&dbManager, &appSettings, &runnerManager, &prefixManager, &controllerManager, &diagnosticsManager);
    Tsuki::GameManager gameManager(&dbManager, &appSettings, &runnerManager, &prefixManager, &steamGridDbService, &launchPipeline);
    Tsuki::UiController uiController(&dbManager,
                                     &appSettings,
                                     &downloadManager,
                                     &runnerManager,
                                     &prefixManager,
                                     &winetricksManager,
                                     &controllerManager,
                                     &steamGridDbService,
                                     &launchPipeline,
                                     &diagnosticsManager,
                                     &gameManager);

    if (parser.isSet(launchOption)) {
        const QString gameId = parser.value(launchOption).trimmed();
        QObject::connect(&launchPipeline, &Tsuki::LaunchPipeline::gameStopped, &app, &QGuiApplication::quit);
        QObject::connect(&launchPipeline, &Tsuki::LaunchPipeline::gameLaunchFailed, &app, &QGuiApplication::quit);
        QTimer::singleShot(0, [&launchPipeline, gameId]() {
            launchPipeline.launchGame(gameId);
        });
        return app.exec();
    }

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("appSettings"), &appSettings);
    engine.rootContext()->setContextProperty(QStringLiteral("downloadManager"), &downloadManager);
    engine.rootContext()->setContextProperty(QStringLiteral("uiController"), &uiController);

    const QUrl url(QStringLiteral("qrc:/tsuki_app/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app,
        [url](QObject* obj, const QUrl& objUrl) {
            if (!obj && url == objUrl) {
                QCoreApplication::exit(-1);
            }
        }, Qt::QueuedConnection);

    engine.load(url);

    if (parser.isSet(smokeTestOption)) {
        QTimer::singleShot(400, &app, &QGuiApplication::quit);
    }

    return app.exec();
}

