import Foundation

/// Which TimeTac deployment to talk to.
public enum TimeTacHost: String, CaseIterable, Sendable, Codable {
    case production = "api.timetac.com"
    case sandbox = "api-sandbox.timetac.com"

    public var displayName: String {
        switch self {
        case .production: "Production"
        case .sandbox: "Sandbox"
        }
    }

    /// Where the web app for the same deployment lives. The API and the browser are on different
    /// hostnames, and it's the browser one people recognise.
    public var webHost: String {
        switch self {
        case .production: "go.timetac.com"
        case .sandbox: "go-sandbox.timetac.com"
        }
    }
}

/// The v4 spec documents `{account}/V4/...`, while TimeTac's own JS client builds
/// `{account}/userapi/v4/...`. Both appear to be live; the account lookup happens before path
/// routing server-side, so which one an account accepts can only be settled at runtime.
/// `TimeTacClient` probes and persists whichever works.
public enum APIPathStyle: String, Sendable, Codable, CaseIterable {
    case v4 = "V4"
    case userapiV4 = "userapi/v4"
}

/// Non-secret settings. Anything sensitive lives in the Keychain instead — see `Keychain`.
public struct AppConfiguration: Sendable, Codable, Equatable {
    public var account: String
    public var host: TimeTacHost
    public var clientID: String
    public var username: String
    public var pathStyle: APIPathStyle
    public var pollInterval: TimeInterval
    public var stickySignIn: Bool

    public init(
        account: String = "",
        host: TimeTacHost = .production,
        clientID: String = "",
        username: String = "",
        pathStyle: APIPathStyle = .v4,
        pollInterval: TimeInterval = 60,
        stickySignIn: Bool = true
    ) {
        self.account = account
        self.host = host
        self.clientID = clientID
        self.username = username
        self.pathStyle = pathStyle
        self.pollInterval = pollInterval
        self.stickySignIn = stickySignIn
    }

    /// `https://api.timetac.com/{account}` — the root every request hangs off.
    public var baseURL: URL? {
        guard !account.isEmpty else { return nil }
        return URL(string: "https://\(host.rawValue)/\(account)")
    }

    /// The company-level half: which account, on which server, as which app. Identical for
    /// everyone in a company, so it's set up once rather than at every sign-in.
    public var hasCompanySetup: Bool {
        !account.isEmpty && !clientID.isEmpty
    }

    /// True once there is enough here to attempt a sign-in.
    public var isComplete: Bool {
        hasCompanySetup && !username.isEmpty
    }

    /// Fills in whatever the build was baked with, without ever overwriting a choice already
    /// stored — a user who pointed the app somewhere else keeps pointing there.
    public func applyingCompanyDefaults(_ defaults: CompanyDefaults.Values = CompanyDefaults.current) -> AppConfiguration {
        var copy = self
        if copy.account.isEmpty, let account = defaults.account, !account.isEmpty {
            copy.account = account
            // Only meaningful alongside the account it belongs to.
            if let host = defaults.host { copy.host = host }
        }
        if copy.clientID.isEmpty, let clientID = defaults.clientID, !clientID.isEmpty {
            copy.clientID = clientID
        }
        return copy
    }
}

/// Persists `AppConfiguration` in UserDefaults.
/// `UserDefaults` is documented as thread-safe; the compiler just has no way to know that.
public struct ConfigurationStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "at.koschier.TimeTacBar.configuration"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppConfiguration {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else { return AppConfiguration() }
        return config
    }

    public func save(_ config: AppConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}
