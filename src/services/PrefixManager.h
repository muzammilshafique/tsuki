#pragma once

#include "../core/Models.h"
#include "../core/DatabaseManager.h"
#include "../core/AppSettings.h"
#include "RunnerManager.h"
#include <QObject>
#include <QProcessEnvironment>
#include <QVariantList>
#include <QVariantMap>

namespace Tsuki {

class PrefixManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList prefixes READ prefixesVariant NOTIFY prefixesChanged)
    Q_PROPERTY(bool isBusy READ isBusy NOTIFY busyChanged)
    Q_PROPERTY(QString currentOperation READ currentOperation NOTIFY busyChanged)

public:
    explicit PrefixManager(DatabaseManager* db,
                           AppSettings* settings,
                           RunnerManager* runnerMgr,
                           QObject* parent = nullptr);

    QVariantList prefixesVariant() const;
    QList<PrefixRecord> prefixes() const;
    bool isBusy() const { return m_isBusy; }
    QString currentOperation() const { return m_currentOperation; }

    std::optional<PrefixRecord> getPrefix(const QString& prefixId) const;
    Q_INVOKABLE QVariantMap getPrefixMap(const QString& prefixId) const;

    // Prefix Lifecycle
    Q_INVOKABLE QString createPrefix(const QString& name,
                                     const QString& customBaseLocation = QString(),
                                     const QString& arch = QStringLiteral("win64"),
                                     const QString& windowsVersion = QStringLiteral("win10"),
                                     const QString& runnerId = QString(),
                                     bool initializeNow = true);

    Q_INVOKABLE QString importPrefix(const QString& name, const QString& existingPath);
    Q_INVOKABLE QString clonePrefix(const QString& sourcePrefixId, const QString& newName, const QString& customDestDir = QString());
    Q_INVOKABLE void backupPrefix(const QString& prefixId, const QString& destinationArchivePath = QString());
    Q_INVOKABLE void restorePrefix(const QString& archivePath, const QString& prefixName, const QString& targetBaseDir = QString());
    Q_INVOKABLE bool deletePrefix(const QString& prefixId, bool deleteFilesFromDisk = true);
    Q_INVOKABLE bool renamePrefix(const QString& prefixId, const QString& newName);

    // Configuration & Tools
    Q_INVOKABLE void setWindowsVersion(const QString& prefixId, const QString& winVer);
    Q_INVOKABLE bool setDllOverride(const QString& prefixId, const QString& dllName, const QString& mode);
    Q_INVOKABLE bool removeDllOverride(const QString& prefixId, const QString& dllName);
    Q_INVOKABLE bool installDxvk(const QString& prefixId, bool enable = true);
    Q_INVOKABLE bool installVkd3d(const QString& prefixId, bool enable = true);

    // Run Installers & Utilities
    Q_INVOKABLE void runExecutableInPrefix(const QString& prefixId, const QString& exeOrMsiPath, const QStringList& args = {});
    Q_INVOKABLE void runWineTool(const QString& prefixId, const QString& toolName); // winecfg, regedit, uninstaller, cmd, taskmgr
    Q_INVOKABLE void openPrefixInFileManager(const QString& prefixId);
    Q_INVOKABLE void openPrefixInTerminal(const QString& prefixId);

    // Helper to suggest short prefix name (e.g. "Grand Theft Auto San Andreas" -> "GTASA")
    Q_INVOKABLE QString suggestShortPrefixName(const QString& gameTitle) const;

    static void ensureProtonSymlink(const QString& prefixPath);
    static bool writeRegistryDllOverrides(const QString& prefixPath, const QVariantMap& overrides);

signals:
    void prefixesChanged();
    void busyChanged();
    void prefixOperationFinished(const QString& prefixId, bool success, const QString& message);
    void prefixLogOutput(const QString& prefixId, const QString& line);

private:
    DatabaseManager* m_db;
    AppSettings* m_settings;
    RunnerManager* m_runnerMgr;
    bool m_isBusy = false;
    QString m_currentOperation;

    void setBusyState(bool busy, const QString& op = QString());
    QProcessEnvironment buildPrefixEnvironment(const PrefixRecord& pfx, const RunnerRecord& runner) const;
};

} // namespace Tsuki

