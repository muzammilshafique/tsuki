#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "RunnerManager.h"
#include "PrefixManager.h"
#include "ControllerManager.h"
#include "DiagnosticsManager.h"
#include <QObject>
#include <QProcess>
#include <QMap>
#include <QStringList>

namespace Tsuki {

struct LaunchPlan {
    QString program;
    QStringList arguments;
    QString workingDirectory;
    QProcessEnvironment environment;
    QString prefixPath;
    QString runnerName;
    bool useXboxEmulation = false;
    QString controllerProfileId;
};

class LaunchPipeline : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList runningGameIds READ runningGameIds NOTIFY runningGamesChanged)
    Q_PROPERTY(int runningCount READ runningCount NOTIFY runningGamesChanged)

public:
    explicit LaunchPipeline(DatabaseManager* db,
                            AppSettings* settings,
                            RunnerManager* runnerMgr,
                            PrefixManager* prefixMgr,
                            ControllerManager* controllerMgr,
                            DiagnosticsManager* diagMgr,
                            QObject* parent = nullptr);
    ~LaunchPipeline() override;

    QStringList runningGameIds() const { return m_running.keys(); }
    int runningCount() const { return m_running.size(); }
    Q_INVOKABLE bool isGameRunning(const QString& gameId) const { return m_running.contains(gameId); }

    // Build launch plan (testable without spawning processes)
    LaunchPlan buildLaunchPlan(const GameRecord& game,
                               const RunnerRecord& runner,
                               const PrefixRecord& prefix) const;

    Q_INVOKABLE bool launchGame(const QString& gameId);
    Q_INVOKABLE void stopGame(const QString& gameId);
    Q_INVOKABLE void stopAllGames();

signals:
    void runningGamesChanged();
    void gameStarted(const QString& gameId, const QString& title);
    void gameStopped(const QString& gameId, int exitCode, qint64 sessionSeconds);
    void gameLaunchFailed(const QString& gameId, const QString& reason);

private:
    struct RunningSession {
        QString gameId;
        QString title;
        QString prefixPath;
        QString runnerId;
        QString postExitScript;
        qint64 startTimeEpoch = 0;
        QProcess* process = nullptr;
    };

    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    PrefixManager* m_prefixMgr;
    ControllerManager* m_controllerMgr;
    DiagnosticsManager* m_diagMgr;

    QMap<QString, RunningSession*> m_running;

    void executeScript(const QString& scriptPathOrCmd, const QString& workingDir, const QProcessEnvironment& env, const QString& gameId);
};

} // namespace Tsuki

