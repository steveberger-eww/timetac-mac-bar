import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// The single observable store the UI reads from.
///
/// `@MainActor` throughout: every property here feeds SwiftUI, and the network work it kicks off
/// already hops to the client actor, so there's nothing to gain from isolating pieces separately.
@MainActor
@Observable
public final class AppState {
    public enum Phase: Equatable {
        /// No account name or client id yet — first run.
        case setup
        /// Configured, but there's no usable session.
        case signedOut
        case loading
        case ready
    }

    public private(set) var phase: Phase = .loading
    public private(set) var snapshot = PresenceSnapshot()
    public private(set) var user: TTUser?
    public private(set) var allTasks: [TTTask] = []
    public private(set) var favouriteTasks: [TTTask] = []
    public private(set) var recentTasks: [TTTask] = []
    public private(set) var breakTasks: [TTTask] = []
    public private(set) var lastUpdated: Date?
    public private(set) var isBusy = false
    public var lastError: String?

    /// Bumped once a second while a tracking runs; the elapsed label reads it so SwiftUI
    /// re-renders without anything else having to change.
    public private(set) var tick = Date()

    public private(set) var configuration: AppConfiguration

    /// Whether a client secret is in play at all — baked into the build or entered once. The
    /// setup screen never shows the secret itself, so it asks this instead.
    public var hasClientSecret: Bool {
        isMock || CompanyDefaults.hasClientSecret(keychain: keychain)
    }

    private let configurationStore: ConfigurationStore
    private let keychain: Keychain
    private var tokenStore: TokenStore?
    private var api: any TimeTacAPI
    private let isMock: Bool

    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var wakeObserver: (any NSObjectProtocol)?

