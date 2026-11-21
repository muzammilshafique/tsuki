#pragma once

#include <QByteArray>
#include <QHash>
#include <QList>
#include <QSet>
#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace Tsuki {

struct EpicChunkInfo {
    QString guid;          // 32 uppercase hex chars (FGuid A,B,C,D)
    quint64 hash = 0;      // Rolling hash used in CDN filename
    QByteArray shaHash;    // 20-byte SHA-1 of uncompressed chunk
    quint8 groupNum = 0;   // Subdirectory number (00..99)
    quint32 windowSize = 0;// Uncompressed chunk size (typically 1 MiB)
    qint64 fileSize = 0;   // Compressed size on CDN

    QString relativeChunkPath(const QString& chunksDir) const;
};

struct EpicChunkPart {
    QString chunkGuid;     // References EpicChunkInfo::guid
    quint32 offset = 0;    // Offset within uncompressed chunk
    quint32 size = 0;      // Byte count to read from chunk
};

struct EpicFileManifest {
    QString filename;      // Relative path inside game install folder
    QString symlinkTarget;
    QByteArray shaHash;    // 20-byte SHA-1 of assembled file
    quint8 metaFlags = 0;  // 0x01: ReadOnly, 0x02: Compressed, 0x04: Executable
    QStringList installTags;
    QList<EpicChunkPart> chunkParts;
    qint64 fileSize = 0;   // Sum of chunkPart sizes

    bool isExecutable() const { return (metaFlags & 0x04) != 0; }
    bool isReadOnly() const { return (metaFlags & 0x01) != 0; }
};

struct EpicInstallTagInfo {
    QString tag;
    qint64 downloadSize = 0;
    qint64 installSize = 0;
    int fileCount = 0;
};

struct EpicManifestDiff {
    QList<EpicFileManifest> unchangedFiles;
    QList<EpicFileManifest> modifiedOrNewFiles;
    QStringList removedFiles;
    QSet<QString> requiredChunkGuids;
    qint64 deltaDownloadBytes = 0;
    qint64 deltaInstallBytes = 0;
};

struct EpicManifest {
    bool isValid = false;
    int featureLevel = 0;
    bool isFileData = false;
    quint32 appId = 0;
    QString appName;
    QString buildVersion;
    QString launchExe;
    QString launchCommand;
    QString prereqName;
    QString prereqPath;
    QString prereqArgs;
    QStringList prereqIds;
    QString uninstallActionPath;
    QString uninstallActionArgs;
    QVariantMap customFields;

    QList<EpicChunkInfo> chunks;
    QHash<QString, int> chunkIndexByGuid;
    QList<EpicFileManifest> files;

    qint64 totalDownloadSize = 0;
    qint64 totalInstallSize = 0;

    QString chunksSubdir() const;
    const EpicChunkInfo* findChunk(const QString& guid) const;
    QList<EpicInstallTagInfo> computeInstallTags() const;
    static bool fileMatchesTags(const EpicFileManifest& fm, const QStringList& selectedTags);
};

class EpicManifestParser {
public:
    static bool parse(const QByteArray& rawBytes, EpicManifest& outManifest, QString* outError = nullptr);
    static bool parseBinary(const QByteArray& rawBytes, EpicManifest& outManifest, QString* outError = nullptr);
    static bool parseJson(const QByteArray& rawBytes, EpicManifest& outManifest, QString* outError = nullptr);

    static EpicManifestDiff diffManifests(const EpicManifest& oldManifest,
                                          const EpicManifest& newManifest,
                                          const QStringList& selectedTags = QStringList());

    static bool decompressChunk(const QByteArray& rawChunkBytes,
                                const QByteArray& expectedSha1,
                                QByteArray& outUncompressed,
                                QString* outError = nullptr);

    static QByteArray buildChunk(const QString& guidHex32,
                                 const QByteArray& uncompressedData,
                                 quint64* outHash = nullptr,
                                 QByteArray* outSha1 = nullptr);

    static QByteArray buildJsonManifest(const QString& appName,
                                        const QString& buildVersion,
                                        const QList<EpicFileManifest>& files,
                                        const QList<EpicChunkInfo>& chunks);

    static bool zlibInflate(const QByteArray& compressed,
                            QByteArray& outData,
                            quint32 expectedSizeHint = 0,
                            QString* outError = nullptr);

    static bool zlibDeflate(const QByteArray& raw,
                            QByteArray& outCompressed,
                            QString* outError = nullptr);

    static QString formatFGuid(const uchar* bytes16);
    static quint64 computeRollingHash(const QByteArray& data);
};

} // namespace Tsuki

