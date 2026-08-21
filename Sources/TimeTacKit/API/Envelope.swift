import Foundation

/// Every TimeTac resource response is wrapped in this envelope.
///
/// The important quirk: a failed call still comes back as **HTTP 200** with `Success: false` and an
/// `Error` / `ErrorMessage` pair. Checking the status code alone silently swallows real failures, so
/// `TimeTacClient` always decodes this and inspects `Success`.
public struct APIEnvelope<Element: Decodable & Sendable>: Decodable, Sendable {
    public let success: Bool
    public let numResults: Int?
    public let resourceName: String?
    public let serverTimeZone: String?
    public let results: [Element]
    public let error: Int?
    public let errorMessage: String?

    private enum CodingKeys: String, CodingKey {
        case success = "Success"
        case numResults = "NumResults"
        case resourceName = "ResourceName"
        case serverTimeZone = "ServerTimeZone"
        case results = "Results"
        case error = "Error"
        case errorMessage = "ErrorMessage"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = (try? container.decode(Bool.self, forKey: .success)) ?? false
        numResults = try? container.decode(Int.self, forKey: .numResults)
        resourceName = try? container.decode(String.self, forKey: .resourceName)
        serverTimeZone = try? container.decode(String.self, forKey: .serverTimeZone)
        // Actions like `stop` can answer with an empty or absent Results array.
        results = (try? container.decode([Element].self, forKey: .results)) ?? []

        // `Error` is an integer in practice but has been seen as a string; accept either.
        if let code = try? container.decode(Int.self, forKey: .error) {
            error = code
        } else if let text = try? container.decode(String.self, forKey: .error) {
            error = Int(text)
        } else {
            error = nil
        }
        errorMessage = try? container.decode(String.self, forKey: .errorMessage)
    }
}

/// OAuth token response from `POST {base}/auth/oauth2/token`.
public struct TokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let tokenType: String?
    public let expiresIn: Int?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

/// Error body from the auth endpoint, which does *not* use the resource envelope.
struct OAuthErrorBody: Decodable {
    let error: String?
    let errorDescription: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

public enum TimeTacError: Error, LocalizedError, Sendable {
    /// Account name / client id / username not filled in yet.
    case notConfigured
    /// The client secret is in the Keychain but macOS wouldn't release it to this build.
    case keychainDenied(OSStatus)
    /// No stored credentials — the user needs to sign in.
    case notAuthenticated
    /// Token rejected. Triggers exactly one refresh-and-retry before surfacing.
    case unauthorized(String?)
    /// Path or account not found — also how a wrong `APIPathStyle` shows up.
    case notFound
    /// HTTP-level failure that isn't 401/404.
    case http(status: Int, body: String)
    /// `Success: false` inside an otherwise-200 envelope.
    case api(code: Int?, message: String)
    case decoding(String)
    case transport(String)
    /// Sign-in failed at the OAuth endpoint.
    case authFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "TimeTacBar isn't set up yet. Add your account name and API credentials in Settings."
        case .keychainDenied(let status):
            """
            macOS wouldn't release the saved client secret (Keychain error \(status)). \
            That happens when the app is rebuilt with a different signature. \
            Re-enter the client secret under Company setup to fix it.
            """
        case .notAuthenticated:
            "You're signed out. Sign in to continue."
        case .unauthorized(let message):
            message ?? "Your session expired. Please sign in again."
        case .notFound:
            "The server couldn't find that endpoint or account. Check the account name in Settings."
        case .http(let status, let body):
            "The server returned HTTP \(status).\(body.isEmpty ? "" : " \(body.prefix(200))")"
        case .api(let code, let message):
            code.map { "TimeTac error \($0): \(message)" } ?? message
        case .decoding(let detail):
            "Couldn't read the server's response. \(detail)"
        case .transport(let detail):
            detail
        case .authFailed(let detail):
            detail
        }
    }

    /// Whether it's worth refreshing the token and trying once more.
    public var isAuthExpiry: Bool {
        switch self {
        case .unauthorized: true
        case .api(let code, _): code == 401
        default: false
        }
    }
}

extension UInt8 {
    /// ASCII whitespace, for sniffing a response body's first meaningful character.
    var isWhitespaceByte: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0D
    }
}
