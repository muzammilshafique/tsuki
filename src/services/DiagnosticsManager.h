#pragma once

#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "RunnerManager.h"
#include "PrefixManager.h"
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QMap>

namespace Tsuki {

class DiagnosticsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList systemChecks READ systemChecks NOTIFY systemChecksChanged)
    Q_PROPERTY(bool gamescopeAvailable READ gamescopeAvailable NOTIFY systemChecksChanged)
    Q_PROPERTY(QString activeGameLog READ activeGameLog NOTIFY activeGameLogChanged)
    Q_PROPERTY(QString selectedLogGameId READ selectedLogGameId WRITE setSelectedLogGameId NOTIFY activeGameLogChanged)
    Q_PROPERTY(QVariantList detectedIssues READ detectedIssues NOTIFY detectedIssuesChanged)

public:
    explicit DiagnosticsManager(DatabaseManager* db,
                                AppSettings* settings,
                                RunnerManager* runnerMgr,
                                PrefixManager* prefixMgr,
                                QObject* parent = nullptr);

    QVariantList systemChecks() const { return m_systemChecks; }
    bool gamescopeAvailable() const { return m_gamescopeAvailable; }
    QString activeGameLog() const;
    QString selectedLogGameId() const { return m_selectedLogGameId; }
    void setSelectedLogGameId(const QString& gameId);
    QVariantList detectedIssues() const { return m_detectedIssues; }

    void startNewGameLog(const QString& gameId, const QString& headerInfo);
    void appendGameLog(const QString& gameId, const QString& text);
    QVariantMap analyzeGameLogForErrors(const QString& gameId, int exitCode);

    Q_INVOKABLE void runSystemDiagnostics();
    Q_INVOKABLE QVariantMap diagnosePrefix(const QString& prefixId) const;
    Q_INVOKABLE bool repairPrefix(const QString& prefixId);
    Q_INVOKABLE QString getGameLogText(const QString& gameId) const;
    Q_INVOKABLE bool exportGameLog(const QString& gameId, const QString& destinationPath) const;
    Q_INVOKABLE void clearGameLog(const QString& gameId);

signals:
    void systemChecksChanged();
    void activeGameLogChanged();
    void detectedIssuesChanged();
    void launchErrorDiagnosed(const QString& gameId, const QString& gameTitle, const QString& summary, const QString& recommendation);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    PrefixManager* m_prefixMgr;

    QVariantList m_systemChecks;
    bool m_gamescopeAvailable = false;
    QVariantList m_detectedIssues;
    QString m_selectedLogGameId;
    QMap<QString, QString> m_inMemoryLogs;

    static QString logFilePathForGame(const QString& gameId);
};

} // namespace Tsuki

