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
                platform TEXT DEFAULT 'windows',
                source TEXT DEFAULT 'local',
                epic_app_name TEXT,
                epic_namespace TEXT,
                epic_catalog_item_id TEXT,
                epic_build_version TEXT,
                epic_install_dir TEXT
            )
        )"),
        QStringLiteral(R"(
            CREATE TABLE IF NOT EXISTS epic_library (
                app_name TEXT PRIMARY KEY,
                namespace_id TEXT NOT NULL,
                catalog_item_id TEXT NOT NULL,
                title TEXT NOT NULL,
                developer TEXT,
                description TEXT,
                cover_url TEXT,
                banner_url TEXT,
                logo_url TEXT,
                cover_path TEXT,
                banner_path TEXT,
                logo_path TEXT,
                download_size INTEGER DEFAULT 0,
                install_size INTEGER DEFAULT 0,
                build_version TEXT,
                last_synced INTEGER DEFAULT 0
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
        )")
    };

    for (const QString& sql : schemas) {
        if (!q.exec(sql)) {
            qWarning() << "Failed to execute schema SQL:" << q.lastError().text();
            return false;
        }
    }

    // Ensure legacy controller_profiles table is removed cleanly
    q.exec(QStringLiteral("DROP TABLE IF EXISTS controller_profiles"));

    // Ensure 'platform' and Epic columns exist in 'games' table (migration for existing databases)
    QSet<QString> existingCols;
    if (q.exec(QStringLiteral("PRAGMA table_info(games)"))) {
        while (q.next()) {
            existingCols.insert(q.value(1).toString().toLower());
        }
    }
    struct ColumnMigration {
        const char* name;
        const char* sql;
    };
    static const ColumnMigration kMigrations[] = {
        {"platform", "ALTER TABLE games ADD COLUMN platform TEXT DEFAULT 'windows'"},
        {"source", "ALTER TABLE games ADD COLUMN source TEXT DEFAULT 'local'"},
        {"epic_app_name", "ALTER TABLE games ADD COLUMN epic_app_name TEXT"},
        {"epic_namespace", "ALTER TABLE games ADD COLUMN epic_namespace TEXT"},
        {"epic_catalog_item_id", "ALTER TABLE games ADD COLUMN epic_catalog_item_id TEXT"},
        {"epic_build_version", "ALTER TABLE games ADD COLUMN epic_build_version TEXT"},
        {"epic_install_dir", "ALTER TABLE games ADD COLUMN epic_install_dir TEXT"}
    };
    for (const auto& m : kMigrations) {
        if (!existingCols.contains(QLatin1String(m.name))) {
            if (!q.exec(QLatin1String(m.sql))) {
                qWarning() << "Failed to migrate games table for column" << m.name << ":" << q.lastError().text();
            }
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
            platform, source, epic_app_name, epic_namespace, epic_catalog_item_id,
            epic_build_version, epic_install_dir
        ) VALUES (
            :id, :title, :executable_path, :working_directory, :launch_arguments,
            :runner_id, :prefix_id, :cover_path, :banner_path, :logo_path, :icon_path,
            :steamgrid_app_id, :is_favorite, :is_pinned,
            :playtime_seconds, :last_played_timestamp, :added_timestamp, :launch_config_json,
            :platform, :source, :epic_app_name, :epic_namespace, :epic_catalog_item_id,
            :epic_build_version, :epic_install_dir
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
    q.bindValue(QStringLiteral(":source"), game.source.isEmpty() ? QStringLiteral("local") : game.source);
    q.bindValue(QStringLiteral(":epic_app_name"), game.epicAppName);
    q.bindValue(QStringLiteral(":epic_namespace"), game.epicNamespace);
    q.bindValue(QStringLiteral(":epic_catalog_item_id"), game.epicCatalogItemId);
    q.bindValue(QStringLiteral(":epic_build_version"), game.epicBuildVersion);
    q.bindValue(QStringLiteral(":epic_install_dir"), game.epicInstallDir);

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
    g.source = q.value(19).toString();
    if (g.source.isEmpty()) {
        g.source = QStringLiteral("local");
    }
    g.epicAppName = q.value(20).toString();
    g.epicNamespace = q.value(21).toString();
    g.epicCatalogItemId = q.value(22).toString();
    g.epicBuildVersion = q.value(23).toString();
    g.epicInstallDir = q.value(24).toString();
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
               platform, source, epic_app_name, epic_namespace, epic_catalog_item_id,
               epic_build_version, epic_install_dir
        FROM games WHERE id = :id
    )"));
    q.bindValue(QStringLiteral(":id"), gameId);
    if (q.exec() && q.next()) {
        return recordFromQuery(q);
    }
    return std::nullopt;
}

