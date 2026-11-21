#pragma once

#include "../core/DatabaseManager.h"
#include "../core/Models.h"
#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <functional>

namespace Tsuki {

class UmuIdResolver : public QObject {
    Q_OBJECT
public:
    explicit UmuIdResolver(DatabaseManager* db, QObject* parent = nullptr);

    /// Synchronously resolves the best known UMU GAMEID for a game using:
    /// 1) game.umuGameId explicit override
    /// 2) SQLite umu_id_cache lookup for (store, codename)
    /// 3) "umu-default" fallback
    QString resolveGameIdSync(const GameRecord& game) const;

    /// Canonical UMU store string ("egs" for Epic, "none" for local).
    static QString storeForGame(const GameRecord& game);

    /// Asynchronously query the UMU database API for (store, codename) and store in SQLite cache.
    /// Invokes callback with resolved ID (or empty string if none found).
    void lookupAndCache(const QString& store,
                        const QString& codename,
                        std::function<void(const QString& umuId)> callback = nullptr);

    /// Convenience helper for QML / EpicService.
    Q_INVOKABLE void lookupForGame(const QString& gameId);

    /// Parse umu_api.php JSON payload into first matching umu_id (unit-testable).
    static QString parseUmuApiResponse(const QByteArray& jsonPayload, QString* outTitle = nullptr);

signals:
    void umuIdResolved(const QString& store, const QString& codename, const QString& umuId);

private:
    DatabaseManager* m_db;
    QNetworkAccessManager m_nam;
    QSet<QString> m_inFlight;
};

} // namespace Tsuki