    /// Remembered so "Back to work" after a break resumes what you were actually doing.
    private var lastWorkTaskID: Int? {
        get { UserDefaults.standard.object(forKey: Self.lastTaskKey) as? Int }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastTaskKey) }
    }

    private static let lastTaskKey = "at.koschier.TimeTacBar.lastWorkTaskID"

    public init(
        configurationStore: ConfigurationStore = ConfigurationStore(),
        keychain: Keychain = Keychain(),
        useMock: Bool = ProcessInfo.processInfo.environment["TIMETACBAR_MOCK"] == "1"
    ) {
        self.configurationStore = configurationStore
        self.keychain = keychain
        self.isMock = useMock

        let configuration = useMock
            ? AppConfiguration(account: "demo", clientID: "mock", username: "demo")
            : configurationStore.load().applyingCompanyDefaults()
        self.configuration = configuration

        if useMock {
            self.api = MockClient()
            self.tokenStore = nil
        } else {
            let store = TokenStore(configuration: configuration, keychain: keychain)
            self.tokenStore = store
            self.api = TimeTacClient(
                configuration: configuration,
                tokenStore: store,
                onConfigurationChange: { updated in
                    // Fires when the client settles on a path style; persist so the next launch
                    // doesn't have to probe again.
                    ConfigurationStore().save(updated)
                }
            )
        }
    }

    /// Injects a client directly. Used by tests and previews so the state machine can be driven
    /// without touching UserDefaults or the Keychain.
    init(api: any TimeTacAPI, configuration: AppConfiguration = AppConfiguration(account: "test", clientID: "test", username: "test")) {
        self.configurationStore = ConfigurationStore()
        self.keychain = Keychain()
        self.isMock = true
        self.configuration = configuration
        self.api = api
        self.tokenStore = nil
    }

    // MARK: - Lifecycle

    public func start() async {
        startTicking()
        observeWake()

        if isMock {
            phase = .ready
            await refresh()
            startPolling()
            return
        }

        guard let tokenStore, configuration.hasCompanySetup, await tokenStore.hasClientCredentials else {
            phase = .setup
            return
        }

        guard await tokenStore.hasStoredSession else {
            phase = .signedOut
            return
        }

        phase = .loading
        await refresh()
        startPolling()
    }

    /// Tears down the background loops. The app lives as long as the process, so this is only for
    /// tests and previews.
    public func stop() {
        pollTask?.cancel()
        tickTask?.cancel()
        #if canImport(AppKit)
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        #endif
    }

    private func startPolling() {
        pollTask?.cancel()
        let interval = max(15, configuration.pollInterval)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                self?.advanceTick()
            }
        }
    }

    private func advanceTick() {
        // Only invalidate views when there's a running duration on screen.
        guard snapshot.status.isTracking else { return }
        tick = Date()
    }

    private func observeWake() {
        #if canImport(AppKit)
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // After sleep the elapsed time is stale and a tracking may have been stopped
            // elsewhere, so re-sync rather than waiting for the next poll.
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        #endif
    }

    // MARK: - Reading

    public func refresh() async {
        guard phase != .setup, phase != .signedOut else { return }

        do {
            let user = try await api.currentUser()
            self.user = user

            // Independent reads, so let them overlap.
            async let overview = api.statusOverview(userID: user.id)
            async let tracking = api.currentTracking()
            async let today = api.trackingsToday(userID: user.id)
            async let absences = api.absenceDaysToday(userID: user.id)

            let resolvedOverview = try await overview
            let resolvedTracking = try await tracking
            let resolvedToday = try await today
            let resolvedAbsences = try await absences

            if allTasks.isEmpty { try await loadTasks(userID: user.id) }

            apply(
                overview: resolvedOverview,
                tracking: resolvedTracking,
                today: resolvedToday,
                absences: resolvedAbsences
            )

            lastUpdated = Date()
            lastError = nil
            phase = .ready
        } catch {
            handle(error)
        }
    }

    /// Refreshes only if the last sync is older than `maxAge`.
    public func refreshIfStale(maxAge: TimeInterval = 10) async {
        if let lastUpdated, Date().timeIntervalSince(lastUpdated) < maxAge { return }
        await refresh()
    }

    private func loadTasks(userID: Int) async throws {
        let tasks = try await api.tasks()
        allTasks = tasks

        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        breakTasks = tasks.filter(\.isBreak)

        let favouriteIDs = (try? await api.favouriteTaskIDs(userID: userID)) ?? []
        let recentIDs = (try? await api.recentTaskIDs(userID: userID)) ?? []

        favouriteTasks = favouriteIDs.compactMap { byID[$0] }.filter(\.isWorkable)
        // `recentTasks` comes back newest-first; drop anything already pinned as a favourite so
        // the picker doesn't list the same task twice.
        let favouriteSet = Set(favouriteTasks.map(\.id))
        recentTasks = recentIDs
            .compactMap { byID[$0] }
            .filter { $0.isWorkable && !favouriteSet.contains($0.id) }
    }

    private func apply(
        overview: UserStatusOverview?,
        tracking: TimeTracking?,
        today: [TimeTracking],
        absences: [AbsenceDay]
    ) {
        let status = PresenceSnapshot.status(overview: overview, tracking: tracking)
        let taskID = overview?.timeTrackingTaskID ?? tracking?.taskID
        let task = taskID.flatMap { id in allTasks.first { $0.id == id } }

        if status == .working, let taskID { lastWorkTaskID = taskID }

        snapshot = PresenceSnapshot(
            status: status,
            taskID: taskID,
            taskName: task?.name ?? taskID.map { "Task \($0)" },
            startedAt: overview?.startDate ?? tracking?.startDate,
            todayTotal: PresenceSnapshot.workedSeconds(in: today),
            leave: absences.filter(\.isGranted)
        )
    }

    // MARK: - Actions

    public func startWork(taskID: Int?) async {
        let resolved = taskID ?? lastWorkTaskID ?? favouriteTasks.first?.id ?? allTasks.first(where: \.isWorkable)?.id
        await act {
            guard let user = self.user else { throw TimeTacError.notAuthenticated }
            try await self.api.startTracking(userID: user.id, taskID: resolved)
            if let resolved { self.lastWorkTaskID = resolved }
        }
    }

    public func takeBreak(taskID: Int? = nil) async {
        let resolved = taskID ?? breakTasks.first?.id
        guard let resolved else {
            lastError = "No break task is set up in TimeTac, so there's nothing to switch to."
            return
        }
        await act {
            guard let user = self.user else { throw TimeTacError.notAuthenticated }
            try await self.api.startTracking(userID: user.id, taskID: resolved)
        }
    }

    public func clockOut() async {
        await act {
            guard let user = self.user else { throw TimeTacError.notAuthenticated }
            try await self.api.stopTracking(userID: user.id)
        }
    }

    /// Switching task is just starting a new tracking — the server closes the previous one.
    public func switchTask(to taskID: Int) async {
        await startWork(taskID: taskID)
    }

    private func act(_ body: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await body()
            lastError = nil
            await refresh()
        } catch {
            handle(error)
        }
    }

    // MARK: - Session

    /// The company-level half of the setup: which account, on which server, as which OAuth
    /// client. Done once — by whoever builds the app, or in the setup screen — and then left
    /// alone, so signing in is only ever a username and a password.
    public func saveCompanySetup(
        account: String,
        host: TimeTacHost,
        clientID: String,
        clientSecret: String
    ) async {
        var updated = configuration
        updated.account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.host = host
        updated.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if secret.isEmpty {
            // Left blank: whoever is only here to fix the account name keeps the secret they have.
        } else if secret == CompanyDefaults.current.clientSecret {
            // Same as the build's own, so nothing to override — and leaving the baked-in one out
            // of the Keychain means rotating it is a rebuild and nothing else.
            keychain.remove(.clientSecret)
        } else if !keychain.set(secret, for: .clientSecret) {
            lastError = "macOS wouldn't let the client secret be saved to the Keychain."
            return
        }

        // Pointing at a different account invalidates any session held for the old one.
        if updated.account != configuration.account || updated.clientID != configuration.clientID {
            await tokenStore?.signOut()
            keychain.removeSession()
            updated.username = ""
            user = nil
        }

        configuration = updated
        configurationStore.save(updated)

        let store = TokenStore(configuration: updated, keychain: keychain)
        tokenStore = store
        api = TimeTacClient(
            configuration: updated,
            tokenStore: store,
            onConfigurationChange: { ConfigurationStore().save($0) }
        )
        lastError = nil
        phase = updated.hasCompanySetup ? .signedOut : .setup
    }

    public func signIn(username: String, password: String, remember: Bool) async {
        isBusy = true
        defer { isBusy = false }

        var updated = configuration
        updated.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.stickySignIn = remember

        let store = TokenStore(configuration: updated, keychain: keychain)
        let request = TokenStore.SignInRequest(username: updated.username, password: password)

        do {
            try await store.signIn(request, remember: remember)
        } catch {
            handle(error)
            return
        }

        configuration = updated
        configurationStore.save(updated)
        tokenStore = store
        api = TimeTacClient(
            configuration: updated,
            tokenStore: store,
            onConfigurationChange: { ConfigurationStore().save($0) }
        )

        allTasks = []
        user = nil
        phase = .loading
        lastError = nil
        await refresh()
        startPolling()
    }

    public func signOut() async {
        pollTask?.cancel()
        await tokenStore?.signOut()
        keychain.removeSession()
        user = nil
        allTasks = []
        favouriteTasks = []
        recentTasks = []
        breakTasks = []
        snapshot = PresenceSnapshot()
        lastError = nil
        phase = configuration.hasCompanySetup ? .signedOut : .setup
    }

    /// Which server the account lives on is part of the company setup, so the only thing left to
    /// change here is how often we poll.
    public func updateSettings(pollInterval: TimeInterval) async {
        var updated = configuration
        updated.pollInterval = pollInterval
        configuration = updated
        configurationStore.save(updated)

        if let client = api as? TimeTacClient {
            await client.update(configuration: updated)
        }
        await tokenStore?.update(configuration: updated)
        startPolling()
    }

    /// Forces a task-list reload on the next refresh — used after the user adds a favourite in
    /// TimeTac and wants it to show up here.
    public func reloadTasks() async {
        allTasks = []
        await refresh()
    }

    private func handle(_ error: any Error) {
        if let ttError = error as? TimeTacError {
            lastError = ttError.errorDescription
            switch ttError {
            case .notAuthenticated, .unauthorized, .keychainDenied:
                phase = configuration.hasCompanySetup ? .signedOut : .setup
            case .notConfigured:
                phase = .setup
            default:
                if phase == .loading { phase = .ready }
            }
        } else {
            lastError = error.localizedDescription
            if phase == .loading { phase = .ready }
        }
    }
}
