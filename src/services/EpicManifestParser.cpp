#include "EpicManifestParser.h"

#include <QCryptographicHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QtEndian>
#include <cstring>
#include <zlib.h>

namespace Tsuki {

namespace {

constexpr quint32 kManifestMagic = 0x44BEC00Cu;
constexpr quint32 kChunkMagic = 0xB1FE3AA2u;
constexpr quint32 kMaxInflatedBytes = 256u * 1024u * 1024u; // 256 MiB safety bound

class BinaryReader {
public:
    explicit BinaryReader(const QByteArray& data)
        : m_data(data)
        , m_ptr(reinterpret_cast<const uchar*>(data.constData()))
        , m_size(data.size())
    {
    }

    qsizetype pos() const { return m_pos; }
    qsizetype size() const { return m_size; }
    bool atEnd() const { return m_pos >= m_size; }

    bool canRead(qsizetype bytes) const {
        return bytes >= 0 && m_pos <= m_size && (m_size - m_pos) >= bytes;
    }

    bool seek(qsizetype newPos) {
        if (newPos < 0 || newPos > m_size) return false;
        m_pos = newPos;
        return true;
    }

    bool readUInt8(quint8& out) {
        if (!canRead(1)) return false;
        out = m_ptr[m_pos++];
        return true;
    }

    bool readUInt32(quint32& out) {
        if (!canRead(4)) return false;
        out = qFromLittleEndian<quint32>(m_ptr + m_pos);
        m_pos += 4;
        return true;
    }

    bool readInt32(qint32& out) {
        if (!canRead(4)) return false;
        out = qFromLittleEndian<qint32>(m_ptr + m_pos);
        m_pos += 4;
        return true;
    }

    bool readUInt64(quint64& out) {
        if (!canRead(8)) return false;
        out = qFromLittleEndian<quint64>(m_ptr + m_pos);
        m_pos += 8;
        return true;
    }

    bool readInt64(qint64& out) {
        if (!canRead(8)) return false;
        out = qFromLittleEndian<qint64>(m_ptr + m_pos);
        m_pos += 8;
        return true;
    }

    bool readBytes(qsizetype len, QByteArray& out) {
        if (!canRead(len)) return false;
        out = QByteArray(reinterpret_cast<const char*>(m_ptr + m_pos), len);
        m_pos += len;
        return true;
    }

    bool readRawPtr(qsizetype len, const uchar*& outPtr) {
        if (!canRead(len)) return false;
        outPtr = m_ptr + m_pos;
        m_pos += len;
        return true;
    }

    bool readFString(QString& out) {
        qint32 length = 0;
        if (!readInt32(length)) return false;
        if (length == 0) {
            out.clear();
            return true;
        }
        if (length > 0) {
            if (length > 16 * 1024 * 1024 || !canRead(length)) return false;
            qsizetype actualLen = length;
            if (m_ptr[m_pos + length - 1] == '\0') {
                actualLen = length - 1;
            }
            out = QString::fromUtf8(reinterpret_cast<const char*>(m_ptr + m_pos), actualLen);
            m_pos += length;
            return true;
        } else {
            const qint64 charCount = -static_cast<qint64>(length);
            const qint64 byteLen = charCount * 2;
            if (byteLen <= 0 || byteLen > 16 * 1024 * 1024 || !canRead(byteLen)) return false;
            qsizetype u16Count = static_cast<qsizetype>(charCount);
            const char16_t* u16Ptr = reinterpret_cast<const char16_t*>(m_ptr + m_pos);
            if (u16Count > 0 && u16Ptr[u16Count - 1] == u'\0') {
                --u16Count;
            }
            out = QString::fromUtf16(u16Ptr, u16Count);
            m_pos += static_cast<qsizetype>(byteLen);
            return true;
        }
    }

private:
    const QByteArray& m_data;
    const uchar* m_ptr = nullptr;
    qsizetype m_size = 0;
    qsizetype m_pos = 0;
};

} // namespace

QString EpicChunkInfo::relativeChunkPath(const QString& chunksDir) const {
    const QString groupStr = QStringLiteral("%1").arg(groupNum, 2, 10, QLatin1Char('0'));
    const QString hashStr = QStringLiteral("%1").arg(hash, 16, 16, QLatin1Char('0')).toUpper();
    return QStringLiteral("%1/%2/%3_%4.chunk").arg(chunksDir, groupStr, hashStr, guid);
}

QString EpicManifest::chunksSubdir() const {
    if (featureLevel >= 15) return QStringLiteral("ChunksV4");
    if (featureLevel >= 6) return QStringLiteral("ChunksV3");
    if (featureLevel >= 3) return QStringLiteral("ChunksV2");
    return QStringLiteral("Chunks");
}

const EpicChunkInfo* EpicManifest::findChunk(const QString& guid) const {
    const auto it = chunkIndexByGuid.constFind(guid);
    if (it == chunkIndexByGuid.constEnd()) return nullptr;
    const int idx = it.value();
    if (idx < 0 || idx >= chunks.size()) return nullptr;
    return &chunks.at(idx);
}

QString EpicManifestParser::formatFGuid(const uchar* bytes16) {
    const quint32 a = qFromLittleEndian<quint32>(bytes16);
    const quint32 b = qFromLittleEndian<quint32>(bytes16 + 4);
    const quint32 c = qFromLittleEndian<quint32>(bytes16 + 8);
    const quint32 d = qFromLittleEndian<quint32>(bytes16 + 12);
    return QStringLiteral("%1%2%3%4")
        .arg(a, 8, 16, QLatin1Char('0'))
        .arg(b, 8, 16, QLatin1Char('0'))
        .arg(c, 8, 16, QLatin1Char('0'))
        .arg(d, 8, 16, QLatin1Char('0'))
        .toUpper();
}

bool EpicManifestParser::zlibInflate(const QByteArray& compressed,
                                       QByteArray& outData,
                                       quint32 expectedSizeHint,
                                       QString* outError) {
    outData.clear();
    if (compressed.isEmpty()) {
        if (outError) *outError = QStringLiteral("Empty compressed buffer");
        return false;
    }

    z_stream zs{};
    if (inflateInit(&zs) != Z_OK) {
        if (outError) *outError = QStringLiteral("zlib inflateInit failed");
        return false;
    }

    zs.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(compressed.constData()));
    zs.avail_in = static_cast<uInt>(compressed.size());

