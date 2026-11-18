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

} // namespace Tsuki

