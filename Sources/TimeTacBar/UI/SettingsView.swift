import SwiftUI
import TimeTacKit

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var pollInterval: Double = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TimeTacBar Settings").font(.title2).fontWeight(.semibold)

            Form {
                Section {
                    LabeledContent("Account", value: state.configuration.account.isEmpty
                                   ? "Not set" : state.configuration.account)
                    LabeledContent("Server", value: state.configuration.host.displayName)
                    LabeledContent("Signed in as", value: state.user?.displayName
                                   ?? (state.configuration.username.isEmpty ? "Nobody" : state.configuration.username))
                    Button("Company setup…") {
                        openWindow(id: WindowID.companySetup)
                        activateApp()
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("The account and API credentials are company-wide — set once, then everyone signs in with their own username and password.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section {
                    Picker("Check status every", selection: $pollInterval) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                } footer: {
                    Text("The elapsed timer counts locally every second regardless — this is how often TimeTacBar re-checks the server.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Tasks") {
                    LabeledContent("Loaded", value: "\(state.allTasks.count) tasks, \(state.breakTasks.count) break")
                    Button("Reload task list") { Task { await state.reloadTasks() } }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Sign out", role: .destructive) {
                    Task { await state.signOut() }
                }
                .disabled(state.phase == .setup)

                Button(state.phase == .ready ? "Switch account…" : "Sign in…") {
                    openWindow(id: WindowID.login)
                    activateApp()
                }

                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear {
            pollInterval = state.configuration.pollInterval
        }
        .onChange(of: pollInterval) { _, newValue in
            Task { await state.updateSettings(pollInterval: newValue) }
        }
    }
}
