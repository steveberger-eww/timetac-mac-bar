import Foundation

/// Live TimeTac client.
///
/// An `actor` because it caches two pieces of resolved state — the user id and the working path
/// style — that concurrent callers would otherwise re-derive.
public actor TimeTacClient: TimeTacAPI {
    private var configuration: AppConfiguration
    private let tokenStore: TokenStore
    private let session: URLSession
    private let onConfigurationChange: @Sendable (AppConfiguration) -> Void

    private var cachedUser: TTUser?
    /// The alternate path style is tried at most once per launch, so a genuine 404 doesn't double
    /// every subsequent request.
    private var pathStyleProbed = false

    public init(
        configuration: AppConfiguration,
        tokenStore: TokenStore,
        session: URLSession = .shared,
        onConfigurationChange: @escaping @Sendable (AppConfiguration) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.session = session
        self.onConfigurationChange = onConfigurationChange
    }

    public func update(configuration: AppConfiguration) async {
        let accountChanged = configuration.account != self.configuration.account
            || configuration.host != self.configuration.host
        self.configuration = configuration
        await tokenStore.update(configuration: configuration)
        if accountChanged {
            cachedUser = nil
            pathStyleProbed = false
        }
    }

    // MARK: - TimeTacAPI

    public func currentUser() async throws -> TTUser {
        if let cachedUser { return cachedUser }

        // `users/me` isn't in the published v4 spec, but TimeTac's own client calls it, so try it
        // first and fall back to matching on username.
        if let user: TTUser = try? await first(TimeTacEndpoints.currentUser()) {
            cachedUser = user
            return user
        }

        guard !configuration.username.isEmpty else { throw TimeTacError.notConfigured }
        let candidates: [TTUser] = try await send(TimeTacEndpoints.users(username: configuration.username))
        guard let user = candidates.first(where: {
            $0.username?.caseInsensitiveCompare(configuration.username) == .orderedSame
        }) ?? candidates.first else {
            throw TimeTacError.api(code: nil, message: "Couldn't work out which TimeTac user you are.")
        }
        cachedUser = user
        return user
    }

    public func statusOverview(userID: Int) async throws -> UserStatusOverview? {
        let rows: [UserStatusOverview] = try await send(TimeTacEndpoints.statusOverview(userID: userID))
        // A manager's read can return the whole team, so never just take the first row.
        return rows.first { $0.userID == userID } ?? rows.first
    }

    public func currentTracking() async throws -> TimeTracking? {
        try await first(TimeTacEndpoints.currentTracking())
    }

    public func tasks() async throws -> [TTTask] {
        try await send(TimeTacEndpoints.tasks())
    }

    public func favouriteTaskIDs(userID: Int) async throws -> [Int] {
        let refs: [TaskReference] = try await send(TimeTacEndpoints.favouriteTasks(userID: userID))
        return refs.map(\.nodeID)
    }

    public func recentTaskIDs(userID: Int) async throws -> [Int] {
        let refs: [TaskReference] = try await send(TimeTacEndpoints.recentTasks(userID: userID))
        return refs.map(\.nodeID)
    }

    public func trackingsToday(userID: Int) async throws -> [TimeTracking] {
        let dayStart = TimeTacTime.day(Date()) + " 00:00:00"
        return try await send(TimeTacEndpoints.trackingsSince(userID: userID, dayStart: dayStart))
    }

    public func absenceDaysToday(userID: Int) async throws -> [AbsenceDay] {
        try await send(TimeTacEndpoints.absenceDays(userID: userID, date: TimeTacTime.day(Date())))
    }

    @discardableResult
    public func startTracking(userID: Int, taskID: Int?) async throws -> TimeTracking? {
        try await first(TimeTacEndpoints.startTracking(
            userID: userID,
            taskID: taskID,
            timeZone: TimeZone.current.identifier
        ))
    }

    public func stopTracking(userID: Int) async throws {
        let _: [TimeTracking] = try await send(TimeTacEndpoints.stopTracking(
            userID: userID,
            timeZone: TimeZone.current.identifier
        ))
    }

    // MARK: - Transport

    static func looksLikeHTML(_ data: Data) -> Bool {
        guard let first = data.first(where: { !$0.isWhitespaceByte }) else { return false }
        return first == UInt8(ascii: "<")
    }

    private func first<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T? {
        let results: [T] = try await send(endpoint)
        return results.first
    }

    private func send<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> [T] {
        do {
            return try await perform(endpoint, allowingAuthRetry: true)
        } catch TimeTacError.notFound where !pathStyleProbed {
            // A wrong path style is indistinguishable from a missing endpoint, so try the other
            // one once and keep it if it works.
            pathStyleProbed = true
            let alternate: APIPathStyle = configuration.pathStyle == .v4 ? .userapiV4 : .v4
            let previous = configuration.pathStyle
            configuration.pathStyle = alternate
            do {
                let results: [T] = try await perform(endpoint, allowingAuthRetry: true)
                onConfigurationChange(configuration)
                return results
            } catch {
                configuration.pathStyle = previous
                throw error
            }
        }
    }

    private func perform<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        allowingAuthRetry: Bool
    ) async throws -> [T] {
        guard let baseURL = configuration.baseURL else { throw TimeTacError.notConfigured }
        guard let url = endpoint.url(baseURL: baseURL, pathStyle: configuration.pathStyle) else {
            throw TimeTacError.notConfigured
        }

        let token = try await tokenStore.token()

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload = body.mapValues(\.encodable)
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TimeTacError.transport(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 {
            guard allowingAuthRetry else {
                throw TimeTacError.unauthorized(nil)
            }
            _ = try await tokenStore.refreshedToken(replacing: token)
            return try await perform(endpoint, allowingAuthRetry: false)
        }

        if status == 404 { throw TimeTacError.notFound }

        guard (200..<300).contains(status) else {
            throw TimeTacError.http(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        let envelope: APIEnvelope<T>
        do {
            envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        } catch {
            // A wrong path style answers with an HTML error page rather than the envelope, and
            // that case should drive the path probe. Anything else is a genuine shape mismatch and
            // must be reported as such, not disguised as a missing endpoint.
            if Self.looksLikeHTML(data) { throw TimeTacError.notFound }
            throw TimeTacError.decoding("Unexpected response from \(endpoint.resource)/\(endpoint.action).")
        }

        guard envelope.success else {
            // A rejected token can arrive as a 200 carrying Error 401, so route it back through
            // the same refresh-and-retry path.
            if envelope.error == 401, allowingAuthRetry {
                _ = try await tokenStore.refreshedToken(replacing: token)
                return try await perform(endpoint, allowingAuthRetry: false)
            }
            throw TimeTacError.api(
                code: envelope.error,
                message: envelope.errorMessage ?? "The request was rejected."
            )
        }

        return envelope.results
    }
}
