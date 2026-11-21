#include "UmuIdResolver.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QUrlQuery>

namespace Tsuki {

UmuIdResolver::UmuIdResolver(DatabaseManager* db, QObject* parent)
    : QObject(parent)
    , m_db(db)
{
}

QString UmuIdResolver::storeForGame(const GameRecord& game) {
    if (game.isEpic()) {
        return QStringLiteral("egs");
    }
    return QStringLiteral("none");
}

QString UmuIdResolver::resolveGameIdSync(const GameRecord& game) const {
    const QString overrideId = game.umuGameId.trimmed();
    if (!overrideId.isEmpty()) {
        return overrideId;
    }
    if (m_db && game.isEpic() && !game.epicAppName.isEmpty()) {
        const QString cached = m_db->getCachedUmuId(QStringLiteral("egs"), game.epicAppName);
        if (!cached.isEmpty()) {
            return cached;
        }
    }
    return QStringLiteral("umu-default");
}

QString UmuIdResolver::parseUmuApiResponse(const QByteArray& jsonPayload, QString* outTitle) {
    const QJsonDocument doc = QJsonDocument::fromJson(jsonPayload);
    if (!doc.isArray()) return QString();
    const QJsonArray arr = doc.array();
    for (const QJsonValue& val : arr) {
        if (!val.isObject()) continue;
        const QJsonObject obj = val.toObject();
        const QString umuId = obj.value(QStringLiteral("umu_id")).toString().trimmed();
        if (!umuId.isEmpty()) {
            if (outTitle) {
                *outTitle = obj.value(QStringLiteral("title")).toString().trimmed();
            }
            return umuId;
        }
    }
    return QString();
}

void UmuIdResolver::lookupAndCache(const QString& store,
                                   const QString& codename,
                                   std::function<void(const QString&)> callback) {
    const QString cleanStore = store.trimmed().toLower();
    const QString cleanCode = codename.trimmed();
    if (cleanStore.isEmpty() || cleanCode.isEmpty() || cleanStore == QLatin1String("none")) {
        if (callback) callback(QString());
        return;
    }

    if (m_db) {
        const QString cached = m_db->getCachedUmuId(cleanStore, cleanCode);
        if (!cached.isEmpty()) {
            if (callback) callback(cached);
            return;
        }
    }

    const QString key = cleanStore + QLatin1Char(':') + cleanCode;
    if (m_inFlight.contains(key)) {
        if (callback) callback(QString());
        return;
    }
    m_inFlight.insert(key);

    QUrl url(QStringLiteral("https://umu.openwinecomponents.org/umu_api.php"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("store"), cleanStore);
    q.addQueryItem(QStringLiteral("codename"), cleanCode);
    url.setQuery(q);

    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("TsukiLauncher/1.0"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);

    QNetworkReply* reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply, key, cleanStore, cleanCode, callback]() {
        m_inFlight.remove(key);
        const bool ok = (reply->error() == QNetworkReply::NoError);
        const QByteArray body = ok ? reply->readAll() : QByteArray();
        reply->deleteLater();

        QString title;
        const QString resolved = ok ? parseUmuApiResponse(body, &title) : QString();
        if (!resolved.isEmpty() && m_db) {
            m_db->saveCachedUmuId(cleanStore, cleanCode, resolved, title);
            emit umuIdResolved(cleanStore, cleanCode, resolved);
        }
        if (callback) callback(resolved);
    });
}

void UmuIdResolver::lookupForGame(const QString& gameId) {
    if (!m_db || gameId.isEmpty()) return;
    auto gOpt = m_db->getGame(gameId);
    if (!gOpt.has_value() || !gOpt->isEpic()) return;
    lookupAndCache(QStringLiteral("egs"), gOpt->epicAppName);
}

} // namespace Tsuki

