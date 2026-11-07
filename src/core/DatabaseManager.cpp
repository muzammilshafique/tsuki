#include "DatabaseManager.h"
#include "AppSettings.h"
#include <QSqlQuery>
#include <QSqlError>
#include <QUuid>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>

namespace Tsuki {

DatabaseManager::DatabaseManager(const QString& dbFilePath, QObject* parent)
    : QObject(parent)
    , m_dbPath(dbFilePath.isEmpty() ? (AppSettings::dataDir() + QStringLiteral("/tsuki.db")) : dbFilePath)
    , m_connectionName(QStringLiteral("tsuki_db_") + QUuid::createUuid().toString(QUuid::Id128))
{
}

DatabaseManager::~DatabaseManager() {
    if (QSqlDatabase::contains(m_connectionName)) {
        {
            QSqlDatabase database = QSqlDatabase::database(m_connectionName, false);
            if (database.isOpen()) {
                database.close();
            }
        }
        QSqlDatabase::removeDatabase(m_connectionName);
    }
}

QSqlDatabase DatabaseManager::db() const {
    return QSqlDatabase::database(m_connectionName);
}

bool DatabaseManager::isOpen() const {
    QMutexLocker locker(&m_mutex);
    return QSqlDatabase::contains(m_connectionName) && db().isOpen();
}

bool DatabaseManager::initialize() {
    QMutexLocker locker(&m_mutex);
    QSqlDatabase database = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    database.setDatabaseName(m_dbPath);
    if (!database.open()) {
        qWarning() << "Failed to open SQLite database:" << database.lastError().text();
        return false;
    }

    QSqlQuery q(database);
    q.exec(QStringLiteral("PRAGMA journal_mode=WAL;"));
    q.exec(QStringLiteral("PRAGMA synchronous=NORMAL;"));
    q.exec(QStringLiteral("PRAGMA foreign_keys=ON;"));

    const QStringList schemas = {
        QStringLiteral(R"(
            CREATE TABLE IF NOT EXISTS games (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                executable_path TEXT NOT NULL,
                working_directory TEXT,
                launch_arguments TEXT,
                runner_id TEXT,
                prefix_id TEXT,
                cover_path TEXT,
                banner_path TEXT,
                logo_path TEXT,
                icon_path TEXT,
                steamgrid_app_id TEXT,
                is_favorite INTEGER DEFAULT 0,
                is_pinned INTEGER DEFAULT 0,
                playtime_seconds INTEGER DEFAULT 0,
                last_played_timestamp INTEGER DEFAULT 0,
                added_timestamp INTEGER DEFAULT 0,
                launch_config_json TEXT,
                platform TEXT DEFAULT 'windows'
            )
        )"),
        QStringLiteral(R"(
            CREATE TABLE IF NOT EXISTS prefixes (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                path TEXT NOT NULL,
                arch TEXT DEFAULT 'win64',
                windows_version TEXT DEFAULT 'win10',
                runner_id TEXT,
                dxvk_installed INTEGER DEFAULT 0,
                vkd3d_installed INTEGER DEFAULT 0,
                dll_overrides_json TEXT,
                installed_winetricks_json TEXT,
                created_at INTEGER DEFAULT 0
            )
        )"),
        QStringLiteral(R"(
            CREATE TABLE IF NOT EXISTS runners (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                type TEXT NOT NULL,
                version TEXT,
                path TEXT NOT NULL,
                binary_path TEXT NOT NULL,
                is_system INTEGER DEFAULT 0,
                settings_json TEXT
            )
        )"),
        QStringLiteral(R"(
            CREATE TABLE IF NOT EXISTS controller_profiles (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                xbox_emulation INTEGER DEFAULT 1,
                deadzone INTEGER DEFAULT 4000,
                button_mappings_json TEXT
            )
        )")
    };

    for (const QString& sql : schemas) {
        if (!q.exec(sql)) {
            qWarning() << "Failed to execute schema SQL:" << q.lastError().text();
            return false;
        }
    }

    // Ensure 'platform' column exists in 'games' table (migration for existing databases)
    bool hasPlatform = false;
    if (q.exec(QStringLiteral("PRAGMA table_info(games)"))) {
        while (q.next()) {
            if (q.value(1).toString().compare(QStringLiteral("platform"), Qt::CaseInsensitive) == 0) {
                hasPlatform = true;
                break;
            }
        }
    }
    if (!hasPlatform) {
        if (!q.exec(QStringLiteral("ALTER TABLE games ADD COLUMN platform TEXT DEFAULT 'windows'"))) {
            qWarning() << "Failed to migrate games table for platform column:" << q.lastError().text();
        }
    }

    // Ensure default controller profile exists
    q.prepare(QStringLiteral("SELECT COUNT(*) FROM controller_profiles WHERE id = 'default-xbox'"));
    if (q.exec() && q.next() && q.value(0).toInt() == 0) {
        ControllerProfileRecord defProfile;
        defProfile.id = QStringLiteral("default-xbox");
        defProfile.name = QStringLiteral("Xbox 360 Standard (XInput)");
        defProfile.xboxEmulation = true;
        defProfile.deadzone = 4000;
        defProfile.buttonMappings = ControllerProfileRecord::defaultXboxMappings();
        locker.unlock();
        saveControllerProfile(defProfile);
        locker.relock();
    }

    // Migrate any legacy swapped X/Y button mappings in controller profiles
    q.prepare(QStringLiteral("SELECT id, button_mappings_json FROM controller_profiles"));
    if (q.exec()) {
        struct MigItem { QString id; QString json; };
        QList<MigItem> toMigrate;
        while (q.next()) {
            const QString pid = q.value(0).toString();
            const QString jsonStr = q.value(1).toString();
            if (jsonStr.contains(QStringLiteral("\"x\":\"BTN_WEST\"")) &&
                jsonStr.contains(QStringLiteral("\"y\":\"BTN_NORTH\""))) {
                QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
                QJsonObject obj = doc.object();
                obj[QStringLiteral("x")] = QStringLiteral("BTN_NORTH");
                obj[QStringLiteral("y")] = QStringLiteral("BTN_WEST");
                toMigrate.append({pid, QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact))});
            }
        }
        for (const auto& item : toMigrate) {
            QSqlQuery updateQ(db());
            updateQ.prepare(QStringLiteral("UPDATE controller_profiles SET button_mappings_json = :json WHERE id = :id"));
            updateQ.bindValue(QStringLiteral(":json"), item.json);
            updateQ.bindValue(QStringLiteral(":id"), item.id);
            updateQ.exec();
        }
    }

    return true;
}