    const qsizetype initialCap = (expectedSizeHint > 0 && expectedSizeHint <= kMaxInflatedBytes)
                                     ? static_cast<qsizetype>(expectedSizeHint)
                                     : qMin<qsizetype>(qMax<qsizetype>(compressed.size() * 4, 65536), kMaxInflatedBytes);
    outData.reserve(initialCap);

    char buffer[65536];
    int ret = Z_OK;
    do {
        zs.next_out = reinterpret_cast<Bytef*>(buffer);
        zs.avail_out = sizeof(buffer);
        ret = inflate(&zs, Z_NO_FLUSH);

        const qsizetype have = static_cast<qsizetype>(sizeof(buffer) - zs.avail_out);
        if (have > 0) {
            if (static_cast<quint64>(outData.size()) + static_cast<quint64>(have) > kMaxInflatedBytes) {
                inflateEnd(&zs);
                if (outError) *outError = QStringLiteral("Inflated manifest exceeds safety limit");
                return false;
            }
            outData.append(buffer, have);
        }

        if (ret != Z_OK && ret != Z_STREAM_END) {
            inflateEnd(&zs);
            if (outError) *outError = QStringLiteral("zlib inflate error (%1)").arg(ret);
            return false;
        }
    } while (ret != Z_STREAM_END);

    inflateEnd(&zs);
    return true;
}

bool EpicManifestParser::parse(const QByteArray& rawBytes, EpicManifest& outManifest, QString* outError) {
    outManifest = EpicManifest{};
    if (rawBytes.size() >= 4) {
        const quint32 magic = qFromLittleEndian<quint32>(reinterpret_cast<const uchar*>(rawBytes.constData()));
        if (magic == kManifestMagic) {
            return parseBinary(rawBytes, outManifest, outError);
        }
    }
    const QByteArray trimmed = rawBytes.trimmed();
    if (trimmed.startsWith('{')) {
        return parseJson(trimmed, outManifest, outError);
    }
    if (outError) *outError = QStringLiteral("Unrecognized Epic manifest format");
    return false;
}

