#include "SteamGridDbService.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QUrlQuery>

namespace Tsuki {

SteamGridDbService::SteamGridDbService(AppSettings *settings,
                                       DownloadManager *dl, QObject *parent)
    : QObject(parent), m_settings(settings), m_dl(dl) {}

QString SteamGridDbService::generateFallbackPoster(const QString &gameId,
                                                   const QString &title) {
  const QString artDir =
      AppSettings::artworkDir() + QStringLiteral("/") + gameId;
  QDir().mkpath(artDir);
  const QString svgPath = artDir + QStringLiteral("/fallback_cover.svg");

  QString safeTitle = title.toHtmlEscaped().trimmed();
  if (safeTitle.isEmpty())
    safeTitle = QStringLiteral("Windows Game");

    QString line1 = safeTitle;
    QString line2;
    if (safeTitle.length() > 20) {
      const QStringList words =
          safeTitle.split(QLatin1Char(' '), Qt::SkipEmptyParts);
      QString current;
      int wordIdx = 0;
      while (wordIdx < words.size() &&
             (current.length() + words[wordIdx].length() + 1) <= 18) {
        if (!current.isEmpty())
          current += QLatin1Char(' ');
        current += words[wordIdx];
        wordIdx++;
      }
      line1 = current.isEmpty() ? words.first() : current;
      QString rest;
      while (wordIdx < words.size()) {
        if (!rest.isEmpty())
          rest += QLatin1Char(' ');
        rest += words[wordIdx];
        wordIdx++;
      }
      if (rest.length() > 22)
        rest = rest.left(20) + QStringLiteral("…");
      line2 = rest;
    }

    const QString svg =
        QStringLiteral(
            R"SVG(<svg xmlns="http://www.w3.org/2000/svg" width="600" height="900" viewBox="0 0 600 900">
  <rect width="600" height="900" fill="#101014"/>
  <rect x="20" y="20" width="560" height="860" rx="16" fill="#15151b" stroke="#22222a" stroke-width="1.5"/>
  <g transform="translate(256, 280)" fill="none" stroke="#363642" stroke-width="3" stroke-linecap="round" stroke-linejoin="round">
    <rect x="0" y="0" width="88" height="58" rx="18"/>
    <circle cx="28" cy="29" r="4.5" fill="#363642"/>
    <circle cx="60" cy="29" r="4.5" fill="#363642"/>
    <path d="M44 21 v16 M36 29 h16"/>
  </g>
  <text x="300" y="490" font-family="system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" font-size="34" font-weight="700" fill="#f4f4f5" text-anchor="middle" letter-spacing="-0.3">%1</text>
  <text x="300" y="535" font-family="system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" font-size="28" font-weight="600" fill="#d4d4d8" text-anchor="middle" letter-spacing="-0.3">%2</text>
  <rect x="235" y="780" width="130" height="28" rx="14" fill="#1b1b22" stroke="#272732" stroke-width="1"/>
  <text x="300" y="798" font-family="system-ui, -apple-system, sans-serif" font-size="10" font-weight="700" fill="#71717a" text-anchor="middle" letter-spacing="1.5">LOCAL GAME</text>
</svg>)SVG").arg(line1, line2);

    QFile f(svgPath);
  if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
    f.write(svg.toUtf8());
    f.close();
  }
  return svgPath;
  }

  QString SteamGridDbService::generateFallbackBanner(const QString &gameId,
                                                     const QString &title) {
    const QString artDir =
        AppSettings::artworkDir() + QStringLiteral("/") + gameId;
    QDir().mkpath(artDir);
    const QString svgPath = artDir + QStringLiteral("/fallback_banner.svg");

    QString safeTitle = title.toHtmlEscaped().trimmed();
    if (safeTitle.isEmpty())
      safeTitle = QStringLiteral("Windows Game");
    if (safeTitle.length() > 36)
      safeTitle = safeTitle.left(34) + QStringLiteral("…");

    const QString svg = QStringLiteral(
        R"SVG(<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="620" viewBox="0 0 1920 620">
  <rect width="1920" height="620" fill="#0f0f13"/>
  <rect x="24" y="24" width="1872" height="572" rx="20" fill="#131319" stroke="#202028" stroke-width="1.5"/>
  <text x="960" y="310" font-family="system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" font-size="44" font-weight="700" fill="#f4f4f5" text-anchor="middle" letter-spacing="-0.5">%1</text>
  <text x="960" y="356" font-family="system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif" font-size="15" font-weight="600" fill="#71717a" text-anchor="middle" letter-spacing="1.5">TSUKI GAME LAUNCHER</text>
</svg>)SVG").arg(safeTitle);

    QFile f(svgPath);
  if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
    f.write(svg.toUtf8());
    f.close();
  }
  return svgPath;
  }

  void SteamGridDbService::fetchArtworkForGame(
      const QString &gameId, const QString &gameTitle,
      std::function<void(const QString &, const QString &, const QString &,
                         const QString &, const QString &)>
          onResolved) {
    const QString apiKey = m_settings->steamGridDbApiKey().trimmed();
    if (!apiKey.isEmpty()) {
      fetchFromSteamGridDb(gameId, gameTitle, apiKey, std::move(onResolved));
    } else {
      fetchFromPublicSteamStore(gameId, gameTitle, std::move(onResolved));
    }
  }

  void SteamGridDbService::downloadImageToFile(const QUrl &url,
                                               const QString &destPath,
                                               std::function<void(bool)> done) {
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("TsukiLauncher/1.0"));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                     QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [reply, destPath, done]() {
      if (reply->error() == QNetworkReply::NoError) {
        const QByteArray data = reply->readAll();
        reply->deleteLater();
        if (data.size() > 256) {
          QFile f(destPath);
          if (f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            f.write(data);
            f.close();
            done(true);
            return;
          }
        }
      } else {
        reply->deleteLater();
      }
      done(false);
    });
  }

  void SteamGridDbService::fetchFromSteamGridDb(
      const QString &gameId, const QString &gameTitle, const QString &apiKey,
      std::function<void(const QString &, const QString &, const QString &,
                         const QString &, const QString &)>
          onResolved) {
    const QString encoded =
        QString::fromUtf8(QUrl::toPercentEncoding(gameTitle));
    QNetworkRequest req(
        QUrl(QStringLiteral(
                 "https://www.steamgriddb.com/api/v2/search/autocomplete/%1")
                 .arg(encoded)));
    req.setRawHeader("Authorization", QByteArray("Bearer ") + apiKey.toUtf8());
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("TsukiLauncher/1.0"));

    QNetworkReply *reply = m_nam.get(req);
    connect(
        reply, &QNetworkReply::finished, this,
        [this, reply, gameId, gameTitle, apiKey, onResolved]() {
          if (reply->error() != QNetworkReply::NoError) {
            reply->deleteLater();
            fetchFromPublicSteamStore(gameId, gameTitle, onResolved);
            return;
          }
          const QJsonObject root =
              QJsonDocument::fromJson(reply->readAll()).object();
          reply->deleteLater();
          const QJsonArray data = root["data"].toArray();
          if (data.isEmpty()) {
            fetchFromPublicSteamStore(gameId, gameTitle, onResolved);
            return;
          }

          const QJsonObject first = data.first().toObject();
          const int sgdbId = first["id"].toInt();
          QString releaseYear;
          if (first.contains(QStringLiteral("release_date"))) {
            const qint64 relEpoch =
                first["release_date"].toVariant().toLongLong();
            if (relEpoch > 0) {
              releaseYear = QString::number(
                  QDateTime::fromSecsSinceEpoch(relEpoch).date().year());
            }
          }

          const QString artDir =
              AppSettings::artworkDir() + QStringLiteral("/") + gameId;
          QDir().mkpath(artDir);

          // Fetch grid poster and hero banner from SteamGridDB
          QNetworkRequest gridReq(
              QUrl(QStringLiteral("https://www.steamgriddb.com/api/v2/grids/"
                                  "game/%1?dimensions=600x900")
                       .arg(sgdbId)));
          gridReq.setRawHeader("Authorization",
                               QByteArray("Bearer ") + apiKey.toUtf8());
          QNetworkReply *gridReply = m_nam.get(gridReq);

          connect(
              gridReply, &QNetworkReply::finished, this,
              [this, gridReply, gameId, sgdbId, apiKey, artDir, releaseYear,
               onResolved]() {
                QString gridUrl;
                if (gridReply->error() == QNetworkReply::NoError) {
                  const QJsonArray arr =
                      QJsonDocument::fromJson(gridReply->readAll())
                          .object()["data"]
                          .toArray();
                  if (!arr.isEmpty())
                    gridUrl = arr.first().toObject()["url"].toString();
                }
                gridReply->deleteLater();

                QNetworkRequest heroReq(QUrl(
                    QStringLiteral(
                        "https://www.steamgriddb.com/api/v2/heroes/game/%1")
                        .arg(sgdbId)));
                heroReq.setRawHeader("Authorization",
                                     QByteArray("Bearer ") + apiKey.toUtf8());
                QNetworkReply *heroReply = m_nam.get(heroReq);

                connect(
                    heroReply, &QNetworkReply::finished, this,
                    [this, heroReply, gameId, gridUrl, artDir, releaseYear,
                     onResolved]() {
                      QString heroUrl;
                      if (heroReply->error() == QNetworkReply::NoError) {
                        const QJsonArray arr =
                            QJsonDocument::fromJson(heroReply->readAll())
                                .object()["data"]
                                .toArray();
                        if (!arr.isEmpty())
                          heroUrl = arr.first().toObject()["url"].toString();
                      }
                      heroReply->deleteLater();

                      const QString coverDest =
                          artDir + QStringLiteral("/cover.jpg");
                      const QString bannerDest =
                          artDir + QStringLiteral("/banner.jpg");

                      if (!gridUrl.isEmpty()) {
                        downloadImageToFile(
                            QUrl(gridUrl), coverDest,
                            [this, gameId, coverDest, heroUrl, bannerDest,
                             releaseYear, onResolved](bool okCover) {
                              const QString finalCover =
                                  okCover ? coverDest : QString();
                              if (!heroUrl.isEmpty()) {
                                downloadImageToFile(
                                    QUrl(heroUrl), bannerDest,
                                    [this, gameId, finalCover, bannerDest,
                                     releaseYear, onResolved](bool okBanner) {
                                      const QString finalBanner =
                                          okBanner ? bannerDest : QString();
                                      if (onResolved)
                                        onResolved(finalCover, finalBanner,
                                                   QString(), QString(),
                                                   releaseYear);
                                      emit artworkUpdated(
                                          gameId, finalCover, finalBanner,
                                          QString(), QString(), releaseYear);
                                    });
                              } else {
                                if (onResolved)
                                  onResolved(finalCover, QString(), QString(),
                                             QString(), releaseYear);
                                emit artworkUpdated(gameId, finalCover,
                                                    QString(), QString(),
                                                    QString(), releaseYear);
                              }
                            });
                      } else {
                        if (onResolved)
                          onResolved(QString(), QString(), QString(), QString(),
                                     releaseYear);
                      }
                    });
              });
        });
  }

  void SteamGridDbService::fetchFromPublicSteamStore(
      const QString &gameId, const QString &gameTitle,
      std::function<void(const QString &, const QString &, const QString &,
                         const QString &, const QString &)>
          onResolved) {
    const QString encoded =
        QString::fromUtf8(QUrl::toPercentEncoding(gameTitle));
    const QUrl url(QStringLiteral("https://store.steampowered.com/api/"
                                  "storesearch/?term=%1&l=english&cc=US")
                       .arg(encoded));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("TsukiLauncher/1.0"));

    QNetworkReply *reply = m_nam.get(req);
    connect(
        reply, &QNetworkReply::finished, this,
        [this, reply, gameId, onResolved]() {
          if (reply->error() != QNetworkReply::NoError) {
            reply->deleteLater();
            if (onResolved)
              onResolved(QString(), QString(), QString(), QString(), QString());
            return;
          }
          const QJsonObject root =
              QJsonDocument::fromJson(reply->readAll()).object();
          reply->deleteLater();

          const QJsonArray items = root["items"].toArray();
          if (items.isEmpty()) {
            if (onResolved)
              onResolved(QString(), QString(), QString(), QString(), QString());
            return;
          }

          const QJsonObject first = items.first().toObject();
          const int steamAppId = first["id"].toInt();
          if (steamAppId <= 0) {
            if (onResolved)
              onResolved(QString(), QString(), QString(), QString(), QString());
            return;
          }

          const QString artDir =
              AppSettings::artworkDir() + QStringLiteral("/") + gameId;
          QDir().mkpath(artDir);
          const QString coverDest = artDir + QStringLiteral("/cover.jpg");
          const QString bannerDest = artDir + QStringLiteral("/banner.jpg");
          const QString logoDest = artDir + QStringLiteral("/logo.png");

          const QUrl coverUrl(
              QStringLiteral(
                  "https://shared.akamai.steamstatic.com/store_item_assets/"
                  "steam/apps/%1/library_600x900.jpg")
                  .arg(steamAppId));
          const QUrl bannerUrl(
              QStringLiteral("https://shared.akamai.steamstatic.com/"
                             "store_item_assets/steam/apps/%1/library_hero.jpg")
                  .arg(steamAppId));
          const QUrl logoUrl(
              QStringLiteral("https://shared.akamai.steamstatic.com/"
                             "store_item_assets/steam/apps/%1/logo.png")
                  .arg(steamAppId));

          downloadImageToFile(
              coverUrl, coverDest,
              [this, gameId, coverDest, bannerUrl, bannerDest, logoUrl,
               logoDest, onResolved](bool okCover) {
                const QString finalCover = okCover ? coverDest : QString();
                downloadImageToFile(
                    bannerUrl, bannerDest,
                    [this, gameId, finalCover, bannerDest, logoUrl, logoDest,
                     onResolved](bool okBanner) {
                      const QString finalBanner =
                          okBanner ? bannerDest : QString();
                      downloadImageToFile(
                          logoUrl, logoDest,
                          [this, gameId, finalCover, finalBanner, logoDest,
                           onResolved](bool okLogo) {
                            const QString finalLogo =
                                okLogo ? logoDest : QString();
                            if (onResolved)
                              onResolved(finalCover, finalBanner, finalLogo,
                                         QString(), QString());
                            emit artworkUpdated(gameId, finalCover, finalBanner,
                                                finalLogo, QString(),
                                                QString());
                          });
                    });
              });
        });
  }

  void SteamGridDbService::searchGames(const QString &query) {
    if (query.trimmed().isEmpty()) {
      m_searchResults.clear();
      emit searchResultsChanged();
      return;
    }

    m_isSearching = true;
    emit searchingChanged();

    const QString encoded =
        QString::fromUtf8(QUrl::toPercentEncoding(query.trimmed()));
    const QUrl url(QStringLiteral("https://store.steampowered.com/api/"
                                  "storesearch/?term=%1&l=english&cc=US")
                       .arg(encoded));
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::UserAgentHeader,
                  QStringLiteral("TsukiLauncher/1.0"));

    QNetworkReply *reply = m_nam.get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
      m_isSearching = false;
      emit searchingChanged();

      if (reply->error() != QNetworkReply::NoError) {
        reply->deleteLater();
        return;
      }
      const QJsonArray items =
          QJsonDocument::fromJson(reply->readAll()).object()["items"].toArray();
      reply->deleteLater();

      m_searchResults.clear();
      for (const QJsonValue &v : items) {
        const QJsonObject o = v.toObject();
        const int appId = o["id"].toInt();
        QVariantMap m;
        m["appId"] = QString::number(appId);
        m["name"] = o["name"].toString();
        m["coverUrl"] =
            QStringLiteral(
                "https://shared.akamai.steamstatic.com/store_item_assets/steam/"
                "apps/%1/library_600x900.jpg")
                .arg(appId);
        m["bannerUrl"] =
            QStringLiteral("https://shared.akamai.steamstatic.com/"
                           "store_item_assets/steam/apps/%1/library_hero.jpg")
                .arg(appId);
        m_searchResults.append(m);
      }
      emit searchResultsChanged();
    });
  }

} // namespace Tsuki