bool DatabaseManager::saveGame(const GameRecord& game) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        INSERT OR REPLACE INTO games (
            id, title, executable_path, working_directory, launch_arguments,
            runner_id, prefix_id, cover_path, banner_path, logo_path, icon_path,
            steamgrid_app_id, is_favorite, is_pinned,
            playtime_seconds, last_played_timestamp, added_timestamp, launch_config_json,
            platform
        ) VALUES (
            :id, :title, :executable_path, :working_directory, :launch_arguments,
            :runner_id, :prefix_id, :cover_path, :banner_path, :logo_path, :icon_path,
            :steamgrid_app_id, :is_favorite, :is_pinned,
            :playtime_seconds, :last_played_timestamp, :added_timestamp, :launch_config_json,
            :platform
        )
    )"));
    q.bindValue(QStringLiteral(":id"), game.id);
    q.bindValue(QStringLiteral(":title"), game.title);
    q.bindValue(QStringLiteral(":executable_path"), game.executablePath);
    q.bindValue(QStringLiteral(":working_directory"), game.workingDirectory);
    q.bindValue(QStringLiteral(":launch_arguments"), game.launchArguments);
    q.bindValue(QStringLiteral(":runner_id"), game.runnerId);
    q.bindValue(QStringLiteral(":prefix_id"), game.prefixId);
    q.bindValue(QStringLiteral(":cover_path"), game.coverPath);
    q.bindValue(QStringLiteral(":banner_path"), game.bannerPath);
    q.bindValue(QStringLiteral(":logo_path"), game.logoPath);
    q.bindValue(QStringLiteral(":icon_path"), game.iconPath);
    q.bindValue(QStringLiteral(":steamgrid_app_id"), game.steamGridAppId);
    q.bindValue(QStringLiteral(":is_favorite"), game.isFavorite ? 1 : 0);
    q.bindValue(QStringLiteral(":is_pinned"), game.isPinned ? 1 : 0);
    q.bindValue(QStringLiteral(":playtime_seconds"), game.playtimeSeconds);
    q.bindValue(QStringLiteral(":last_played_timestamp"), game.lastPlayedTimestamp);
    q.bindValue(QStringLiteral(":added_timestamp"), game.addedTimestamp);
    q.bindValue(QStringLiteral(":launch_config_json"), game.launchConfigToJson());
    q.bindValue(QStringLiteral(":platform"), game.platform.isEmpty() ? QStringLiteral("windows") : game.platform);

    if (!q.exec()) {
        qWarning() << "saveGame failed:" << q.lastError().text();
        return false;
    }
    return true;
}

