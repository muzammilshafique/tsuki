#pragma once

#include "../core/AppSettings.h"
#include "../core/DatabaseManager.h"
#include "../services/DownloadManager.h"
#include "../services/RunnerManager.h"
#include "../services/PrefixManager.h"
#include "../services/WinetricksManager.h"
#include "../services/ControllerManager.h"
#include "../services/SteamGridDbService.h"
#include "../services/LaunchPipeline.h"
#include "../services/DiagnosticsManager.h"
#include "../services/GameManager.h"
#include <QObject>
#include <QPoint>
#include <QVariant>

namespace Tsuki {

class UiController : public QObject {
    Q_OBJECT

    // Yoru UI Reference Compatible Properties
    Q_PROPERTY(bool isKeyboardNavActive READ isKeyboardNavActive WRITE setKeyboardNavActive NOTIFY keyboardNavActiveChanged)
    Q_PROPERTY(QString activeInputType READ activeInputType WRITE setActiveInputType NOTIFY activeInputTypeChanged)
    Q_PROPERTY(bool isGamepadActive READ isGamepadActive NOTIFY activeInputTypeChanged)
    Q_PROPERTY(Tsuki::GameListModel* searchModel READ searchModel CONSTANT)
    Q_PROPERTY(Tsuki::ControllerManager* gamepad READ gamepad CONSTANT)

    // Tsuki Modular Services
    Q_PROPERTY(Tsuki::DownloadManager* downloadManager READ downloadManager CONSTANT)
    Q_PROPERTY(Tsuki::GameManager* gameManager READ gameManager CONSTANT)
    Q_PROPERTY(Tsuki::RunnerManager* runnerManager READ runnerManager CONSTANT)
    Q_PROPERTY(Tsuki::PrefixManager* prefixManager READ prefixManager CONSTANT)
    Q_PROPERTY(Tsuki::WinetricksManager* winetricksManager READ winetricksManager CONSTANT)
    Q_PROPERTY(Tsuki::ControllerManager* controllerManager READ controllerManager CONSTANT)
    Q_PROPERTY(Tsuki::LaunchPipeline* launchPipeline READ launchPipeline CONSTANT)
    Q_PROPERTY(Tsuki::DiagnosticsManager* diagnosticsManager READ diagnosticsManager CONSTANT)
    Q_PROPERTY(Tsuki::SteamGridDbService* steamGridDb READ steamGridDb CONSTANT)

public:
    explicit UiController(DatabaseManager* db,
                          AppSettings* settings,
                          DownloadManager* dl,
                          RunnerManager* runnerMgr,
                          PrefixManager* prefixMgr,
                          WinetricksManager* wtMgr,
                          ControllerManager* ctrlMgr,
                          SteamGridDbService* sgdb,
                          LaunchPipeline* launchPipeline,
                          DiagnosticsManager* diagMgr,
                          GameManager* gameMgr,
                          QObject* parent = nullptr);
    ~UiController() override;

    bool isKeyboardNavActive() const { return m_isKeyboardNavActive; }
    Q_INVOKABLE void setKeyboardNavActive(bool active);

    QString activeInputType() const { return m_activeInputType; }
    bool isGamepadActive() const { return m_activeInputType == QLatin1String("playstation") || m_activeInputType == QLatin1String("xbox"); }
    Q_INVOKABLE void setActiveInputType(const QString& inputType);

    GameListModel* searchModel() const { return m_gameMgr->model(); }
    ControllerManager* gamepad() const { return m_ctrlMgr; }

    DownloadManager* downloadManager() const { return m_dl; }
    GameManager* gameManager() const { return m_gameMgr; }
    RunnerManager* runnerManager() const { return m_runnerMgr; }
    PrefixManager* prefixManager() const { return m_prefixMgr; }
    WinetricksManager* winetricksManager() const { return m_wtMgr; }
    ControllerManager* controllerManager() const { return m_ctrlMgr; }
    LaunchPipeline* launchPipeline() const { return m_launchPipeline; }
    DiagnosticsManager* diagnosticsManager() const { return m_diagMgr; }
    SteamGridDbService* steamGridDb() const { return m_sgdb; }

    // Native System File & Folder Selectors
    Q_INVOKABLE QString selectFile(const QString& title = QString(), const QString& filter = QString(), const QString& initialPath = QString());
    Q_INVOKABLE QString selectFolder(const QString& title = QString(), const QString& initialPath = QString());

    // Yoru-compatible search & card actions
    Q_INVOKABLE void search(const QString& query, int filterType = -1);
    Q_INVOKABLE void loadFavorites();
    Q_INVOKABLE void loadDownloads();
    Q_INVOKABLE void loadRecentMedia();
    Q_INVOKABLE void togglePin(const QString& gameId);
    Q_INVOKABLE void toggleFavorite(const QVariant& itemOrId);
    Q_INVOKABLE void removeRecent(const QString& gameId);

signals:
    void keyboardNavActiveChanged();
    void activeInputTypeChanged();
    void searchStateChanged(bool loading, const QString& error);
    void toastRequested(const QString& message, bool isError);

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    DownloadManager* m_dl;
    RunnerManager* m_runnerMgr;
    PrefixManager* m_prefixMgr;
    WinetricksManager* m_wtMgr;
    ControllerManager* m_ctrlMgr;
    SteamGridDbService* m_sgdb;
    LaunchPipeline* m_launchPipeline;
    DiagnosticsManager* m_diagMgr;
    GameManager* m_gameMgr;

    bool m_isKeyboardNavActive = false;
    bool m_cursorHidden = false;
    QString m_activeInputType = QStringLiteral("keyboard");
    QPoint m_lastMousePos;
    bool m_hasLastMousePos = false;

    void updateCursorVisibility(bool hide);
};

} // namespace Tsuki

