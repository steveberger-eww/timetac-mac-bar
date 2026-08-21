import Foundation

/// The company-level half of the setup, optionally baked into the app at build time.
///
/// The account name and the OAuth client id/secret are the same for everyone in a company —
/// TimeTac issues one pair per account, not per person, and their own web app ships its pair
/// inside the JavaScript bundle. Baking ours in means a colleague can be handed the built `.app`
/// and only ever sees a username and password, exactly like the web login.
///
/// Values come from the app bundle's `Info.plist` (written by `make bundle` from `company.env`),
/// falling back to the environment so `swift run`, `make probe` and tests can supply the same
/// values without a bundle.
public enum CompanyDefaults {
    public struct Values: Sendable, Equatable {
        public var account: String?
        public var host: TimeTacHost?
        public var clientID: String?
        public var clientSecret: String?

        public init(
            account: String? = nil,
            host: TimeTacHost? = nil,
            clientID: String? = nil,
            clientSecret: String? = nil
        ) {
            self.account = account
            self.host = host
            self.clientID = clientID
            self.clientSecret = clientSecret
        }

        /// True once a build carries enough to skip the setup screen entirely.
        public var isComplete: Bool {
            account?.isEmpty == false && clientID?.isEmpty == false && clientSecret?.isEmpty == false
        }
    }

    /// Info.plist key paired with the environment variable that overrides it.
    private static let keys = (
        account: ("TTBAccount", "TIMETAC_ACCOUNT"),
        host: ("TTBHost", "TIMETAC_HOST"),
        clientID: ("TTBClientID", "TIMETAC_CLIENT_ID"),
        clientSecret: ("TTBClientSecret", "TIMETAC_CLIENT_SECRET")
    )

    public static var current: Values {
        Values(
            account: value(keys.account),
            host: value(keys.host).flatMap(TimeTacHost.init(rawValue:)),
            clientID: value(keys.clientID),
            clientSecret: value(keys.clientSecret)
        )
    }

    /// The secret in play: a value typed into the setup screen wins, otherwise whatever the build
    /// carries. Keeping the baked-in one out of the Keychain means a rebuild after TimeTac's
    /// credentials expire takes effect without anyone having to clear anything.
    ///
    /// Throws rather than returning nil so "you haven't set this up" and "macOS won't give it back"
    /// reach the user as the different problems they are.
    public static func clientSecret(keychain: Keychain, defaults: Values = current) throws -> String {
        let baked = defaults.clientSecret.flatMap { $0.isEmpty ? nil : $0 }

        switch keychain.lookup(.clientSecret) {
        case .found(let secret):
            return secret
        case .missing:
            guard let baked else { throw TimeTacError.notConfigured }
            return baked
        case .denied(let status):
            // A baked-in secret needs no Keychain at all, so this only matters without one.
            guard let baked else { throw TimeTacError.keychainDenied(status) }
            return baked
        }
    }

    /// Whether a secret exists at all, denied or not — enough to know a company setup has happened.
    public static func hasClientSecret(keychain: Keychain, defaults: Values = current) -> Bool {
        if defaults.clientSecret?.isEmpty == false { return true }
        return keychain.lookup(.clientSecret) != .missing
    }

    private static func value(_ key: (info: String, environment: String)) -> String? {
        if let fromEnvironment = ProcessInfo.processInfo.environment[key.environment],
           !fromEnvironment.isEmpty {
            return fromEnvironment
        }
        guard let fromBundle = Bundle.main.object(forInfoDictionaryKey: key.info) as? String,
              !fromBundle.isEmpty
        else { return nil }
        return fromBundle
    }
}