bool EpicManifestParser::parseBinary(const QByteArray& rawBytes, EpicManifest& outManifest, QString* outError) {
    BinaryReader hr(rawBytes);
    quint32 magic = 0;
    quint32 headerSize = 0;
    quint32 dataSizeUncompressed = 0;
    quint32 dataSizeCompressed = 0;
    QByteArray shaHash;
    quint8 storedAs = 0;
    quint32 version = 0;

    if (!hr.readUInt32(magic) || magic != kManifestMagic ||
        !hr.readUInt32(headerSize) ||
        !hr.readUInt32(dataSizeUncompressed) ||
        !hr.readUInt32(dataSizeCompressed) ||
        !hr.readBytes(20, shaHash) ||
        !hr.readUInt8(storedAs)) {
        if (outError) *outError = QStringLiteral("Truncated Epic binary manifest header");
        return false;
    }

    if (headerSize < 37 || headerSize > static_cast<quint32>(rawBytes.size())) {
        if (outError) *outError = QStringLiteral("Invalid Epic manifest header size");
        return false;
    }
    if (headerSize >= 41) {
        if (!hr.readUInt32(version)) {
            if (outError) *outError = QStringLiteral("Truncated Epic manifest header version");
            return false;
        }
    }
    Q_UNUSED(version);

    if (storedAs & 0x02u) {
        if (outError) *outError = QStringLiteral("Encrypted Epic manifests are not supported");
        return false;
    }

    const qsizetype payloadAvailable = rawBytes.size() - static_cast<qsizetype>(headerSize);
    if (payloadAvailable <= 0) {
        if (outError) *outError = QStringLiteral("Empty Epic manifest payload");
        return false;
    }

    QByteArray payload;
    const qsizetype sliceLen = (dataSizeCompressed > 0 && static_cast<qsizetype>(dataSizeCompressed) <= payloadAvailable)
                                   ? static_cast<qsizetype>(dataSizeCompressed)
                                   : payloadAvailable;
    const QByteArray rawPayload = rawBytes.mid(static_cast<qsizetype>(headerSize), sliceLen);

    if (storedAs & 0x01u) {
        if (!zlibInflate(rawPayload, payload, dataSizeUncompressed, outError)) {
            return false;
        }
    } else {
        payload = rawPayload;
    }

    // Verify SHA-1 if present (non-zero)
    bool hasNonZeroSha = false;
    for (char c : shaHash) {
        if (c != 0) {
            hasNonZeroSha = true;
            break;
        }
    }
    if (hasNonZeroSha) {
        const QByteArray actualSha = QCryptographicHash::hash(payload, QCryptographicHash::Sha1);
        if (actualSha != shaHash) {
            if (outError) *outError = QStringLiteral("Epic manifest SHA-1 checksum mismatch");
            return false;
        }
    }

    BinaryReader r(payload);

    // ── 1. FManifestMeta ───────────────────────────────────────────────────────
    const qsizetype metaStart = r.pos();
    quint32 metaSize = 0;
    quint8 metaVersion = 0;
    qint32 featureLevel = 0;
    quint8 isFileData = 0;
    if (!r.readUInt32(metaSize) || !r.readUInt8(metaVersion) ||
        metaSize < 5 || metaStart + static_cast<qsizetype>(metaSize) > r.size()) {
        if (outError) *outError = QStringLiteral("Corrupt FManifestMeta section");
        return false;
    }
    if (!r.readInt32(featureLevel) ||
        !r.readUInt8(isFileData) ||
        !r.readUInt32(outManifest.appId) ||
        !r.readFString(outManifest.appName) ||
        !r.readFString(outManifest.buildVersion) ||
        !r.readFString(outManifest.launchExe) ||
        !r.readFString(outManifest.launchCommand)) {
        if (outError) *outError = QStringLiteral("Failed to read FManifestMeta fields");
        return false;
    }
    outManifest.featureLevel = featureLevel;
    outManifest.isFileData = (isFileData != 0);

    quint32 prereqCount = 0;
    if (!r.readUInt32(prereqCount) || prereqCount > 1024) {
        if (outError) *outError = QStringLiteral("Invalid prereqIds count");
        return false;
    }
    for (quint32 i = 0; i < prereqCount; ++i) {
        QString pid;
        if (!r.readFString(pid)) {
            if (outError) *outError = QStringLiteral("Failed reading prereqId");
            return false;
        }
        outManifest.prereqIds.append(pid);
    }
    if (!r.readFString(outManifest.prereqName) ||
        !r.readFString(outManifest.prereqPath) ||
        !r.readFString(outManifest.prereqArgs)) {
        if (outError) *outError = QStringLiteral("Failed reading prereq metadata");
        return false;
    }
    if (metaVersion >= 1 && r.pos() < metaStart + static_cast<qsizetype>(metaSize)) {
        r.readFString(outManifest.uninstallActionPath);
        r.readFString(outManifest.uninstallActionArgs);
    }
    r.seek(metaStart + static_cast<qsizetype>(metaSize));

    // ── 2. FChunkDataList (Columnar SoA) ───────────────────────────────────────
    const qsizetype chunkStart = r.pos();
    quint32 chunkListSize = 0;
    quint8 chunkDataVersion = 0;
    qint32 chunkCount = 0;
    if (!r.readUInt32(chunkListSize) || !r.readUInt8(chunkDataVersion) ||
        !r.readInt32(chunkCount) ||
        chunkListSize < 9 || chunkCount < 0 || chunkCount > 5000000 ||
        chunkStart + static_cast<qsizetype>(chunkListSize) > r.size()) {
        if (outError) *outError = QStringLiteral("Corrupt FChunkDataList section");
        return false;
    }
    Q_UNUSED(chunkDataVersion);

    outManifest.chunks.resize(chunkCount);
    outManifest.chunkIndexByGuid.reserve(chunkCount);

    for (qint32 i = 0; i < chunkCount; ++i) {
        const uchar* gPtr = nullptr;
        if (!r.readRawPtr(16, gPtr)) {
            if (outError) *outError = QStringLiteral("Truncated chunk GUIDs");
            return false;
        }
        const QString guidStr = formatFGuid(gPtr);
        outManifest.chunks[i].guid = guidStr;
        outManifest.chunkIndexByGuid.insert(guidStr, i);
    }
    for (qint32 i = 0; i < chunkCount; ++i) {
        if (!r.readUInt64(outManifest.chunks[i].hash)) {
            if (outError) *outError = QStringLiteral("Truncated chunk hashes");
            return false;
        }
    }
    for (qint32 i = 0; i < chunkCount; ++i) {
        if (!r.readBytes(20, outManifest.chunks[i].shaHash)) {
            if (outError) *outError = QStringLiteral("Truncated chunk SHA-1s");
            return false;
        }
    }
    for (qint32 i = 0; i < chunkCount; ++i) {
        if (!r.readUInt8(outManifest.chunks[i].groupNum)) {
            if (outError) *outError = QStringLiteral("Truncated chunk group numbers");
            return false;
        }
    }
    for (qint32 i = 0; i < chunkCount; ++i) {
        if (!r.readUInt32(outManifest.chunks[i].windowSize)) {
            if (outError) *outError = QStringLiteral("Truncated chunk window sizes");
            return false;
        }
    }
    qint64 totalDl = 0;
    for (qint32 i = 0; i < chunkCount; ++i) {
        if (!r.readInt64(outManifest.chunks[i].fileSize)) {
            if (outError) *outError = QStringLiteral("Truncated chunk file sizes");
            return false;
        }
        if (outManifest.chunks[i].fileSize > 0) {
            totalDl += outManifest.chunks[i].fileSize;
        }
    }
    outManifest.totalDownloadSize = totalDl;
    r.seek(chunkStart + static_cast<qsizetype>(chunkListSize));

    // ── 3. FFileManifestList (Columnar SoA) ──────────────────────────────────
    const qsizetype fileStart = r.pos();
    quint32 fileListSize = 0;
    quint8 fileDataVersion = 0;
    qint32 fileCount = 0;
    if (!r.readUInt32(fileListSize) || !r.readUInt8(fileDataVersion) ||
        !r.readInt32(fileCount) ||
        fileListSize < 9 || fileCount < 0 || fileCount > 5000000 ||
        fileStart + static_cast<qsizetype>(fileListSize) > r.size()) {
        if (outError) *outError = QStringLiteral("Corrupt FFileManifestList section");
        return false;
    }
    Q_UNUSED(fileDataVersion);

    outManifest.files.resize(fileCount);

    for (qint32 i = 0; i < fileCount; ++i) {
        if (!r.readFString(outManifest.files[i].filename)) {
            if (outError) *outError = QStringLiteral("Truncated file names");
            return false;
        }
        outManifest.files[i].filename.replace(QLatin1Char('\\'), QLatin1Char('/'));
    }
    for (qint32 i = 0; i < fileCount; ++i) {
        if (!r.readFString(outManifest.files[i].symlinkTarget)) {
            if (outError) *outError = QStringLiteral("Truncated symlink targets");
            return false;
        }
    }
    for (qint32 i = 0; i < fileCount; ++i) {
        if (!r.readBytes(20, outManifest.files[i].shaHash)) {
            if (outError) *outError = QStringLiteral("Truncated file SHA-1s");
            return false;
        }
    }
    for (qint32 i = 0; i < fileCount; ++i) {
        if (!r.readUInt8(outManifest.files[i].metaFlags)) {
            if (outError) *outError = QStringLiteral("Truncated file meta flags");
            return false;
        }
    }
    for (qint32 i = 0; i < fileCount; ++i) {
        quint32 tagCount = 0;
        if (!r.readUInt32(tagCount) || tagCount > 4096) {
            if (outError) *outError = QStringLiteral("Invalid file installTags count");
            return false;
        }
        for (quint32 t = 0; t < tagCount; ++t) {
            QString tag;
            if (!r.readFString(tag)) {
                if (outError) *outError = QStringLiteral("Truncated file installTag");
                return false;
            }
            outManifest.files[i].installTags.append(tag);
        }
    }
    qint64 totalInstall = 0;
    for (qint32 i = 0; i < fileCount; ++i) {
        quint32 partCount = 0;
        if (!r.readUInt32(partCount) || partCount > 1000000) {
            if (outError) *outError = QStringLiteral("Invalid file chunkParts count");
            return false;
        }
        outManifest.files[i].chunkParts.reserve(static_cast<int>(partCount));
        qint64 fSize = 0;
        for (quint32 p = 0; p < partCount; ++p) {
            const qsizetype partStart = r.pos();
            quint32 partSize = 0;
            const uchar* gPtr = nullptr;
            quint32 offset = 0;
            quint32 size = 0;
            if (!r.readUInt32(partSize) || partSize < 28 ||
                partStart + static_cast<qsizetype>(partSize) > r.size() ||
                !r.readRawPtr(16, gPtr) ||
                !r.readUInt32(offset) ||
                !r.readUInt32(size)) {
                if (outError) *outError = QStringLiteral("Corrupt FChunkPart entry");
                return false;
            }
            EpicChunkPart part;
            part.chunkGuid = formatFGuid(gPtr);
            part.offset = offset;
            part.size = size;
            outManifest.files[i].chunkParts.append(part);
            fSize += static_cast<qint64>(size);
            r.seek(partStart + static_cast<qsizetype>(partSize));
        }
        outManifest.files[i].fileSize = fSize;
        totalInstall += fSize;
    }
    outManifest.totalInstallSize = totalInstall;
    r.seek(fileStart + static_cast<qsizetype>(fileListSize));

    // ── 4. FCustomFields (optional) ───────────────────────────────────────────
    if (!r.atEnd() && r.canRead(9)) {
        const qsizetype cfStart = r.pos();
        quint32 cfSize = 0;
        quint8 cfVer = 0;
        qint32 cfCount = 0;
        if (r.readUInt32(cfSize) && r.readUInt8(cfVer) && r.readInt32(cfCount) &&
            cfCount >= 0 && cfCount <= 10000 &&
            cfStart + static_cast<qsizetype>(cfSize) <= r.size()) {
            Q_UNUSED(cfVer);
            QStringList keys;
            keys.reserve(cfCount);
            bool ok = true;
            for (qint32 i = 0; i < cfCount; ++i) {
                QString k;
                if (!r.readFString(k)) { ok = false; break; }
                keys.append(k);
            }
            if (ok) {
                for (qint32 i = 0; i < cfCount; ++i) {
                    QString v;
                    if (!r.readFString(v)) break;
                    outManifest.customFields.insert(keys.at(i), v);
                }
            }
        }
    }

    outManifest.launchExe.replace(QLatin1Char('\\'), QLatin1Char('/'));
    outManifest.isValid = true;
    return true;
}

