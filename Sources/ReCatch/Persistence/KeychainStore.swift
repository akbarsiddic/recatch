import Foundation
import Security

/// Keychain-only API keys. Never in UserDefaults or logs.
enum KeychainStore {
    static func save(provider: String, key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.meetingradar.llm",
            kSecAttrAccount as String: provider]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = key.data(using: .utf8)!
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    /// Cheap existence check so a row can show "stored" without reading the secret.
    static func has(provider: String) -> Bool {
        guard let key = load(provider: provider) else { return false }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func load(provider: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.meetingradar.llm",
            kSecAttrAccount as String: provider,
            kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

/// Strip secrets before any logging. Transcripts never go to os_log by default.
enum Redactor {
    static func redact(_ s: String) -> String {
        var r = s
        for pat in ["sk-[A-Za-z0-9-_]+", "sk-ant-[A-Za-z0-9-_]+", "xox[bpas]-[A-Za-z0-9-]+", "ghp_[A-Za-z0-9]+", "Bearer\\s+\\S+", "zen_[A-Za-z0-9]+" ] {
            r = r.replacingOccurrences(of: pat, with: "[REDACTED]", options: .regularExpression)
        }
        return r
    }
}