bool DatabaseManager::removeGame(const QString& gameId) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral("DELETE FROM games WHERE id = :id"));
    q.bindValue(QStringLiteral(":id"), gameId);
    return q.exec();
}

GameRecord DatabaseManager::recordFromQuery(QSqlQuery& q) {
    GameRecord g;
    g.id = q.value(0).toString();
    g.title = q.value(1).toString();
    g.executablePath = q.value(2).toString();
    g.workingDirectory = q.value(3).toString();
    g.launchArguments = q.value(4).toString();
    g.runnerId = q.value(5).toString();
    g.prefixId = q.value(6).toString();
    g.coverPath = q.value(7).toString();
    g.bannerPath = q.value(8).toString();
    g.logoPath = q.value(9).toString();
    g.iconPath = q.value(10).toString();
    g.steamGridAppId = q.value(11).toString();
    g.isFavorite = q.value(12).toInt() != 0;
    g.isPinned = q.value(13).toInt() != 0;
    g.playtimeSeconds = q.value(14).toLongLong();
    g.lastPlayedTimestamp = q.value(15).toLongLong();
    g.addedTimestamp = q.value(16).toLongLong();
    g.applyLaunchConfigJson(q.value(17).toString());
    g.platform = q.value(18).toString();
    if (g.platform.isEmpty()) {
        g.platform = QStringLiteral("windows");
    }
    return g;
}

std::optional<GameRecord> DatabaseManager::getGame(const QString& gameId) const {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT id, title, executable_path, working_directory, launch_arguments,
               runner_id, prefix_id, cover_path, banner_path, logo_path, icon_path,
               steamgrid_app_id, is_favorite, is_pinned,
               playtime_seconds, last_played_timestamp, added_timestamp, launch_config_json,
               platform
        FROM games WHERE id = :id
    )"));
    q.bindValue(QStringLiteral(":id"), gameId);
    if (q.exec() && q.next()) {
        return recordFromQuery(q);
    }
    return std::nullopt;
}