bool EpicManifestParser::parseJson(const QByteArray& rawBytes, EpicManifest& outManifest, QString* outError) {
    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(rawBytes, &err);
    if (!doc.isObject()) {
        if (outError) *outError = QStringLiteral("Invalid JSON manifest: %1").arg(err.errorString());
        return false;
    }
    const QJsonObject root = doc.object();
    const QString verStr = root.value(QStringLiteral("ManifestFileVersion")).toString();
    if (!verStr.isEmpty()) {
        bool ok = false;
        const int v = verStr.toInt(&ok);
        if (ok) outManifest.featureLevel = v;
    } else {
        outManifest.featureLevel = root.value(QStringLiteral("ManifestFileVersion")).toInt(18);
    }

    outManifest.isFileData = root.value(QStringLiteral("bIsFileData")).toBool(false);
    outManifest.appId = static_cast<quint32>(root.value(QStringLiteral("AppID")).toString().toUInt());
    outManifest.appName = root.value(QStringLiteral("AppNameString")).toString();
    outManifest.buildVersion = root.value(QStringLiteral("BuildVersionString")).toString();
    outManifest.launchExe = root.value(QStringLiteral("LaunchExeString")).toString();
    outManifest.launchExe.replace(QLatin1Char('\\'), QLatin1Char('/'));
    outManifest.launchCommand = root.value(QStringLiteral("LaunchCommand")).toString();
    outManifest.prereqName = root.value(QStringLiteral("PrereqName")).toString();
    outManifest.prereqPath = root.value(QStringLiteral("PrereqPath")).toString();
    outManifest.prereqArgs = root.value(QStringLiteral("PrereqArgs")).toString();

    const QJsonObject hashObj = root.value(QStringLiteral("ChunkHashList")).toObject();
    const QJsonObject shaObj = root.value(QStringLiteral("ChunkShaList")).toObject();
    const QJsonObject groupObj = root.value(QStringLiteral("DataGroupList")).toObject();
    const QJsonObject sizeObj = root.value(QStringLiteral("ChunkFilesizeList")).toObject();

    auto decodeBlobInt = [](const QString& blob, int strideChars, quint64& out) -> bool {
        if (blob.size() < strideChars) return false;
        quint64 val = 0;
        for (int i = 0; i + 2 < blob.size() && i < 24; i += 3) {
            bool ok = false;
            const quint64 b = blob.mid(i, 3).toULongLong(&ok);
            if (!ok) return false;
            val = (val << 8) | (b & 0xFFu);
        }
        out = val;
        return true;
    };

    qint64 totalDl = 0;
    for (auto it = hashObj.constBegin(); it != hashObj.constEnd(); ++it) {
        const QString guid = it.key().toUpper();
        EpicChunkInfo info;
        info.guid = guid;

        const QString hStr = it.value().toString();
        bool hexOk = false;
        info.hash = hStr.toULongLong(&hexOk, 16);
        if (!hexOk) {
            decodeBlobInt(hStr, 3, info.hash);
        }

        const QString shaHex = shaObj.value(it.key()).toString();
        if (shaHex.size() == 40) {
            info.shaHash = QByteArray::fromHex(shaHex.toLatin1());
        }

        info.groupNum = static_cast<quint8>(groupObj.value(it.key()).toString().toUInt());
        const QString fsStr = sizeObj.value(it.key()).toString();
        bool fsOk = false;
        info.fileSize = fsStr.toLongLong(&fsOk);
        if (!fsOk) {
            quint64 fsVal = 0;
            if (decodeBlobInt(fsStr, 3, fsVal)) {
                info.fileSize = static_cast<qint64>(fsVal);
            }
        }
        totalDl += info.fileSize;
        outManifest.chunkIndexByGuid.insert(guid, outManifest.chunks.size());
        outManifest.chunks.append(info);
    }
    outManifest.totalDownloadSize = totalDl;

    const QJsonArray filesArr = root.value(QStringLiteral("FileManifestList")).toArray();
    qint64 totalInst = 0;
    for (const QJsonValue& fv : filesArr) {
        const QJsonObject fo = fv.toObject();
        EpicFileManifest fm;
        fm.filename = fo.value(QStringLiteral("Filename")).toString();
        fm.filename.replace(QLatin1Char('\\'), QLatin1Char('/'));
        fm.symlinkTarget = fo.value(QStringLiteral("SymlinkTarget")).toString();
        if (fo.value(QStringLiteral("bIsReadOnly")).toBool(false)) fm.metaFlags |= 0x01u;
        if (fo.value(QStringLiteral("bIsCompressed")).toBool(false)) fm.metaFlags |= 0x02u;
        if (fo.value(QStringLiteral("bIsUnixExecutable")).toBool(false)) fm.metaFlags |= 0x04u;

        const QString fileHashStr = fo.value(QStringLiteral("FileHash")).toString().trimmed();
        if (fileHashStr.size() == 40) {
            fm.shaHash = QByteArray::fromHex(fileHashStr.toLatin1());
        } else if (fileHashStr.size() == 60) {
            QByteArray sha;
            sha.reserve(20);
            bool allOk = true;
            for (int hi = 0; hi < 60; hi += 3) {
                bool ok = false;
                const uint b = fileHashStr.mid(hi, 3).toUInt(&ok);
                if (!ok || b > 255u) { allOk = false; break; }
                sha.append(static_cast<char>(b));
            }
            if (allOk) fm.shaHash = sha;
        }

        const QJsonArray tagsArr = fo.value(QStringLiteral("InstallTags")).toArray();
        for (const QJsonValue& tv : tagsArr) fm.installTags.append(tv.toString());

        const QJsonArray partsArr = fo.value(QStringLiteral("FileChunkParts")).toArray();
        qint64 fSize = 0;
        for (const QJsonValue& pv : partsArr) {
            const QJsonObject po = pv.toObject();
            EpicChunkPart part;
            part.chunkGuid = po.value(QStringLiteral("Guid")).toString().toUpper();
            part.offset = static_cast<quint32>(po.value(QStringLiteral("Offset")).toString().toUInt());
            if (part.offset == 0) part.offset = static_cast<quint32>(po.value(QStringLiteral("Offset")).toInt());
            part.size = static_cast<quint32>(po.value(QStringLiteral("Size")).toString().toUInt());
            if (part.size == 0) part.size = static_cast<quint32>(po.value(QStringLiteral("Size")).toInt());
            fm.chunkParts.append(part);
            fSize += static_cast<qint64>(part.size);
        }
        fm.fileSize = fSize;
        totalInst += fSize;
        outManifest.files.append(fm);
    }
    outManifest.totalInstallSize = totalInst;
    outManifest.isValid = !outManifest.appName.isEmpty() || !outManifest.files.isEmpty();
    return outManifest.isValid;
}

