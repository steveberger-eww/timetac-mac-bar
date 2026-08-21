import SwiftUI
import TimeTacKit

/// The one-time, company-level half of the setup: which TimeTac account, and which OAuth client
/// to present as. Everyone in a company shares these, so this is filled in once — or baked into
/// the build, in which case nobody ever sees this screen.
struct CompanySetupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var address = ""
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var isSaving = false

    /// What `address` resolves to, shown back so a typo is obvious before signing in.
    private var locator: AccountLocator? { AccountLocator.parse(address) }

    private var canSave: Bool {
        locator != nil && !clientID.isEmpty && !isSaving
            && (!clientSecret.isEmpty || state.hasClientSecret)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Company setup").font(.title2).fontWeight(.semibold)
                Text("These are the same for everyone in your company and only need setting once. Your own username and password come next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section {
                    TextField("TimeTac address", text: $address,
                              prompt: Text("https://go.timetac.com/yourcompany"))
                } header: {
                    Text("Account")
                } footer: {
                    resolvedFooter
                }

                Section {
                    TextField("Client ID", text: $clientID)
                    SecureField(state.hasClientSecret ? "Client secret (unchanged)" : "Client secret",
                                text: $clientSecret)
                } header: {
                    Text("API credentials")
                } footer: {
                    Text("In TimeTac: Settings → API Credentials → Create. They belong to the company account, not to you, so the same pair works for every colleague. Note the expiry date you set — a pair that has lapsed is rejected as an invalid client.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)

            if let error = state.lastError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear(perform: prefill)
    }

    @ViewBuilder
    private var resolvedFooter: some View {
        Group {
            if let locator {
                let server = locator.host ?? state.configuration.host
                Text("Account “\(locator.account)” on \(server.displayName.lowercased()).")
            } else if address.isEmpty {
                Text("Paste the address you use for TimeTac in the browser, or type just the account name.")
            } else {
                Text("That doesn't look like a TimeTac address or account name.")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func prefill() {
        let configuration = state.configuration
        if address.isEmpty, !configuration.account.isEmpty {
            address = "https://\(configuration.host.webHost)/\(configuration.account)"
        }
        if clientID.isEmpty { clientID = configuration.clientID }
        // A stored secret never comes back out of the Keychain into a field. Blank means "keep
        // what's already there", so coming back here to fix a typo in the account doesn't mean
        // hunting the secret down again.
    }

    private func save() {
        guard let locator else { return }
        isSaving = true
        Task {
            await state.saveCompanySetup(
                account: locator.account,
                host: locator.host ?? state.configuration.host,
                clientID: clientID,
                clientSecret: clientSecret
            )
            isSaving = false
            if state.configuration.hasCompanySetup {
                dismiss()
                openWindow(id: WindowID.login)
                activateApp()
            }
        }
    }
}
