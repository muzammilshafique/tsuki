#include "UiController.h"
#include <QCoreApplication>
#include <QCursor>
#include <QFileDialog>
#include <QDir>
#include <QEvent>
#include <QGuiApplication>
#include <QKeyEvent>
#include <QMouseEvent>

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
    , m_activeInputType((ctrlMgr && ctrlMgr->isConnected()) ? ctrlMgr->controllerType() : QStringLiteral("keyboard"))
{
    if (QCoreApplication::instance()) {
        QCoreApplication::instance()->installEventFilter(this);
    }

    if (m_ctrlMgr) {
        connect(m_ctrlMgr, &ControllerManager::uiKeySimulated, this, [this]() {
            setActiveInputType(m_ctrlMgr->controllerType());
            setKeyboardNavActive(true);
        });
        connect(m_ctrlMgr, &ControllerManager::gamepadInputReceived, this, [this](const QString& type) {
            setActiveInputType(type);
            setKeyboardNavActive(true);
        });
        connect(m_ctrlMgr, &ControllerManager::controllersChanged, this, [this]() {
            if (isGamepadActive()) {
                if (m_ctrlMgr->isConnected()) {
                    setActiveInputType(m_ctrlMgr->controllerType());
                } else {
                    setActiveInputType(QStringLiteral("keyboard"));
                }
            }
        });
    }
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
        setKeyboardNavActive(false);
        emit toastRequested(QStringLiteral("Launching %1…").arg(title), false);
    });
    connect(m_diagMgr, &DiagnosticsManager::launchErrorDiagnosed, this,
            [this](const QString&, const QString& title, const QString& summary, const QString& rec) {
                emit toastRequested(QStringLiteral("%1: %2 — %3").arg(title, summary, rec), true);
            });
}

UiController::~UiController() {
    updateCursorVisibility(false);
}

void UiController::updateCursorVisibility(bool hide) {
    if (hide && !m_cursorHidden) {
        QGuiApplication::setOverrideCursor(Qt::BlankCursor);
        m_cursorHidden = true;
    } else if (!hide && m_cursorHidden) {
        QGuiApplication::restoreOverrideCursor();
        m_cursorHidden = false;
    }
}

void UiController::setKeyboardNavActive(bool active) {
    if (m_isKeyboardNavActive == active) return;
    m_isKeyboardNavActive = active;
    updateCursorVisibility(active);
    emit keyboardNavActiveChanged();
}

void UiController::setActiveInputType(const QString& inputType) {
    const QString normalized = (inputType == QLatin1String("playstation") || inputType == QLatin1String("xbox"))
        ? inputType
        : QStringLiteral("keyboard");
    if (m_activeInputType == normalized) return;
    m_activeInputType = normalized;
    emit activeInputTypeChanged();
}

bool UiController::eventFilter(QObject* watched, QEvent* event) {
    if (event->type() == QEvent::KeyPress) {
        if (m_ctrlMgr && m_ctrlMgr->isSendingSyntheticKey()) {
            setActiveInputType(m_ctrlMgr->controllerType());
            setKeyboardNavActive(true);
        } else {
            auto* ke = static_cast<QKeyEvent*>(event);
            switch (ke->key()) {
                case Qt::Key_Shift:
                case Qt::Key_Control:
                case Qt::Key_Alt:
                case Qt::Key_Meta:
                case Qt::Key_CapsLock:
                    break;
                case Qt::Key_Up:
                case Qt::Key_Down:
                case Qt::Key_Left:
                case Qt::Key_Right:
                case Qt::Key_Tab:
                case Qt::Key_Backtab:
                case Qt::Key_Return:
                case Qt::Key_Enter:
                case Qt::Key_Space:
                case Qt::Key_Escape:
                case Qt::Key_Backspace:
                case Qt::Key_PageUp:
                case Qt::Key_PageDown:
                case Qt::Key_Slash:
                case Qt::Key_BracketLeft:
                case Qt::Key_BracketRight:
                    setActiveInputType(QStringLiteral("keyboard"));
                    setKeyboardNavActive(true);
                    break;
                default:
                    setActiveInputType(QStringLiteral("keyboard"));
                    break;
            }
        }
    } else if (event->type() == QEvent::MouseButtonPress || event->type() == QEvent::Wheel) {
        setActiveInputType(QStringLiteral("keyboard"));
        setKeyboardNavActive(false);
    } else if (event->type() == QEvent::MouseMove) {
        auto* me = static_cast<QMouseEvent*>(event);
        const QPoint pos = me->globalPosition().toPoint();
        if (!m_hasLastMousePos || (pos - m_lastMousePos).manhattanLength() >= 2) {
            m_lastMousePos = pos;
            m_hasLastMousePos = true;
            setActiveInputType(QStringLiteral("keyboard"));
            setKeyboardNavActive(false);
        }
    } else if (event->type() == QEvent::ApplicationDeactivate || event->type() == QEvent::WindowDeactivate) {
        updateCursorVisibility(false);
    }
    return QObject::eventFilter(watched, event);
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
    updateCursorVisibility(false);
    const QString dlgTitle = title.isEmpty() ? QStringLiteral("Select File") : title;
    const QString startDir = initialPath.isEmpty() ? QDir::homePath() : initialPath;
    const QString selected = QFileDialog::getOpenFileName(nullptr, dlgTitle, startDir, filter);
    return selected;
}

QString UiController::selectFolder(const QString& title, const QString& initialPath) {
    updateCursorVisibility(false);
    const QString dlgTitle = title.isEmpty() ? QStringLiteral("Select Folder") : title;
    const QString startDir = initialPath.isEmpty() ? QDir::homePath() : initialPath;
    const QString selected = QFileDialog::getExistingDirectory(nullptr, dlgTitle, startDir, QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks);
    return selected;
}

} // namespace Tsuki