std::optional<GameRecord> DatabaseManager::getGameByEpicAppName(const QString& appName) const {
    if (appName.isEmpty()) return std::nullopt;
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT id, title, executable_path, working_directory, launch_arguments,
               runner_id, prefix_id, cover_path, banner_path, logo_path, icon_path,
               steamgrid_app_id, is_favorite, is_pinned,
               playtime_seconds, last_played_timestamp, added_timestamp, launch_config_json,
               platform, source, epic_app_name, epic_namespace, epic_catalog_item_id,
               epic_build_version, epic_install_dir
        FROM games WHERE epic_app_name = :app_name AND source = 'epic'
        LIMIT 1
    )"));
    q.bindValue(QStringLiteral(":app_name"), appName);
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
               platform, source, epic_app_name, epic_namespace, epic_catalog_item_id,
               epic_build_version, epic_install_dir
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

bool DatabaseManager::setAllGamesXboxEmulationState(bool enabled) {
    QMutexLocker locker(&m_mutex);
    auto database = db();
    if (!database.isOpen()) return false;

    QSqlQuery q(database);
    if (!q.exec(QStringLiteral("SELECT id, launch_config_json FROM games"))) {
        return false;
    }

    struct UpdateItem {
        QString id;
        QString json;
    };
    QList<UpdateItem> updates;
    const int targetVal = enabled ? 1 : 0;

    while (q.next()) {
        const QString id = q.value(0).toString();
        const QString jsonStr = q.value(1).toString();
        QJsonObject obj;
        if (!jsonStr.isEmpty()) {
            QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
            if (doc.isObject()) {
                obj = doc.object();
            }
        }
        bool changed = false;
        if (!obj.contains(QStringLiteral("xboxEmulationState")) || obj.value(QStringLiteral("xboxEmulationState")).toInt(-1) != targetVal) {
            obj[QStringLiteral("xboxEmulationState")] = targetVal;
            changed = true;
        }
        if (obj.contains(QStringLiteral("controllerProfileId"))) {
            obj.remove(QStringLiteral("controllerProfileId"));
            changed = true;
        }
        if (changed) {
            updates.append({id, QString::fromUtf8(QJsonDocument(obj).toJson(QJsonDocument::Compact))});
        }
    }

    for (const auto& item : updates) {
        QSqlQuery updateQ(database);
        updateQ.prepare(QStringLiteral("UPDATE games SET launch_config_json = :json WHERE id = :id"));
        updateQ.bindValue(QStringLiteral(":json"), item.json);
        updateQ.bindValue(QStringLiteral(":id"), item.id);
        updateQ.exec();
    }
    return true;
}

EpicLibraryItem DatabaseManager::epicItemFromQuery(QSqlQuery& q) {
    EpicLibraryItem item;
    item.appName = q.value(0).toString();
    item.namespaceId = q.value(1).toString();
    item.catalogItemId = q.value(2).toString();
    item.title = q.value(3).toString();
    item.developer = q.value(4).toString();
    item.description = q.value(5).toString();
    item.coverUrl = q.value(6).toString();
    item.bannerUrl = q.value(7).toString();
    item.logoUrl = q.value(8).toString();
    item.coverPath = q.value(9).toString();
    item.bannerPath = q.value(10).toString();
    item.logoPath = q.value(11).toString();
    item.downloadSize = q.value(12).toLongLong();
    item.installSize = q.value(13).toLongLong();
    item.buildVersion = q.value(14).toString();
    item.lastSynced = q.value(15).toLongLong();
    return item;
}

bool DatabaseManager::saveEpicLibraryItem(const EpicLibraryItem& item) {
    return saveEpicLibraryItems({item});
}

