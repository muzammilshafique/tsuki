#pragma once

#include <QString>

namespace Tsuki {

class SecretStore {
public:
    enum class Backend {
        Keyring,
        FileFallback
    };

    /// Returns true if Freedesktop Secret Service (libsecret / KWallet / GNOME Keyring)
    /// is compiled in, enabled, and reachable.
    static bool isKeyringAvailable();

    /// Save secret under `accountKey`. Uses Secret Service when available, otherwise writes
    /// to `fallbackFilePath` with strict 0600 permissions. Removes any stale plaintext fallback
    /// file when keyring storage succeeds.
    static bool saveSecret(const QString& accountKey,
                           const QString& secretValue,
                           const QString& fallbackFilePath,
                           Backend* usedBackend = nullptr);

    /// Load secret from Secret Service first, falling back to `fallbackFilePath`.
    /// If loaded from `fallbackFilePath` while keyring is available, transparently migrates
    /// into keyring and removes the plaintext file.
    static QString loadSecret(const QString& accountKey,
                              const QString& fallbackFilePath,
                              Backend* usedBackend = nullptr);

    /// Delete secret from both Secret Service (if available) and `fallbackFilePath`.
    static bool deleteSecret(const QString& accountKey, const QString& fallbackFilePath);

    /// Detect CPU x86-64-v3 support (used by AppSettings / RunnerManager without circular deps).
    static bool detectCpuX86_64V3();

private:
    static bool isFileFallbackForced();
    static bool writeFallbackFile(const QString& path, const QString& value);
    static QString readFallbackFile(const QString& path);
};

} // namespace Tsuki