bool EpicManifestParser::decompressChunk(const QByteArray& rawChunkBytes,
                                           const QByteArray& expectedSha1,
                                           QByteArray& outUncompressed,
                                           QString* outError) {
    outUncompressed.clear();
    BinaryReader r(rawChunkBytes);
    quint32 magic = 0;
    quint32 version = 0;
    quint32 headerSize = 0;
    quint32 compressedSize = 0;
    const uchar* guidPtr = nullptr;
    quint64 hash = 0;
    quint8 storedAs = 0;

    if (!r.readUInt32(magic) || magic != kChunkMagic ||
        !r.readUInt32(version) ||
        !r.readUInt32(headerSize) ||
        !r.readUInt32(compressedSize) ||
        !r.readRawPtr(16, guidPtr) ||
        !r.readUInt64(hash) ||
        !r.readUInt8(storedAs)) {
        if (outError) *outError = QStringLiteral("Invalid Epic chunk header");
        return false;
    }
    Q_UNUSED(guidPtr);
    Q_UNUSED(hash);

    if (headerSize < 41 || headerSize > static_cast<quint32>(rawChunkBytes.size())) {
        if (outError) *outError = QStringLiteral("Invalid Epic chunk header size");
        return false;
    }

    QByteArray headerSha1;
    if (version >= 2 && r.canRead(20)) {
        r.readBytes(20, headerSha1);
    }

    if (storedAs & 0x02u) {
        if (outError) *outError = QStringLiteral("Encrypted Epic chunks are not supported");
        return false;
    }

    const qsizetype payloadAvail = rawChunkBytes.size() - static_cast<qsizetype>(headerSize);
    const qsizetype payloadLen = (compressedSize > 0 && static_cast<qsizetype>(compressedSize) <= payloadAvail)
                                     ? static_cast<qsizetype>(compressedSize)
                                     : payloadAvail;
    const QByteArray payload = rawChunkBytes.mid(static_cast<qsizetype>(headerSize), payloadLen);

    if (storedAs & 0x01u) {
        if (!zlibInflate(payload, outUncompressed, 1024u * 1024u, outError)) {
            return false;
        }
    } else {
        outUncompressed = payload;
    }

    const QByteArray actualSha1 = QCryptographicHash::hash(outUncompressed, QCryptographicHash::Sha1);
    if (!expectedSha1.isEmpty() && actualSha1 != expectedSha1) {
        if (outError) *outError = QStringLiteral("Chunk SHA-1 verification failed");
        return false;
    }
    if (expectedSha1.isEmpty() && headerSha1.size() == 20) {
        bool nonZero = false;
        for (char c : headerSha1) {
            if (c != 0) { nonZero = true; break; }
        }
        if (nonZero && actualSha1 != headerSha1) {
            if (outError) *outError = QStringLiteral("Chunk header SHA-1 verification failed");
            return false;
        }
    }

    return true;
}