bool DatabaseManager::saveEpicLibraryItems(const QList<EpicLibraryItem>& items) {
    if (items.isEmpty()) return true;
    QMutexLocker locker(&m_mutex);
    auto database = db();
    if (!database.isOpen()) return false;
    database.transaction();

    QSqlQuery q(database);
    q.prepare(QStringLiteral(R"(
        INSERT OR REPLACE INTO epic_library (
            app_name, namespace_id, catalog_item_id, title, developer, description,
            cover_url, banner_url, logo_url, cover_path, banner_path, logo_path,
            download_size, install_size, build_version, last_synced
        ) VALUES (
            :app_name, :namespace_id, :catalog_item_id, :title, :developer, :description,
            :cover_url, :banner_url, :logo_url,
            COALESCE(NULLIF(:cover_path, ''), (SELECT cover_path FROM epic_library WHERE app_name = :app_name)),
            COALESCE(NULLIF(:banner_path, ''), (SELECT banner_path FROM epic_library WHERE app_name = :app_name)),
            COALESCE(NULLIF(:logo_path, ''), (SELECT logo_path FROM epic_library WHERE app_name = :app_name)),
            CASE WHEN :download_size > 0 THEN :download_size ELSE COALESCE((SELECT download_size FROM epic_library WHERE app_name = :app_name), 0) END,
            CASE WHEN :install_size > 0 THEN :install_size ELSE COALESCE((SELECT install_size FROM epic_library WHERE app_name = :app_name), 0) END,
            COALESCE(NULLIF(:build_version, ''), (SELECT build_version FROM epic_library WHERE app_name = :app_name)),
            :last_synced
        )
    )"));

    for (const EpicLibraryItem& item : items) {
        q.bindValue(QStringLiteral(":app_name"), item.appName);
        q.bindValue(QStringLiteral(":namespace_id"), item.namespaceId);
        q.bindValue(QStringLiteral(":catalog_item_id"), item.catalogItemId);
        q.bindValue(QStringLiteral(":title"), item.title);
        q.bindValue(QStringLiteral(":developer"), item.developer);
        q.bindValue(QStringLiteral(":description"), item.description);
        q.bindValue(QStringLiteral(":cover_url"), item.coverUrl);
        q.bindValue(QStringLiteral(":banner_url"), item.bannerUrl);
        q.bindValue(QStringLiteral(":logo_url"), item.logoUrl);
        q.bindValue(QStringLiteral(":cover_path"), item.coverPath);
        q.bindValue(QStringLiteral(":banner_path"), item.bannerPath);
        q.bindValue(QStringLiteral(":logo_path"), item.logoPath);
        q.bindValue(QStringLiteral(":download_size"), item.downloadSize);
        q.bindValue(QStringLiteral(":install_size"), item.installSize);
        q.bindValue(QStringLiteral(":build_version"), item.buildVersion);
        q.bindValue(QStringLiteral(":last_synced"), item.lastSynced);
        if (!q.exec()) {
            qWarning() << "saveEpicLibraryItems failed:" << q.lastError().text();
            database.rollback();
            return false;
        }
    }
    return database.commit();
}

std::optional<EpicLibraryItem> DatabaseManager::getEpicLibraryItem(const QString& appName) const {
    if (appName.isEmpty()) return std::nullopt;
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        SELECT app_name, namespace_id, catalog_item_id, title, developer, description,
               cover_url, banner_url, logo_url, cover_path, banner_path, logo_path,
               download_size, install_size, build_version, last_synced
        FROM epic_library WHERE app_name = :app_name
    )"));
    q.bindValue(QStringLiteral(":app_name"), appName);
    if (q.exec() && q.next()) {
        return epicItemFromQuery(q);
    }
    return std::nullopt;
}

QList<EpicLibraryItem> DatabaseManager::getAllEpicLibraryItems() const {
    QMutexLocker locker(&m_mutex);
    QList<EpicLibraryItem> list;
    QSqlQuery q(db());
    if (q.exec(QStringLiteral(R"(
        SELECT app_name, namespace_id, catalog_item_id, title, developer, description,
               cover_url, banner_url, logo_url, cover_path, banner_path, logo_path,
               download_size, install_size, build_version, last_synced
        FROM epic_library ORDER BY title COLLATE NOCASE ASC
    )"))) {
        while (q.next()) {
            list.append(epicItemFromQuery(q));
        }
    }
    return list;
}

bool DatabaseManager::updateEpicLibraryArtwork(const QString& appName,
                                               const QString& coverPath,
                                               const QString& bannerPath,
                                               const QString& logoPath) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        UPDATE epic_library
        SET cover_path = CASE WHEN :cover != '' THEN :cover ELSE cover_path END,
            banner_path = CASE WHEN :banner != '' THEN :banner ELSE banner_path END,
            logo_path = CASE WHEN :logo != '' THEN :logo ELSE logo_path END
        WHERE app_name = :app_name
    )"));
    q.bindValue(QStringLiteral(":cover"), coverPath);
    q.bindValue(QStringLiteral(":banner"), bannerPath);
    q.bindValue(QStringLiteral(":logo"), logoPath);
    q.bindValue(QStringLiteral(":app_name"), appName);
    return q.exec();
}

bool DatabaseManager::updateEpicLibrarySizes(const QString& appName, qint64 downloadSize, qint64 installSize, const QString& buildVersion) {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    q.prepare(QStringLiteral(R"(
        UPDATE epic_library
        SET download_size = CASE WHEN :dl > 0 THEN :dl ELSE download_size END,
            install_size = CASE WHEN :inst > 0 THEN :inst ELSE install_size END,
            build_version = CASE WHEN :bv != '' THEN :bv ELSE build_version END
        WHERE app_name = :app_name
    )"));
    q.bindValue(QStringLiteral(":dl"), downloadSize);
    q.bindValue(QStringLiteral(":inst"), installSize);
    q.bindValue(QStringLiteral(":bv"), buildVersion);
    q.bindValue(QStringLiteral(":app_name"), appName);
    return q.exec();
}

bool DatabaseManager::clearEpicLibrary() {
    QMutexLocker locker(&m_mutex);
    QSqlQuery q(db());
    return q.exec(QStringLiteral("DELETE FROM epic_library"));
}

} // namespace Tsuki