QList<GameRecord> DatabaseManager::getAllGames() const {
    QMutexLocker locker(&m_mutex);
    QList<GameRecord> list;
    QSqlQuery q(db());
    if (q.exec(QStringLiteral(R"(
        SELECT id, title, executable_path, working_directory, launch_arguments,
               runner_id, prefix_id, cover_path, banner_path, logo_path, icon_path,
               steamgrid_app_id, is_favorite, is_pinned,
               playtime_seconds, last_played_timestamp, added_timestamp, launch_config_json,
               platform
        FROM games
        ORDER BY is_pinned DESC, last_played_timestamp DESC, added_timestamp DESC
    )"))) {
        while (q.next()) {
            list.append(recordFromQuery(q));
        }
    }
    return list;
}

bool DatabaseManager::updatePlaytime(const QString& gameId, qint64 additionalSeconds, qint64 lastPlayedEpoch) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        UPDATE games
        SET playtime_seconds = playtime_seconds + :add_secs,
            last_played_timestamp = :last_played
        WHERE id = :id
    )"));
    q.bindValue(QStringLiteral(":add_secs"), qMax<qint64>(0, additionalSeconds));
    q.bindValue(QStringLiteral(":last_played"), lastPlayedEpoch);
    q.bindValue(QStringLiteral(":id"), gameId);
    return q.exec();
}

bool DatabaseManager::savePrefix(const PrefixRecord& prefix) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        INSERT OR REPLACE INTO prefixes (
            id, name, path, arch, windows_version, runner_id,
            dxvk_installed, vkd3d_installed, dll_overrides_json,
            installed_winetricks_json, created_at
        ) VALUES (
            :id, :name, :path, :arch, :windows_version, :runner_id,
            :dxvk_installed, :vkd3d_installed, :dll_overrides_json,
            :installed_winetricks_json, :created_at
        )
    )"));
    q.bindValue(QStringLiteral(":id"), prefix.id);
    q.bindValue(QStringLiteral(":name"), prefix.name);
    q.bindValue(QStringLiteral(":path"), prefix.path);
    q.bindValue(QStringLiteral(":arch"), prefix.arch);
    q.bindValue(QStringLiteral(":windows_version"), prefix.windowsVersion);
    q.bindValue(QStringLiteral(":runner_id"), prefix.runnerId);
    q.bindValue(QStringLiteral(":dxvk_installed"), prefix.dxvkInstalled ? 1 : 0);
    q.bindValue(QStringLiteral(":vkd3d_installed"), prefix.vkd3dInstalled ? 1 : 0);

    const QString overridesJson = QString::fromUtf8(
        QJsonDocument(QJsonObject::fromVariantMap(prefix.dllOverrides)).toJson(QJsonDocument::Compact));
    const QString winetricksJson = QString::fromUtf8(
        QJsonDocument(QJsonArray::fromStringList(prefix.installedWinetricks)).toJson(QJsonDocument::Compact));

    q.bindValue(QStringLiteral(":dll_overrides_json"), overridesJson);
    q.bindValue(QStringLiteral(":installed_winetricks_json"), winetricksJson);
    q.bindValue(QStringLiteral(":created_at"), prefix.createdAt);
    return q.exec();
}

bool DatabaseManager::removePrefix(const QString& prefixId) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral("DELETE FROM prefixes WHERE id = :id"));
    q.bindValue(QStringLiteral(":id"), prefixId);
    return q.exec();
}

PrefixRecord DatabaseManager::prefixFromQuery(QSqlQuery& q) {
    PrefixRecord p;
    p.id = q.value(0).toString();
    p.name = q.value(1).toString();
    p.path = q.value(2).toString();
    p.arch = q.value(3).toString();
    p.windowsVersion = q.value(4).toString();
    p.runnerId = q.value(5).toString();
    p.dxvkInstalled = q.value(6).toInt() != 0;
    p.vkd3dInstalled = q.value(7).toInt() != 0;

    const QByteArray ovBytes = q.value(8).toString().toUtf8();
    if (!ovBytes.isEmpty()) {
        p.dllOverrides = QJsonDocument::fromJson(ovBytes).object().toVariantMap();
    }
    const QByteArray wtBytes = q.value(9).toString().toUtf8();
    if (!wtBytes.isEmpty()) {
        const QJsonArray arr = QJsonDocument::fromJson(wtBytes).array();
        for (const QJsonValue& v : arr) {
            p.installedWinetricks.append(v.toString());
        }
    }
    p.createdAt = q.value(10).toLongLong();
    return p;
}