bool EpicManifest::fileMatchesTags(const EpicFileManifest& fm, const QStringList& selectedTags) {
    if (fm.installTags.isEmpty()) {
        return true; // Base files are always required
    }
    if (selectedTags.isEmpty()) {
        return true; // Empty selection means install everything (default backward-compatible behavior)
    }
    for (const QString& tag : fm.installTags) {
        if (selectedTags.contains(tag, Qt::CaseInsensitive)) {
            return true;
        }
    }
    return false;
}

QList<EpicInstallTagInfo> EpicManifest::computeInstallTags() const {
    QHash<QString, EpicInstallTagInfo> byTag;
    QHash<QString, QSet<QString>> chunksPerTag;

    for (const EpicFileManifest& fm : files) {
        if (fm.installTags.isEmpty()) continue;
        for (const QString& rawTag : fm.installTags) {
            const QString tag = rawTag.trimmed();
            if (tag.isEmpty()) continue;
            EpicInstallTagInfo& info = byTag[tag];
            info.tag = tag;
            info.installSize += fm.fileSize;
            info.fileCount += 1;
            for (const EpicChunkPart& part : fm.chunkParts) {
                chunksPerTag[tag].insert(part.chunkGuid);
            }
        }
    }

    QList<EpicInstallTagInfo> result;
    for (auto it = byTag.begin(); it != byTag.end(); ++it) {
        qint64 dlBytes = 0;
        for (const QString& guid : chunksPerTag.value(it.key())) {
            if (const EpicChunkInfo* ci = findChunk(guid)) {
                dlBytes += qMax<qint64>(0, ci->fileSize);
            }
        }
        it.value().downloadSize = dlBytes;
        result.append(it.value());
    }
    std::sort(result.begin(), result.end(), [](const EpicInstallTagInfo& a, const EpicInstallTagInfo& b) {
        return a.tag.compare(b.tag, Qt::CaseInsensitive) < 0;
    });
    return result;
}

