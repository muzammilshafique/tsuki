#pragma once

#include "../core/AppSettings.h"
#include "DownloadManager.h"
#include <QNetworkAccessManager>
#include <QObject>
#include <QVariantList>
#include <functional>

namespace Tsuki {

class SteamGridDbService : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool isSearching READ isSearching NOTIFY searchingChanged)
  Q_PROPERTY(
      QVariantList searchResults READ searchResults NOTIFY searchResultsChanged)

public:
  explicit SteamGridDbService(AppSettings *settings, DownloadManager *dl,
                              QObject *parent = nullptr);

  bool isSearching() const { return m_isSearching; }
  QVariantList searchResults() const { return m_searchResults; }

  // Automatically fetch metadata & artwork for a game (uses SteamGridDB API v2
  // if key set, else Steam Store public CDN + local SVG fallback)
  void fetchArtworkForGame(
      const QString &gameId, const QString &gameTitle,
      std::function<void(const QString &cover, const QString &banner,
                         const QString &logo, const QString &icon,
                         const QString &year)>
          onResolved);

  Q_INVOKABLE void searchGames(const QString &query);

  // Generate sleek fallback SVG poster & banner on disk when offline or before
  // remote artwork finishes
  static QString generateFallbackPoster(const QString &gameId,
                                        const QString &title);
  static QString generateFallbackBanner(const QString &gameId,
                                        const QString &title);

  void downloadImageToFile(const QUrl &url, const QString &destPath,
                           std::function<void(bool)> done);

signals:
  void searchingChanged();
  void searchResultsChanged();
  void artworkUpdated(const QString &gameId, const QString &cover,
                      const QString &banner, const QString &logo,
                      const QString &icon, const QString &year);

private:
  AppSettings *m_settings;
  DownloadManager *m_dl;
  QNetworkAccessManager m_nam;
  bool m_isSearching = false;
  QVariantList m_searchResults;

  void fetchFromSteamGridDb(
      const QString &gameId, const QString &gameTitle, const QString &apiKey,
      std::function<void(const QString &, const QString &, const QString &,
                         const QString &, const QString &)>
          onResolved);
  void fetchFromPublicSteamStore(
      const QString &gameId, const QString &gameTitle,
      std::function<void(const QString &, const QString &, const QString &,
                         const QString &, const QString &)>
          onResolved);
};

} // namespace Tsuki
