import SwiftUI
import TimeTacKit

/// Custom entry point so `--probe` can run as a plain CLI without ever starting the UI.
@main
enum EntryPoint {
    static func main() {
        if CommandLine.arguments.contains("--probe") {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var exitCode: Int32 = 1
            // Detached deliberately: under the Swift 6 language mode `main()` is main-actor
            // isolated, so a plain `Task` would inherit that isolation and never get to run
            // against the `semaphore.wait()` blocking the main thread right below.
            Task.detached {
                exitCode = await Diagnostics.probe()
                semaphore.signal()
            }
            semaphore.wait()
            exit(exitCode)
        }
        TimeTacBarApp.main()
    }
}

struct TimeTacBarApp: App {
    @State private var state: AppState

    init() {
        let state = AppState()
        _state = State(initialValue: state)
        // Must happen at launch, not when the panel first opens: with `.menuBarExtraStyle(.window)`
        // SwiftUI builds the dropdown lazily on first click, so starting from the content view
        // would leave the status icon stale and polling stopped until the user clicked it.
        Task { @MainActor in await state.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environment(state)
        } label: {
            MenuBarLabel(snapshot: state.snapshot, tick: state.tick)
        }
        .menuBarExtraStyle(.window)

        Window("Sign in to TimeTac", id: WindowID.login) {
            LoginView()
                .environment(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Company setup", id: WindowID.companySetup) {
            CompanySetupView()
                .environment(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("TimeTacBar Settings", id: WindowID.settings) {
            SettingsView()
                .environment(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum WindowID {
    static let login = "login"
    static let companySetup = "companySetup"
    static let settings = "settings"
}

extension View {
    /// A menu-bar-only app never becomes frontmost on its own, so any window it opens has to ask.
    func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
}
