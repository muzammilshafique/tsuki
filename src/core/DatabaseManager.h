#pragma once

#include "Models.h"
#include <QObject>
#include <QSqlDatabase>
#include <QMutex>
#include <QList>
#include <optional>

namespace Tsuki {

class DatabaseManager : public QObject {
    Q_OBJECT
public:
    explicit DatabaseManager(const QString& dbFilePath = QString(), QObject* parent = nullptr);
    ~DatabaseManager() override;

    bool initialize();
    bool isOpen() const;

    // Games CRUD
    bool saveGame(const GameRecord& game);
    bool removeGame(const QString& gameId);
    std::optional<GameRecord> getGame(const QString& gameId) const;
    QList<GameRecord> getAllGames() const;
    bool updatePlaytime(const QString& gameId, qint64 additionalSeconds, qint64 lastPlayedEpoch);

    // Prefixes CRUD
    bool savePrefix(const PrefixRecord& prefix);
    bool removePrefix(const QString& prefixId);
    std::optional<PrefixRecord> getPrefix(const QString& prefixId) const;
    std::optional<PrefixRecord> getPrefixByName(const QString& name) const;
    QList<PrefixRecord> getAllPrefixes() const;

    // Runners CRUD
    bool saveRunner(const RunnerRecord& runner);
    bool removeRunner(const QString& runnerId);
    std::optional<RunnerRecord> getRunner(const QString& runnerId) const;
    QList<RunnerRecord> getAllRunners() const;

    // Controller Profiles CRUD
    bool saveControllerProfile(const ControllerProfileRecord& profile);
    bool removeControllerProfile(const QString& profileId);
    std::optional<ControllerProfileRecord> getControllerProfile(const QString& profileId) const;
    QList<ControllerProfileRecord> getAllControllerProfiles() const;

private:
    QString m_dbPath;
    QString m_connectionName;
    mutable QMutex m_mutex;

    QSqlDatabase db() const;
    static GameRecord recordFromQuery(class QSqlQuery& q);
    static PrefixRecord prefixFromQuery(class QSqlQuery& q);
    static RunnerRecord runnerFromQuery(class QSqlQuery& q);
    static ControllerProfileRecord controllerProfileFromQuery(class QSqlQuery& q);
};

} // namespace Tsuki

