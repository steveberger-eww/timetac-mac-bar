import Foundation

/// Turns whatever a user has to hand — a bare account name, or the TimeTac web address they've
/// got open in a browser tab — into an account plus the server it lives on.
///
/// Asking for the account name and the server separately makes the user translate
/// `https://go.timetac.com/yourcompany` into two fields; both are already in the URL.
public struct AccountLocator: Equatable, Sendable {
    public var account: String
    /// `nil` when the input was a bare account name and so said nothing about which server.
    public var host: TimeTacHost?

    public init(account: String, host: TimeTacHost? = nil) {
        self.account = account
        self.host = host
    }

    /// The web app and the API live on different hostnames for the same deployment.
    private static let hosts: [String: TimeTacHost] = [
        "go.timetac.com": .production,
        "api.timetac.com": .production,
        "go-sandbox.timetac.com": .sandbox,
        "api-sandbox.timetac.com": .sandbox,
    ]

    private static let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    /// `nil` when there's no plausible account name in the input.
    public static func parse(_ input: String) -> AccountLocator? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if text.lowercased().hasPrefix("www.") { text = String(text.dropFirst(4)) }

        // Anything after the account segment — further path, query, fragment — is noise.
        let segments = text.split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
        guard let first = segments.first.map(String.init) else { return nil }

        if let host = hosts[first.lowercased()] {
            guard segments.count > 1 else { return nil }
            return validated(String(segments[1]), host: host)
        }

        // A hostname we don't know isn't an account name — better to reject than to try signing
        // in to a nonsense account.
        guard !first.contains(".") else { return nil }
        return validated(first, host: nil)
    }

    private static func validated(_ account: String, host: TimeTacHost?) -> AccountLocator? {
        guard !account.isEmpty,
              account.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return AccountLocator(account: account, host: host)
    }
}
