#pragma once

#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "RunnerManager.h"
#include "PrefixManager.h"
#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QMap>
#include <optional>

namespace Tsuki {

class DiagnosticsManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList systemChecks READ systemChecks NOTIFY systemChecksChanged)
    Q_PROPERTY(bool gamescopeAvailable READ gamescopeAvailable NOTIFY systemChecksChanged)
    Q_PROPERTY(bool ntsyncAvailable READ ntsyncAvailable NOTIFY systemChecksChanged)
    Q_PROPERTY(QVariantList detectedGpus READ detectedGpus NOTIFY detectedGpusChanged)
    Q_PROPERTY(QString activeGameLog READ activeGameLog NOTIFY activeGameLogChanged)
    Q_PROPERTY(QString selectedLogGameId READ selectedLogGameId WRITE setSelectedLogGameId NOTIFY activeGameLogChanged)
    Q_PROPERTY(QVariantList detectedIssues READ detectedIssues NOTIFY detectedIssuesChanged)

public:
    struct GpuInfo {
        QString id;           // Stable identifier (e.g. "card0" or Vulkan device name)
        QString name;         // Human-readable name (e.g. "NVIDIA GeForce RTX 4070")
        QString vendor;       // "nvidia", "amd", "intel", "unknown"
        QString pciVendorId;  // e.g. "0x10de"
        QString pciDeviceId;  // e.g. "0x2786"
        int driPrimeIndex = 0;
        bool isDiscrete = false;

        QVariantMap toVariantMap() const {
            QVariantMap m;
            m[QStringLiteral("id")] = id;
            m[QStringLiteral("name")] = name;
            m[QStringLiteral("vendor")] = vendor;
            m[QStringLiteral("pciVendorId")] = pciVendorId;
            m[QStringLiteral("pciDeviceId")] = pciDeviceId;
            m[QStringLiteral("driPrimeIndex")] = driPrimeIndex;
            m[QStringLiteral("isDiscrete")] = isDiscrete;
            return m;
        }
    };

    explicit DiagnosticsManager(DatabaseManager* db,
                                AppSettings* settings,
                                RunnerManager* runnerMgr,
                                PrefixManager* prefixMgr,
                                QObject* parent = nullptr);

    QVariantList systemChecks() const { return m_systemChecks; }
    bool gamescopeAvailable() const { return m_gamescopeAvailable; }
    bool ntsyncAvailable() const { return m_ntsyncAvailable; }
    QVariantList detectedGpus() const;
    QList<GpuInfo> gpuList() const { return m_gpus; }
    std::optional<GpuInfo> findGpu(const QString& gpuSelection) const;
    QString activeGameLog() const;
    QString selectedLogGameId() const { return m_selectedLogGameId; }
    void setSelectedLogGameId(const QString& gameId);
    QVariantList detectedIssues() const { return m_detectedIssues; }

    void startNewGameLog(const QString& gameId, const QString& headerInfo);
    void appendGameLog(const QString& gameId, const QString& text);
    QVariantMap analyzeGameLogForErrors(const QString& gameId, int exitCode);

    Q_INVOKABLE void runSystemDiagnostics();
    Q_INVOKABLE void refreshDetectedGpus();
    Q_INVOKABLE QVariantMap diagnosePrefix(const QString& prefixId) const;
    Q_INVOKABLE bool repairPrefix(const QString& prefixId);
    Q_INVOKABLE QString getGameLogText(const QString& gameId) const;
    Q_INVOKABLE bool exportGameLog(const QString& gameId, const QString& destinationPath) const;
    Q_INVOKABLE void clearGameLog(const QString& gameId);
    int clearInactiveGameLogs(const QSet<QString>& runningGameIds, qint64* freedBytesOut = nullptr);

signals:
    void systemChecksChanged();
    void detectedGpusChanged();
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
    bool m_ntsyncAvailable = false;
    QList<GpuInfo> m_gpus;
    QVariantList m_detectedIssues;
    QString m_selectedLogGameId;
    QMap<QString, QString> m_inMemoryLogs;

    static QString logFilePathForGame(const QString& gameId);
    static QList<GpuInfo> enumerateSysfsGpus();
};

} // namespace Tsuki

