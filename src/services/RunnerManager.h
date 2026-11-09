#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "DownloadManager.h"
#include <QObject>
#include <QNetworkAccessManager>
#include <QVariantList>

namespace Tsuki {

class RunnerManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList installedRunners READ installedRunnersVariant NOTIFY runnersChanged)
    Q_PROPERTY(QVariantList availableReleases READ availableReleases NOTIFY availableReleasesChanged)
    Q_PROPERTY(bool isFetchingReleases READ isFetchingReleases NOTIFY isFetchingReleasesChanged)

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

    Q_INVOKABLE void detectInstalledRunners();
    Q_INVOKABLE void fetchAvailableReleases(const QString& category = QStringLiteral("proton-ge"));
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
    void runnerOperationStatus(const QString& message, bool isError);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    DownloadManager* m_dl;
    QNetworkAccessManager m_nam;
    QVariantList m_availableReleases;
    bool m_isFetchingReleases = false;

    void inspectAndRegisterRunnerDir(const QString& dirPath, bool isSystemDir = false, const QString& sourceLabel = QString());
    void scanSteamRunners();
    void populateFallbackReleases(const QString& category);
    bool isReleaseInstalled(const QString& tagName, const QString& name) const;
};

} // namespace Tsuki

