import Foundation

/// Owns the OAuth session.
///
/// An `actor` because token refresh must not race: several requests can hit a 401 at the same
/// moment, and without serialising them each would spend the refresh token separately, invalidating
/// the others. `refreshTask` makes concurrent callers await a single in-flight refresh.
public actor TokenStore {
    /// Only the per-person half. The client id/secret come from the company setup, which is
    /// already in the configuration and the Keychain by the time anyone signs in.
    public struct SignInRequest: Sendable {
        public var username: String
        public var password: String

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }
    }

    private var configuration: AppConfiguration
    private let keychain: Keychain
    private let session: URLSession

    private var accessToken: String?
    private var expiresAt: Date?
    private var refreshTask: Task<String, Error>?

    /// Refresh this far ahead of the stated expiry so a request never travels with a token that
    /// dies in flight.
    private let expiryMargin: TimeInterval = 60

    public init(
        configuration: AppConfiguration,
        keychain: Keychain = Keychain(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.keychain = keychain
        self.session = session
    }

    public func update(configuration: AppConfiguration) {
        self.configuration = configuration
    }

    /// True if a session could plausibly be restored without prompting for a password.
    public var hasStoredSession: Bool {
        keychain.get(.refreshToken) != nil || keychain.get(.password) != nil
    }

    /// True once the app knows which OAuth client it is — baked in at build time, or entered in
    /// the setup screen.
    public var hasClientCredentials: Bool {
        !configuration.clientID.isEmpty && CompanyDefaults.hasClientSecret(keychain: keychain)
    }

    public var currentAccessToken: String? { accessToken }

    public var expiry: Date? { expiresAt }

    // MARK: - Sign in / out

    /// Exchanges username + password for a token pair and persists the secrets.
    /// - Parameter remember: when false, the password is not written to the Keychain, so the
    ///   session lasts only as long as the refresh token does.
    public func signIn(_ request: SignInRequest, remember: Bool) async throws {
        guard !configuration.clientID.isEmpty else { throw TimeTacError.notConfigured }
        let clientSecret = try CompanyDefaults.clientSecret(keychain: keychain)

        var config = configuration
        config.username = request.username
        configuration = config

        let tokens = try await requestToken(parameters: [
            "grant_type": "password",
            "client_id": configuration.clientID,
            "client_secret": clientSecret,
            "username": request.username,
            "password": request.password,
        ])

        keychain.set(remember ? request.password : nil, for: .password)
        apply(tokens)
    }

    public func signOut() {
        accessToken = nil
        expiresAt = nil
        refreshTask?.cancel()
        refreshTask = nil
        keychain.removeSession()
    }

    // MARK: - Token vending

    /// A usable access token, minting or refreshing one if needed.
    public func token() async throws -> String {
        if let accessToken, let expiresAt, expiresAt.timeIntervalSinceNow > expiryMargin {
            return accessToken
        }
        return try await performRefresh()
    }

    /// Called after a 401. If another task already replaced `stale`, hand back the newer token
    /// rather than burning a second refresh.
    public func refreshedToken(replacing stale: String) async throws -> String {
        if let accessToken, accessToken != stale { return accessToken }
        accessToken = nil
        return try await performRefresh()
    }

    private func performRefresh() async throws -> String {
        if let refreshTask { return try await refreshTask.value }

        let task = Task<String, Error> { [configuration, keychain] in
            let tokens = try await self.obtainTokens(configuration: configuration, keychain: keychain)
            return self.finish(with: tokens)
        }
        refreshTask = task

        defer { refreshTask = nil }
        return try await task.value
    }

    private func finish(with tokens: TokenResponse) -> String {
        apply(tokens)
        return tokens.accessToken
    }

    private func apply(_ tokens: TokenResponse) {
        accessToken = tokens.accessToken
        // TimeTac states TTL in seconds; assume a conservative hour when it's absent.
        expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600))
        if let refreshToken = tokens.refreshToken {
            keychain.set(refreshToken, for: .refreshToken)
        }
    }

    /// Refresh token first; fall back to a stored password when the refresh token has expired or
    /// been revoked. That fallback is what keeps the user from signing in again every few days.
    private func obtainTokens(configuration: AppConfiguration, keychain: Keychain) async throws -> TokenResponse {
        guard !configuration.clientID.isEmpty else { throw TimeTacError.notConfigured }
        let clientSecret = try CompanyDefaults.clientSecret(keychain: keychain)

        if let refreshToken = keychain.get(.refreshToken) {
            do {
                return try await requestToken(parameters: [
                    "grant_type": "refresh_token",
                    "client_id": configuration.clientID,
                    "client_secret": clientSecret,
                    "refresh_token": refreshToken,
                ])
            } catch {
                keychain.remove(.refreshToken)
                guard keychain.get(.password) != nil else { throw error }
            }
        }

        guard let password = keychain.get(.password), !configuration.username.isEmpty else {
            throw TimeTacError.notAuthenticated
        }

        return try await requestToken(parameters: [
            "grant_type": "password",
            "client_id": configuration.clientID,
            "client_secret": clientSecret,
            "username": configuration.username,
            "password": password,
        ])
    }

    // MARK: - Transport

    /// `POST {base}/auth/oauth2/token`, form-encoded. Note this sits outside the versioned path.
    private func requestToken(parameters: [String: String]) async throws -> TokenResponse {
        guard let baseURL = configuration.baseURL else { throw TimeTacError.notConfigured }
        let url = baseURL.appendingPathComponent("auth/oauth2/token")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formEncode(parameters).data(using: .utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TimeTacError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TimeTacError.authFailed(Self.authErrorMessage(data: data, status: status))
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw TimeTacError.decoding("The sign-in response wasn't in the expected format.")
        }
    }

    private static func authErrorMessage(data: Data, status: Int) -> String {
        if let body = try? JSONDecoder().decode(OAuthErrorBody.self, from: data) {
            if let description = body.errorDescription, !description.isEmpty { return description }
            if let error = body.error, !error.isEmpty {
                switch error {
                case "invalid_grant": return "That username or password wasn't accepted."
                // TimeTac's API credentials carry an expiry date set when they're created, so a
                // pair that worked yesterday can stop working without anyone changing anything.
                case "invalid_client":
                    return "That client ID or client secret wasn't accepted — check under Company setup whether it has expired."
                case "Account not found": return "No TimeTac account by that name. Check the account name in Settings."
                default: return error
                }
            }
        }
        if status == 404 {
            return "No TimeTac account by that name. Check the account name in Settings."
        }
        return "Sign-in failed (HTTP \(status))."
    }

    static func formEncode(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }
}