EpicManifestDiff EpicManifestParser::diffManifests(const EpicManifest& oldManifest,
                                                   const EpicManifest& newManifest,
                                                   const QStringList& selectedTags) {
    EpicManifestDiff diff;
    QHash<QString, const EpicFileManifest*> oldByPath;
    oldByPath.reserve(oldManifest.files.size());
    for (const EpicFileManifest& of : oldManifest.files) {
        oldByPath.insert(of.filename.toLower(), &of);
    }

    QSet<QString> newPathsLower;
    for (const EpicFileManifest& nf : newManifest.files) {
        if (!EpicManifest::fileMatchesTags(nf, selectedTags)) {
            continue;
        }
        const QString lowerPath = nf.filename.toLower();
        newPathsLower.insert(lowerPath);

        const EpicFileManifest* oldFile = oldByPath.value(lowerPath, nullptr);
        const bool sameHash = oldFile &&
                              !nf.shaHash.isEmpty() &&
                              !oldFile->shaHash.isEmpty() &&
                              oldFile->shaHash == nf.shaHash &&
                              oldFile->fileSize == nf.fileSize &&
                              oldFile->symlinkTarget == nf.symlinkTarget;
        if (sameHash) {
            diff.unchangedFiles.append(nf);
        } else {
            diff.modifiedOrNewFiles.append(nf);
            diff.deltaInstallBytes += nf.fileSize;
            for (const EpicChunkPart& part : nf.chunkParts) {
                diff.requiredChunkGuids.insert(part.chunkGuid);
            }
        }
    }

    for (const EpicFileManifest& of : oldManifest.files) {
        if (!newPathsLower.contains(of.filename.toLower())) {
            diff.removedFiles.append(of.filename);
        }
    }

    for (const QString& guid : diff.requiredChunkGuids) {
        if (const EpicChunkInfo* ci = newManifest.findChunk(guid)) {
            diff.deltaDownloadBytes += qMax<qint64>(0, ci->fileSize);
        }
    }
    return diff;
}

bool EpicManifestParser::zlibDeflate(const QByteArray& raw,
                                     QByteArray& outCompressed,
                                     QString* outError) {
    outCompressed.clear();
    z_stream zs{};
    if (deflateInit(&zs, Z_DEFAULT_COMPRESSION) != Z_OK) {
        if (outError) *outError = QStringLiteral("zlib deflateInit failed");
        return false;
    }

    zs.next_in = reinterpret_cast<Bytef*>(const_cast<char*>(raw.constData()));
    zs.avail_in = static_cast<uInt>(raw.size());

    char buffer[65536];
    int ret = Z_OK;
    do {
        zs.next_out = reinterpret_cast<Bytef*>(buffer);
        zs.avail_out = sizeof(buffer);
        ret = deflate(&zs, Z_FINISH);
        const qsizetype have = static_cast<qsizetype>(sizeof(buffer) - zs.avail_out);
        if (have > 0) {
            outCompressed.append(buffer, have);
        }
        if (ret != Z_OK && ret != Z_STREAM_END) {
            deflateEnd(&zs);
            if (outError) *outError = QStringLiteral("zlib deflate error (%1)").arg(ret);
            return false;
        }
    } while (ret != Z_STREAM_END);

    deflateEnd(&zs);
    return true;
}