std::optional<PrefixRecord> DatabaseManager::getPrefix(const QString& prefixId) const {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT id, name, path, arch, windows_version, runner_id,
               dxvk_installed, vkd3d_installed, dll_overrides_json,
               installed_winetricks_json, created_at
        FROM prefixes WHERE id = :id
    )"));
    q.bindValue(QStringLiteral(":id"), prefixId);
    if (q.exec() && q.next()) {
        return prefixFromQuery(q);
    }
    return std::nullopt;
}

std::optional<PrefixRecord> DatabaseManager::getPrefixByName(const QString& name) const {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT id, name, path, arch, windows_version, runner_id,
               dxvk_installed, vkd3d_installed, dll_overrides_json,
               installed_winetricks_json, created_at
        FROM prefixes WHERE LOWER(name) = LOWER(:name)
    )"));
    q.bindValue(QStringLiteral(":name"), name);
    if (q.exec() && q.next()) {
        return prefixFromQuery(q);
    }
    return std::nullopt;
}

QList<PrefixRecord> DatabaseManager::getAllPrefixes() const {
    QMutexLocker locker(&m_mutex);
    QList<PrefixRecord> list;
    QSqlQuery q(db());
    if (q.exec(QStringLiteral(R"(
        SELECT id, name, path, arch, windows_version, runner_id,
               dxvk_installed, vkd3d_installed, dll_overrides_json,
               installed_winetricks_json, created_at
        FROM prefixes ORDER BY created_at DESC, name ASC
    )"))) {
        while (q.next()) {
            list.append(prefixFromQuery(q));
        }
    }
    return list;
}

bool DatabaseManager::saveRunner(const RunnerRecord& runner) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        INSERT OR REPLACE INTO runners (
            id, name, type, version, path, binary_path, is_system, settings_json
        ) VALUES (
            :id, :name, :type, :version, :path, :binary_path, :is_system, :settings_json
        )
    )"));
    q.bindValue(QStringLiteral(":id"), runner.id);
    q.bindValue(QStringLiteral(":name"), runner.name);
    q.bindValue(QStringLiteral(":type"), runner.type);
    q.bindValue(QStringLiteral(":version"), runner.version);
    q.bindValue(QStringLiteral(":path"), runner.path);
    q.bindValue(QStringLiteral(":binary_path"), runner.binaryPath);
    q.bindValue(QStringLiteral(":is_system"), runner.isSystem ? 1 : 0);
    q.bindValue(QStringLiteral(":settings_json"),
                QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(runner.settings)).toJson(QJsonDocument::Compact)));
    return q.exec();
}

bool DatabaseManager::removeRunner(const QString& runnerId) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral("DELETE FROM runners WHERE id = :id"));
    q.bindValue(QStringLiteral(":id"), runnerId);
    return q.exec();
}

RunnerRecord DatabaseManager::runnerFromQuery(QSqlQuery& q) {
    RunnerRecord r;
    r.id = q.value(0).toString();
    r.name = q.value(1).toString();
    r.type = q.value(2).toString();
    r.version = q.value(3).toString();
    r.path = q.value(4).toString();
    r.binaryPath = q.value(5).toString();
    r.isSystem = q.value(6).toInt() != 0;
    const QByteArray sBytes = q.value(7).toString().toUtf8();
    if (!sBytes.isEmpty()) {
        r.settings = QJsonDocument::fromJson(sBytes).object().toVariantMap();
    }
    return r;
}

std::optional<RunnerRecord> DatabaseManager::getRunner(const QString& runnerId) const {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT id, name, type, version, path, binary_path, is_system, settings_json
        FROM runners WHERE id = :id
    )"));
    q.bindValue(QStringLiteral(":id"), runnerId);
    if (q.exec() && q.next()) {
        return runnerFromQuery(q);
    }
    return std::nullopt;
}

