#include "SecretStore.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSet>

#ifdef TSUKI_HAS_LIBSECRET
#undef signals
#undef slots
#include <libsecret/secret.h>
#endif

namespace Tsuki {

namespace {

#ifdef TSUKI_HAS_LIBSECRET
const SecretSchema* tsukiSecretSchema() {
    static const SecretSchema schema = {
        "io.github.muzammilshafique.tsuki.Secret",
        SECRET_SCHEMA_NONE,
        {
            {"account", SECRET_SCHEMA_ATTRIBUTE_STRING},
            {"application", SECRET_SCHEMA_ATTRIBUTE_STRING},
            {nullptr, static_cast<SecretSchemaAttributeType>(0)}
        },
        0, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr
    };
    return &schema;
}
#endif

} // namespace

bool SecretStore::isFileFallbackForced() {
    const QByteArray forced = qgetenv("TSUKI_FORCE_FILE_SECRETS").trimmed().toLower();
    if (forced == "1" || forced == "true" || forced == "yes") {
        return true;
    }
    // Never poke a live user keyring during headless/offscreen automated tests unless explicitly requested
    const QByteArray qpa = qgetenv("QT_QPA_PLATFORM").trimmed().toLower();
    if (qpa == "offscreen" && qgetenv("TSUKI_ALLOW_KEYRING_IN_OFFSCREEN") != "1") {
        return true;
    }
    if (qEnvironmentVariableIsEmpty("DBUS_SESSION_BUS_ADDRESS")) {
        return true;
    }
    return false;
}

bool SecretStore::isKeyringAvailable() {
    if (isFileFallbackForced()) {
        return false;
    }
#ifdef TSUKI_HAS_LIBSECRET
    GError* err = nullptr;
    SecretService* svc = secret_service_get_sync(SECRET_SERVICE_NONE, nullptr, &err);
    if (err) {
        g_error_free(err);
        return false;
    }
    if (!svc) {
        return false;
    }
    g_object_unref(svc);
    return true;
#else
    return false;
#endif
}

bool SecretStore::writeFallbackFile(const QString& path, const QString& value) {
    if (path.isEmpty()) return false;
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        return false;
    }
    const QByteArray bytes = value.toUtf8();
    const qint64 written = f.write(bytes);
    f.close();
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    return written == bytes.size();
}

QString SecretStore::readFallbackFile(const QString& path) {
    if (path.isEmpty()) return QString();
    QFile f(path);
    if (!f.exists() || !f.open(QIODevice::ReadOnly)) {
        return QString();
    }
    const QByteArray data = f.readAll();
    f.close();
    return QString::fromUtf8(data);
}

bool SecretStore::saveSecret(const QString& accountKey,
                             const QString& secretValue,
                             const QString& fallbackFilePath,
                             Backend* usedBackend) {
    if (accountKey.trimmed().isEmpty()) {
        return false;
    }
#ifdef TSUKI_HAS_LIBSECRET
    if (!isFileFallbackForced()) {
        GError* err = nullptr;
        const QByteArray acctUtf8 = accountKey.toUtf8();
        const QByteArray valUtf8 = secretValue.toUtf8();
        const QByteArray labelUtf8 = QStringLiteral("Tsuki (%1)").arg(accountKey).toUtf8();
        const gboolean ok = secret_password_store_sync(
            tsukiSecretSchema(),
            SECRET_COLLECTION_DEFAULT,
            labelUtf8.constData(),
            valUtf8.constData(),
            nullptr,
            &err,
            "account", acctUtf8.constData(),
            "application", "tsuki",
            nullptr);
        if (err) {
            g_error_free(err);
        }
        if (ok) {
            if (!fallbackFilePath.isEmpty() && QFileInfo::exists(fallbackFilePath)) {
                QFile::remove(fallbackFilePath);
            }
            if (usedBackend) *usedBackend = Backend::Keyring;
            return true;
        }
    }
#endif
    const bool fileOk = writeFallbackFile(fallbackFilePath, secretValue);
    if (fileOk && usedBackend) {
        *usedBackend = Backend::FileFallback;
    }
    return fileOk;
}

QString SecretStore::loadSecret(const QString& accountKey,
                                const QString& fallbackFilePath,
                                Backend* usedBackend) {
    if (accountKey.trimmed().isEmpty()) {
        return QString();
    }
#ifdef TSUKI_HAS_LIBSECRET
    if (!isFileFallbackForced()) {
        GError* err = nullptr;
        const QByteArray acctUtf8 = accountKey.toUtf8();
        gchar* raw = secret_password_lookup_sync(
            tsukiSecretSchema(),
            nullptr,
            &err,
            "account", acctUtf8.constData(),
            "application", "tsuki",
            nullptr);
        if (err) {
            g_error_free(err);
        }
        if (raw) {
            const QString result = QString::fromUtf8(raw);
            secret_password_free(raw);
            if (!result.isEmpty()) {
                if (usedBackend) *usedBackend = Backend::Keyring;
                return result;
            }
        }
    }
#endif
    const QString fromFile = readFallbackFile(fallbackFilePath);
    if (!fromFile.isEmpty()) {
        // Transparent one-time migration into keyring if available
        if (isKeyringAvailable()) {
            Backend migratedBackend = Backend::FileFallback;
            if (saveSecret(accountKey, fromFile, fallbackFilePath, &migratedBackend)) {
                if (usedBackend) *usedBackend = migratedBackend;
                return fromFile;
            }
        }
        if (usedBackend) *usedBackend = Backend::FileFallback;
        return fromFile;
    }
    return QString();
}

bool SecretStore::deleteSecret(const QString& accountKey, const QString& fallbackFilePath) {
    bool ok = true;
#ifdef TSUKI_HAS_LIBSECRET
    if (!isFileFallbackForced() && !accountKey.trimmed().isEmpty()) {
        GError* err = nullptr;
        const QByteArray acctUtf8 = accountKey.toUtf8();
        secret_password_clear_sync(
            tsukiSecretSchema(),
            nullptr,
            &err,
            "account", acctUtf8.constData(),
            "application", "tsuki",
            nullptr);
        if (err) {
            g_error_free(err);
        }
    }
#endif
    if (!fallbackFilePath.isEmpty() && QFileInfo::exists(fallbackFilePath)) {
        ok = QFile::remove(fallbackFilePath);
    }
    return ok;
}

bool SecretStore::detectCpuX86_64V3() {
    QFile f(QStringLiteral("/proc/cpuinfo"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }
    while (!f.atEnd()) {
        const QByteArray line = f.readLine();
        if (line.startsWith("flags")) {
            const int colon = line.indexOf(':');
            if (colon < 0) continue;
            const QList<QByteArray> parts = line.mid(colon + 1).trimmed().split(' ');
            QSet<QByteArray> flags;
            for (const QByteArray& p : parts) {
                if (!p.isEmpty()) flags.insert(p);
            }
            const bool hasLzcnt = flags.contains("abm") || flags.contains("lzcnt");
            return flags.contains("avx") &&
                   flags.contains("avx2") &&
                   flags.contains("bmi1") &&
                   flags.contains("bmi2") &&
                   flags.contains("f16c") &&
                   flags.contains("fma") &&
                   flags.contains("movbe") &&
                   flags.contains("xsave") &&
                   hasLzcnt;
        }
    }
    return false;
}

} // namespace Tsuki

