#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "DownloadManager.h"
#include <QHash>
#include <QObject>
#include <QNetworkAccessManager>
#include <QVariantList>

namespace Tsuki {

class RunnerManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList installedRunners READ installedRunnersVariant NOTIFY runnersChanged)
    Q_PROPERTY(QVariantList availableReleases READ availableReleases NOTIFY availableReleasesChanged)
    Q_PROPERTY(bool isFetchingReleases READ isFetchingReleases NOTIFY isFetchingReleasesChanged)
    Q_PROPERTY(QString eacRuntimePath READ eacRuntimePath NOTIFY antiCheatRuntimesChanged)
    Q_PROPERTY(QString battleyeRuntimePath READ battleyeRuntimePath NOTIFY antiCheatRuntimesChanged)
    Q_PROPERTY(bool eacRuntimeAvailable READ eacRuntimeAvailable NOTIFY antiCheatRuntimesChanged)
    Q_PROPERTY(bool battleyeRuntimeAvailable READ battleyeRuntimeAvailable NOTIFY antiCheatRuntimesChanged)
    Q_PROPERTY(bool isInstallingEac READ isInstallingEac NOTIFY antiCheatRuntimesChanged)
    Q_PROPERTY(bool isInstallingBattleye READ isInstallingBattleye NOTIFY antiCheatRuntimesChanged)

public:
    explicit RunnerManager(DatabaseManager* db, AppSettings* settings, DownloadManager* dl, QObject* parent = nullptr);

    QVariantList installedRunnersVariant() const;
    QList<RunnerRecord> installedRunners() const;
    QVariantList availableReleases() const { return m_availableReleases; }
    bool isFetchingReleases() const { return m_isFetchingReleases; }

    std::optional<RunnerRecord> resolveRunner(const QString& preferredRunnerId) const;
    QString runnerTagForId(const QString& runnerId) const;
    QString findWineBinaryForRunner(const RunnerRecord& runner) const;
    QString findWineserverBinaryForRunner(const RunnerRecord& runner) const;

    QStringList findDxvkDirectories() const;
    QStringList findVkd3dDirectories() const;

    // Proton Anti-Cheat Runtimes (EAC & BattlEye)
    static QString resolveEacRuntimePath();
    static QString resolveBattlEyeRuntimePath();
    static QString ensureSpaceSafeRuntimePath(const QString& runtimeDir, const QString& linkName);
    QString eacRuntimePath() const { return resolveEacRuntimePath(); }
    QString battleyeRuntimePath() const { return resolveBattlEyeRuntimePath(); }
    bool eacRuntimeAvailable() const { return !resolveEacRuntimePath().isEmpty(); }
    bool battleyeRuntimeAvailable() const { return !resolveBattlEyeRuntimePath().isEmpty(); }
    bool isInstallingEac() const { return m_isInstallingEac; }
    bool isInstallingBattleye() const { return m_isInstallingBattleye; }

    Q_INVOKABLE void installAntiCheatRuntime(const QString& runtimeName);
    Q_INVOKABLE bool removeAntiCheatRuntime(const QString& runtimeName);

    Q_INVOKABLE void detectInstalledRunners();
    Q_INVOKABLE void fetchAvailableReleases(const QString& category = QStringLiteral("proton-ge"),
                                            bool forceRefresh = false);
    Q_INVOKABLE void downloadRelease(const QString& category,
                                     const QString& tagName,
                                     const QString& downloadUrl,
                                     const QString& fileName = QString());
    Q_INVOKABLE void downloadAndInstallRunner(const QString& tagName,
                                              const QString& category,
                                              const QString& downloadUrl,
                                              const QString& fileName);
    Q_INVOKABLE bool removeRunner(const QString& runnerId, bool deleteFiles = false);
    Q_INVOKABLE bool uninstallRunner(const QString& runnerId);
    Q_INVOKABLE bool updateRunnerSettings(const QString& runnerId, const QVariantMap& settings);
    Q_INVOKABLE QVariantMap getRunnerMap(const QString& runnerId) const;

signals:
    void runnersChanged();
    void availableReleasesChanged();
    void isFetchingReleasesChanged();
    void antiCheatRuntimesChanged();
    void runnerOperationStatus(const QString& message, bool isError);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    DownloadManager* m_dl;
    QNetworkAccessManager m_nam;
    QVariantList m_availableReleases;
    QHash<QString, QVariantList> m_releaseCache;
    QHash<QString, qint64> m_releaseCacheTimeMs;
    QString m_activeReleaseCategory = QStringLiteral("proton-ge");
    bool m_isFetchingReleases = false;
    bool m_isInstallingEac = false;
    bool m_isInstallingBattleye = false;

    void inspectAndRegisterRunnerDir(const QString& dirPath, bool isSystemDir = false, const QString& sourceLabel = QString());
    void scanSteamRunners();
    void populateFallbackReleases(const QString& category);
    bool isReleaseInstalled(const QString& tagName, const QString& name) const;
};

} // namespace Tsuki

