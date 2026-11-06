#include "UiController.h"
#include <QFileDialog>
#include <QDir>

namespace Tsuki {

UiController::UiController(DatabaseManager* db,
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
                           QObject* parent)
    : QObject(parent)
    , m_db(db)
    , m_settings(settings)
    , m_dl(dl)
    , m_runnerMgr(runnerMgr)
    , m_prefixMgr(prefixMgr)
    , m_wtMgr(wtMgr)
    , m_ctrlMgr(ctrlMgr)
    , m_sgdb(sgdb)
    , m_launchPipeline(launchPipeline)
    , m_diagMgr(diagMgr)
    , m_gameMgr(gameMgr)
{
    connect(m_ctrlMgr, &ControllerManager::uiKeySimulated, this, [this]() {
        setKeyboardNavActive(true);
    });
    connect(m_gameMgr, &GameManager::gameOperationStatus, this, &UiController::toastRequested);
    connect(m_runnerMgr, &RunnerManager::runnerOperationStatus, this, &UiController::toastRequested);
    connect(m_prefixMgr, &PrefixManager::prefixOperationFinished, this, [this](const QString&, bool ok, const QString& msg) {
        emit toastRequested(msg, !ok);
    });
    connect(m_wtMgr, &WinetricksManager::verbFinished, this, [this](const QString&, const QString&, bool ok, const QString& msg) {
        emit toastRequested(msg, !ok);
    });
    connect(m_launchPipeline, &LaunchPipeline::gameLaunchFailed, this, [this](const QString&, const QString& reason) {
        emit toastRequested(reason, true);
    });
    connect(m_launchPipeline, &LaunchPipeline::gameStarted, this, [this](const QString&, const QString& title) {
        emit toastRequested(QStringLiteral("Launching %1…").arg(title), false);
    });
    connect(m_diagMgr, &DiagnosticsManager::launchErrorDiagnosed, this,
            [this](const QString&, const QString& title, const QString& summary, const QString& rec) {
                emit toastRequested(QStringLiteral("%1: %2 — %3").arg(title, summary, rec), true);
            });
}

void UiController::setKeyboardNavActive(bool active) {
    if (m_isKeyboardNavActive == active) return;
    m_isKeyboardNavActive = active;
    emit keyboardNavActiveChanged();
}

void UiController::search(const QString& query, int filterType) {
    m_gameMgr->model()->setFilterType(filterType);
    m_gameMgr->model()->setSearchQuery(query);
    emit searchStateChanged(false, QString());
}

void UiController::loadFavorites() {
    m_gameMgr->model()->setFilterType(3);
}

void UiController::loadDownloads() {
    m_gameMgr->model()->setFilterType(4);
}

void UiController::loadRecentMedia() {
    m_gameMgr->model()->reload();
}

void UiController::togglePin(const QString& gameId) {
    m_gameMgr->togglePin(gameId);
}

void UiController::toggleFavorite(const QVariant& itemOrId) {
    if (itemOrId.typeId() == QMetaType::QString) {
        m_gameMgr->toggleFavorite(itemOrId.toString());
    } else if (itemOrId.canConvert<QVariantMap>()) {
        const QVariantMap m = itemOrId.toMap();
        const QString id = m.value(QStringLiteral("id"), m.value(QStringLiteral("tmdbId"))).toString();
        if (!id.isEmpty()) {
            m_gameMgr->toggleFavorite(id);
        }
    }
}

void UiController::removeRecent(const QString& gameId) {
    m_gameMgr->removeGame(gameId, false);
}

QString UiController::selectFile(const QString& title, const QString& filter, const QString& initialPath) {
    const QString dlgTitle = title.isEmpty() ? QStringLiteral("Select File") : title;
    const QString startDir = initialPath.isEmpty() ? QDir::homePath() : initialPath;
    const QString selected = QFileDialog::getOpenFileName(nullptr, dlgTitle, startDir, filter);
    return selected;
}

QString UiController::selectFolder(const QString& title, const QString& initialPath) {
    const QString dlgTitle = title.isEmpty() ? QStringLiteral("Select Folder") : title;
    const QString startDir = initialPath.isEmpty() ? QDir::homePath() : initialPath;
    const QString selected = QFileDialog::getExistingDirectory(nullptr, dlgTitle, startDir, QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks);
    return selected;
}

} // namespace Tsuki