QList<RunnerRecord> DatabaseManager::getAllRunners() const {
    QMutexLocker locker(&m_mutex);
    QList<RunnerRecord> list;
    QSqlQuery q(db());
    if (q.exec(QStringLiteral(R"(
        SELECT id, name, type, version, path, binary_path, is_system, settings_json
        FROM runners ORDER BY is_system DESC, name ASC
    )"))) {
        while (q.next()) {
            list.append(runnerFromQuery(q));
        }
    }
    return list;
}

bool DatabaseManager::saveControllerProfile(const ControllerProfileRecord& profile) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        INSERT OR REPLACE INTO controller_profiles (
            id, name, xbox_emulation, deadzone, button_mappings_json
        ) VALUES (
            :id, :name, :xbox_emulation, :deadzone, :button_mappings_json
        )
    )"));
    q.bindValue(QStringLiteral(":id"), profile.id);
    q.bindValue(QStringLiteral(":name"), profile.name);
    q.bindValue(QStringLiteral(":xbox_emulation"), profile.xboxEmulation ? 1 : 0);
    q.bindValue(QStringLiteral(":deadzone"), profile.deadzone);
    q.bindValue(QStringLiteral(":button_mappings_json"),
                QString::fromUtf8(QJsonDocument(QJsonObject::fromVariantMap(profile.buttonMappings)).toJson(QJsonDocument::Compact)));
    return q.exec();
}

bool DatabaseManager::removeControllerProfile(const QString& profileId) {
    if (profileId == QStringLiteral("default-xbox")) return false;
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral("DELETE FROM controller_profiles WHERE id = :id"));
    q.bindValue(QStringLiteral(":id"), profileId);
    return q.exec();
}

ControllerProfileRecord DatabaseManager::controllerProfileFromQuery(QSqlQuery& q) {
    ControllerProfileRecord c;
    c.id = q.value(0).toString();
    c.name = q.value(1).toString();
    c.xboxEmulation = q.value(2).toInt() != 0;
    c.deadzone = q.value(3).toInt();
    const QByteArray mBytes = q.value(4).toString().toUtf8();
    if (!mBytes.isEmpty()) {
        c.buttonMappings = QJsonDocument::fromJson(mBytes).object().toVariantMap();
    }
    if (c.buttonMappings.isEmpty()) {
        c.buttonMappings = ControllerProfileRecord::defaultXboxMappings();
    } else if (c.buttonMappings.value(QStringLiteral("x")).toString() == QStringLiteral("BTN_WEST") &&
               c.buttonMappings.value(QStringLiteral("y")).toString() == QStringLiteral("BTN_NORTH")) {
        c.buttonMappings[QStringLiteral("x")] = QStringLiteral("BTN_NORTH");
        c.buttonMappings[QStringLiteral("y")] = QStringLiteral("BTN_WEST");
    }
    return c;
}

std::optional<ControllerProfileRecord> DatabaseManager::getControllerProfile(const QString& profileId) const {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT id, name, xbox_emulation, deadzone, button_mappings_json
        FROM controller_profiles WHERE id = :id
    )"));
    q.bindValue(QStringLiteral(":id"), profileId);
    if (q.exec() && q.next()) {
        return controllerProfileFromQuery(q);
    }
    return std::nullopt;
}

QList<ControllerProfileRecord> DatabaseManager::getAllControllerProfiles() const {
    QMutexLocker locker(&m_mutex);
    QList<ControllerProfileRecord> list;
    QSqlQuery q(db());
    if (q.exec(QStringLiteral(R"(
        SELECT id, name, xbox_emulation, deadzone, button_mappings_json
        FROM controller_profiles ORDER BY name ASC
    )"))) {
        while (q.next()) {
            list.append(controllerProfileFromQuery(q));
        }
    }
    return list;
}

} // namespace Tsuki

