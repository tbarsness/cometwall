import Foundation
import LocalAuthentication
import Security

/// Saved login passwords, one generic-password item per host in the login keychain.
///
/// The keychain encrypts each item and ties it to this app's code signature, so
/// another app asking for it gets a macOS approval prompt. On top of that the app
/// asks for Touch ID (falling back to the Mac password) once per launch before it
/// reads any password.
@MainActor
final class Credentials {
    private static let service = "com.timbarsness.cometwall.login"

    private var unlocked = false
    /// Set when Touch ID is cancelled, so three tiles don't prompt three times.
    /// Cleared by Layout › Unlock Saved Logins.
    private(set) var declined = false
    private var unlocking: Task<Bool, Never>?

    func hasPassword(for host: String) -> Bool {
        var query = baseQuery(host)
        query[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func save(_ password: String, for host: String) throws {
        SecItemDelete(baseQuery(host) as CFDictionary)
        var item = baseQuery(host)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrLabel as String] = "CometWall login (\(host))"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"])
        }
    }

    func forget(host: String) {
        SecItemDelete(baseQuery(host) as CFDictionary)
    }

    /// The saved password for host, after Touch ID. Nil if none is saved or the
    /// user declined.
    func password(for host: String) async -> String? {
        guard hasPassword(for: host), await unlock() else { return nil }
        var query = baseQuery(host)
        query[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func resetDecline() { declined = false }

    private func unlock() async -> Bool {
        if unlocked { return true }
        if declined { return false }
        if let unlocking { return await unlocking.value }
        let task = Task { @MainActor () -> Bool in
            let context = LAContext()
            let ok = (try? await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "unlock your saved KVM logins")) ?? false
            unlocked = ok
            declined = !ok
            return ok
        }
        unlocking = task
        defer { unlocking = nil }
        return await task.value
    }

    private func baseQuery(_ host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: host,
        ]
    }
}