quint64 EpicManifestParser::computeRollingHash(const QByteArray& data) {
    // 64-bit FNV-1a deterministic hash suitable for chunk filenames
    quint64 h = 14695981039346656037ULL;
    for (uchar b : data) {
        h ^= static_cast<quint64>(b);
        h *= 1099511628211ULL;
    }
    return h;
}

QByteArray EpicManifestParser::buildChunk(const QString& guidHex32,
                                          const QByteArray& uncompressedData,
                                          quint64* outHash,
                                          QByteArray* outSha1) {
    QByteArray compressed;
    quint8 storedAs = 0x01u;
    if (!zlibDeflate(uncompressedData, compressed) || compressed.size() >= uncompressedData.size()) {
        compressed = uncompressedData;
        storedAs = 0x00u;
    }

    const QByteArray sha1 = QCryptographicHash::hash(uncompressedData, QCryptographicHash::Sha1);
    const quint64 rolling = computeRollingHash(uncompressedData);
    if (outHash) *outHash = rolling;
    if (outSha1) *outSha1 = sha1;

    // Header v2: magic(4) + version(4) + headerSize(4) + compSize(4) + guid(16) + hash(8) + storedAs(1) + sha1(20) = 61 bytes
    constexpr quint32 kHeaderSize = 61u;
    QByteArray out;
    out.reserve(static_cast<qsizetype>(kHeaderSize) + compressed.size());

    auto appendLE32 = [&out](quint32 v) {
        uchar b[4];
        qToLittleEndian(v, b);
        out.append(reinterpret_cast<const char*>(b), 4);
    };
    auto appendLE64 = [&out](quint64 v) {
        uchar b[8];
        qToLittleEndian(v, b);
        out.append(reinterpret_cast<const char*>(b), 8);
    };

    appendLE32(kChunkMagic);
    appendLE32(2u); // version 2 includes SHA-1
    appendLE32(kHeaderSize);
    appendLE32(static_cast<quint32>(compressed.size()));

    // Write 16-byte FGuid (4 little-endian uint32s)
    const QString padded = guidHex32.trimmed().toUpper().leftJustified(32, QLatin1Char('0'));
    for (int i = 0; i < 4; ++i) {
        bool ok = false;
        const quint32 part = padded.mid(i * 8, 8).toUInt(&ok, 16);
        appendLE32(part);
    }
    appendLE64(rolling);
    out.append(static_cast<char>(storedAs));
    out.append(sha1.leftJustified(20, '\0', true));
    out.append(compressed);
    return out;
}

QByteArray EpicManifestParser::buildJsonManifest(const QString& appName,
                                                 const QString& buildVersion,
                                                 const QList<EpicFileManifest>& files,
                                                 const QList<EpicChunkInfo>& chunks) {
    QJsonObject root;
    root[QStringLiteral("ManifestFileVersion")] = QStringLiteral("000000000000000000000018");
    root[QStringLiteral("bIsFileData")] = false;
    root[QStringLiteral("AppID")] = QStringLiteral("0");
    root[QStringLiteral("AppNameString")] = appName;
    root[QStringLiteral("BuildVersionString")] = buildVersion;
    root[QStringLiteral("LaunchExeString")] = QString();
    root[QStringLiteral("LaunchCommand")] = QString();

    QJsonObject hashObj;
    QJsonObject shaObj;
    QJsonObject groupObj;
    QJsonObject sizeObj;
    for (const EpicChunkInfo& c : chunks) {
        hashObj[c.guid] = QStringLiteral("%1").arg(c.hash, 16, 16, QLatin1Char('0')).toUpper();
        shaObj[c.guid] = QString::fromLatin1(c.shaHash.toHex()).toUpper();
        groupObj[c.guid] = QString::number(c.groupNum);
        sizeObj[c.guid] = QString::number(c.fileSize);
    }
    root[QStringLiteral("ChunkHashList")] = hashObj;
    root[QStringLiteral("ChunkShaList")] = shaObj;
    root[QStringLiteral("DataGroupList")] = groupObj;
    root[QStringLiteral("ChunkFilesizeList")] = sizeObj;

    QJsonArray filesArr;
    for (const EpicFileManifest& fm : files) {
        QJsonObject fo;
        fo[QStringLiteral("Filename")] = fm.filename;
        fo[QStringLiteral("FileHash")] = QString::fromLatin1(fm.shaHash.toHex()).toUpper();
        if (!fm.installTags.isEmpty()) {
            QJsonArray tagsArr;
            for (const QString& t : fm.installTags) tagsArr.append(t);
            fo[QStringLiteral("InstallTags")] = tagsArr;
        }
        QJsonArray partsArr;
        for (const EpicChunkPart& p : fm.chunkParts) {
            QJsonObject po;
            po[QStringLiteral("Guid")] = p.chunkGuid;
            po[QStringLiteral("Offset")] = static_cast<qint64>(p.offset);
            po[QStringLiteral("Size")] = static_cast<qint64>(p.size);
            partsArr.append(po);
        }
        fo[QStringLiteral("FileChunkParts")] = partsArr;
        filesArr.append(fo);
    }
    root[QStringLiteral("FileManifestList")] = filesArr;
    return QJsonDocument(root).toJson(QJsonDocument::Compact);
}

} // namespace Tsuki

