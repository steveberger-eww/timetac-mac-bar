import Foundation
import Security

/// Thin wrapper over generic-password Keychain items.
///
/// Everything secret goes here: the refresh token, the OAuth client secret, and — when "Stay signed
/// in" is on — the password, which is the fallback when a refresh token has aged out.
public struct Keychain: Sendable {
    public enum Key: String, Sendable, CaseIterable {
        case refreshToken = "refresh_token"
        case clientSecret = "client_secret"
        case password = "password"
    }

    private let service: String

    public init(service: String = "at.koschier.TimeTacBar") {
        self.service = service
    }

    private func query(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    /// Why a read came back without a value. "Nothing stored" and "stored but macOS won't hand it
    /// over" need very different things from the user, and they're indistinguishable in a `String?`.
    public enum Lookup: Sendable, Equatable {
        case found(String)
        case missing
        /// The item is there, but this build isn't the one that wrote it. An ad-hoc signature
        /// changes on every rebuild, and the item's ACL is bound to the signature that created it.
        case denied(OSStatus)
    }

    public func get(_ key: Key) -> String? {
        if case .found(let value) = lookup(key) { return value }
        return nil
    }

    public func lookup(_ key: Key) -> Lookup {
        var query = query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty
            else { return .missing }
            return .found(value)
        case errSecItemNotFound:
            return .missing
        default:
            return .denied(status)
        }
    }

    /// Passing `nil` deletes the item.
    @discardableResult
    public func set(_ value: String?, for key: Key) -> Bool {
        guard let value, !value.isEmpty else { return remove(key) }
        guard let data = value.data(using: .utf8) else { return false }

        let query = query(for: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Survives reboots without needing an unlocked login keychain at launch, which matters
            // for an app that restores its session at login.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound {
            // Something is there that this build can't touch — almost always an item written by an
            // earlier ad-hoc signed build. Deleting needs no ACL approval, so drop it and write a
            // fresh one bound to the identity running now. This is what makes re-entering the
            // client secret actually fix a locked-out install.
            SecItemDelete(query as CFDictionary)
        }
        var insert = query
        insert.merge(attributes) { current, _ in current }
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    public func remove(_ key: Key) -> Bool {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public func removeAll() {
        for key in Key.allCases { remove(key) }
    }

    /// Drops only what belongs to the person signed in. The client secret is company-level setup,
    /// so signing out must leave it behind — otherwise every sign-out would demand it again.
    public func removeSession() {
        remove(.refreshToken)
        remove(.password)
    }
}
