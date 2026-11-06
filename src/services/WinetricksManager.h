#pragma once

#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "RunnerManager.h"
#include "DownloadManager.h"
#include <QObject>
#include <QVariantList>
#include <QProcess>

namespace Tsuki {

class WinetricksManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList catalog READ catalog NOTIFY catalogChanged)
    Q_PROPERTY(bool isRunning READ isRunning NOTIFY runningChanged)
    Q_PROPERTY(QString currentVerb READ currentVerb NOTIFY runningChanged)
    Q_PROPERTY(QString liveOutput READ liveOutput NOTIFY liveOutputChanged)
    Q_PROPERTY(QString winetricksBinaryPath READ winetricksBinaryPath NOTIFY binaryChanged)

public:
    explicit WinetricksManager(DatabaseManager* db,
                               AppSettings* settings,
                               RunnerManager* runnerMgr,
                               DownloadManager* dl,
                               QObject* parent = nullptr);

    QVariantList catalog() const { return m_catalog; }
    bool isRunning() const { return m_activeProcess != nullptr; }
    QString currentVerb() const { return m_currentVerb; }
    QString liveOutput() const { return m_liveOutput; }
    QString winetricksBinaryPath() const { return m_winetricksPath; }

    Q_INVOKABLE QVariantList filterCatalog(const QString& category, const QString& searchQuery, const QString& prefixId = QString()) const;
    Q_INVOKABLE void installVerb(const QString& prefixId, const QString& verb);
    Q_INVOKABLE void removeComponent(const QString& prefixId, const QString& verb);
    Q_INVOKABLE void launchWinetricksGui(const QString& prefixId);
    Q_INVOKABLE void cancelCurrentOperation();
    Q_INVOKABLE void clearLiveOutput();
    Q_INVOKABLE void ensureWinetricksAvailable();

signals:
    void catalogChanged();
    void runningChanged();
    void liveOutputChanged();
    void binaryChanged();
    void verbFinished(const QString& prefixId, const QString& verb, bool success, const QString& summary);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    DownloadManager* m_dl;

    QString m_winetricksPath;
    QVariantList m_catalog;
    QProcess* m_activeProcess = nullptr;
    QString m_currentVerb;
    QString m_liveOutput;

    void populateBuiltInCatalog();
    void appendLog(const QString& text);
    QStringList readInstalledLog(const QString& prefixPath) const;
};

} // namespace Tsuki

