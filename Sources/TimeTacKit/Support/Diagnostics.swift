import Foundation

/// Read-only connectivity check, run with `TimeTacBar --probe`.
///
/// It signs in, resolves the user, and reports what it found. It deliberately performs **no
/// writes**, so it can be pointed at a live account without any risk of touching a timesheet.
/// Credentials come from the saved configuration and Keychain, or from environment variables:
/// `TIMETAC_ACCOUNT`, `TIMETAC_HOST`, `TIMETAC_CLIENT_ID`, `TIMETAC_CLIENT_SECRET`,
/// `TIMETAC_USERNAME`, `TIMETAC_PASSWORD`.
public enum Diagnostics {
    public static func probe() async -> Int32 {
        let environment = ProcessInfo.processInfo.environment
        let keychain = Keychain()
        var configuration = ConfigurationStore().load()

        if let account = environment["TIMETAC_ACCOUNT"] { configuration.account = account }
        if let host = environment["TIMETAC_HOST"].flatMap(TimeTacHost.init(rawValue:)) {
            configuration.host = host
        }
        if let clientID = environment["TIMETAC_CLIENT_ID"] { configuration.clientID = clientID }
        if let username = environment["TIMETAC_USERNAME"] { configuration.username = username }

        // Whatever the environment didn't supply, fall back to what the build was baked with.
        configuration = configuration.applyingCompanyDefaults()

        guard configuration.hasCompanySetup else {
            print("✗ No company setup. Set TIMETAC_ACCOUNT and TIMETAC_CLIENT_ID, bake them in via")
            print("  company.env, or fill them in under Company setup in the app.")
            return 2
        }

        print("Account   \(configuration.account)")
        print("Host      \(configuration.host.rawValue)")
        print("User      \(configuration.username.isEmpty ? "—" : configuration.username)")
        print("Base URL  \(configuration.baseURL?.absoluteString ?? "—")")
        print("")

        // Read after the summary: an ad-hoc signed build can stall here on a Keychain prompt, and
        // seeing what it resolved first makes that obvious rather than looking like a hang.
        do {
            _ = try CompanyDefaults.clientSecret(keychain: keychain)
            print("✓ Client secret available (\(configuration.clientID)).")
        } catch {
            print("✗ \((error as? TimeTacError)?.errorDescription ?? error.localizedDescription)")
            return 2
        }

        let password = environment["TIMETAC_PASSWORD"] ?? keychain.get(.password)

        guard !configuration.username.isEmpty else {
            print("✗ Nobody signed in. Set TIMETAC_USERNAME and TIMETAC_PASSWORD, or sign in first.")
            return 2
        }

        let store = TokenStore(configuration: configuration, keychain: keychain)

        do {
            if let password {
                try await store.signIn(
                    .init(username: configuration.username, password: password),
                    remember: false
                )
            } else {
                _ = try await store.token()
            }
        } catch {
            print("✗ Sign-in failed: \((error as? TimeTacError)?.errorDescription ?? error.localizedDescription)")
            return 1
        }

        if let expiry = await store.expiry {
            print("✓ Signed in. Access token expires \(DurationFormat.clock(expiry)).")
        } else {
            print("✓ Signed in.")
        }

        nonisolated(unsafe) var resolvedPathStyle = configuration.pathStyle
        let client = TimeTacClient(
            configuration: configuration,
            tokenStore: store,
            onConfigurationChange: { resolvedPathStyle = $0.pathStyle }
        )

        let user: TTUser
        do {
            user = try await client.currentUser()
            print("✓ Resolved user: \(user.displayName) (id \(user.id))")
            print("✓ Path style that worked: \(resolvedPathStyle.rawValue)")
        } catch {
            print("✗ Couldn't resolve the current user: \((error as? TimeTacError)?.errorDescription ?? error.localizedDescription)")
            return 1
        }

        do {
            let overview = try await client.statusOverview(userID: user.id)
            let tracking = try await client.currentTracking()
            let status = PresenceSnapshot.status(overview: overview, tracking: tracking)
            print("✓ Status: \(status.label)")

            if let started = overview?.startDate ?? tracking?.startDate {
                let elapsed = Date().timeIntervalSince(started)
                print("  Running since \(DurationFormat.clock(started)) (\(DurationFormat.long(elapsed)))")
            }
            if let taskID = overview?.timeTrackingTaskID ?? tracking?.taskID {
                print("  Task id: \(taskID)")
            }
        } catch {
            print("✗ Status read failed: \((error as? TimeTacError)?.errorDescription ?? error.localizedDescription)")
            return 1
        }

        do {
            let tasks = try await client.tasks()
            let workable = tasks.filter(\.isWorkable)
            let breaks = tasks.filter(\.isBreak)
            print("✓ Tasks: \(tasks.count) total, \(workable.count) startable, \(breaks.count) break")
            if breaks.isEmpty {
                print("  ⚠︎ No non-working task found — 'Take a break' will have nothing to start.")
            } else {
                print("  Break tasks: \(breaks.map(\.name).joined(separator: ", "))")
            }
        } catch {
            print("✗ Task read failed: \((error as? TimeTacError)?.errorDescription ?? error.localizedDescription)")
            return 1
        }

        print("")
        print("All checks passed. No data was modified.")
        return 0
    }
}
