import SwiftUI
import TimeTacKit

/// Just the per-person half. Which company account and which OAuth client to use is company
/// setup — baked into the build or entered once — so this matches what TimeTac's own web login
/// asks for once you're past the account name.
struct LoginView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var username = ""
    @State private var password = ""
    @State private var remember = true

    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !state.isBusy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sign in to TimeTac").font(.title2).fontWeight(.semibold)
                Text("Your credentials are stored in the macOS Keychain and never leave this Mac except to sign in to TimeTac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                Section {
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    Toggle("Stay signed in", isOn: $remember)
                } header: {
                    accountHeader
                } footer: {
                    Text(remember
                         ? "Your password is kept in the Keychain so the session survives token expiry — you won't be asked again."
                         : "Without this you'll need to sign in again whenever the refresh token expires.")
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
                if state.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sign in") {
                    Task {
                        await state.signIn(username: username, password: password, remember: remember)
                        if state.phase == .ready { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear {
            username = state.configuration.username
            remember = state.configuration.stickySignIn
        }
    }

    /// Names the account being signed in to, with a way out for whoever needs to change it —
    /// which, for most people, is never.
    private var accountHeader: some View {
        HStack(spacing: 6) {
            Text(state.configuration.account.isEmpty
                 ? "No company account set up"
                 : "\(state.configuration.account) · \(state.configuration.host.displayName.lowercased())")
            Spacer()
            Button("Company setup…") {
                dismiss()
                openWindow(id: WindowID.companySetup)
                activateApp()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}
