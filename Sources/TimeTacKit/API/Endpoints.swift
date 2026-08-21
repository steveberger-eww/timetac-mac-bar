import Foundation

/// A `Sendable` stand-in for arbitrary JSON, so request bodies don't need `[String: Any]`.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var encodable: Any {
        switch self {
        case .string(let value): value
        case .int(let value): value
        case .double(let value): value
        case .bool(let value): value
        case .null: NSNull()
        }
    }
}

/// Query parameters in TimeTac's convention.
///
/// Equality is the bare `field=value`. Any other comparison needs a companion
/// `_op__field=<operator>` item — that's how their `RequestParamsBuilder` encodes it, and the API
/// ignores the value otherwise.
public struct QueryBuilder: Sendable {
    private var items: [URLQueryItem] = []

    public init() {}

    public func eq(_ field: String, _ value: some CustomStringConvertible) -> QueryBuilder {
        var copy = self
        copy.items.append(URLQueryItem(name: field, value: String(describing: value)))
        return copy
    }

    public func op(_ field: String, _ operation: String, _ value: some CustomStringConvertible) -> QueryBuilder {
        var copy = self
        copy.items.append(URLQueryItem(name: "_op__\(field)", value: operation))
        copy.items.append(URLQueryItem(name: field, value: String(describing: value)))
        return copy
    }

    public func gteq(_ field: String, _ value: some CustomStringConvertible) -> QueryBuilder {
        op(field, "gteq", value)
    }

    public func lteq(_ field: String, _ value: some CustomStringConvertible) -> QueryBuilder {
        op(field, "lteq", value)
    }

    /// `in` takes a pipe-separated list.
    public func `in`(_ field: String, _ values: [some CustomStringConvertible]) -> QueryBuilder {
        op(field, "in", values.map { String(describing: $0) }.joined(separator: "|"))
    }

    public func limit(_ value: Int) -> QueryBuilder {
        var copy = self
        copy.items.append(URLQueryItem(name: "_limit", value: String(value)))
        return copy
    }

    public func orderBy(_ field: String, descending: Bool = false) -> QueryBuilder {
        var copy = self
        copy.items.append(URLQueryItem(name: "_order_by", value: field))
        copy.items.append(URLQueryItem(name: "_sort_direction", value: descending ? "DESC" : "ASC"))
        return copy
    }

    public var queryItems: [URLQueryItem] { items }
}

public struct Endpoint: Sendable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    public let resource: String
    public let action: String
    public let method: Method
    public let query: [URLQueryItem]
    public let body: [String: JSONValue]?

    public init(
        resource: String,
        action: String,
        method: Method = .get,
        query: QueryBuilder = QueryBuilder(),
        body: [String: JSONValue]? = nil
    ) {
        self.resource = resource
        self.action = action
        self.method = method
        self.query = query.queryItems
        self.body = body
    }

    /// `https://api.timetac.com/{account}/V4/{resource}/{action}/?…`
    public func url(baseURL: URL, pathStyle: APIPathStyle) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let base = components?.path ?? ""
        components?.path = "\(base)/\(pathStyle.rawValue)/\(resource)/\(action)/"
        components?.queryItems = query.isEmpty ? nil : query
        return components?.url
    }
}

// MARK: - The endpoints this app actually uses

public enum TimeTacEndpoints {
    public static func currentUser() -> Endpoint {
        Endpoint(resource: "users", action: "me")
    }

    public static func users(username: String) -> Endpoint {
        Endpoint(resource: "users", action: "read", query: QueryBuilder().eq("username", username))
    }

    public static func currentTracking() -> Endpoint {
        Endpoint(resource: "timeTrackings", action: "current")
    }

    public static func statusOverview(userID: Int) -> Endpoint {
        Endpoint(
            resource: "userStatusOverview",
            action: "read",
            query: QueryBuilder().eq("user_id", userID)
        )
    }

    public static func tasks() -> Endpoint {
        Endpoint(
            resource: "tasks",
            action: "read",
            query: QueryBuilder().limit(2000).orderBy("name")
        )
    }

    public static func favouriteTasks(userID: Int) -> Endpoint {
        Endpoint(
            resource: "favouriteTasks",
            action: "read",
            query: QueryBuilder().eq("user_id", userID).limit(200)
        )
    }

    public static func recentTasks(userID: Int) -> Endpoint {
        Endpoint(
            resource: "recentTasks",
            action: "read",
            query: QueryBuilder().eq("user_id", userID).limit(50).orderBy("last_started", descending: true)
        )
    }

    /// `task_id` is optional — omitting it lets the server pick the user's default task.
    public static func startTracking(userID: Int, taskID: Int?, timeZone: String) -> Endpoint {
        var body: [String: JSONValue] = [
            "user_id": .int(userID),
            "start_time_timezone": .string(timeZone),
            // 1 = live booking, as opposed to a post-dated correction.
            "start_type_id": .int(1),
        ]
        if let taskID { body["task_id"] = .int(taskID) }
        return Endpoint(resource: "timeTrackings", action: "start", method: .post, body: body)
    }

    public static func stopTracking(userID: Int, timeZone: String) -> Endpoint {
        Endpoint(
            resource: "timeTrackings",
            action: "stop",
            method: .put,
            body: [
                "user_id": .int(userID),
                "end_time_timezone": .string(timeZone),
                "end_type_id": .int(1),
            ]
        )
    }

    /// Trackings that began today, for the day's total.
    public static func trackingsSince(userID: Int, dayStart: String) -> Endpoint {
        Endpoint(
            resource: "timeTrackings",
            action: "read",
            query: QueryBuilder()
                .eq("user_id", userID)
                .gteq("start_time", dayStart)
                .limit(200)
        )
    }

    public static func absenceDays(userID: Int, date: String) -> Endpoint {
        Endpoint(
            resource: "absenceDays",
            action: "read",
            query: QueryBuilder().eq("user_id", userID).eq("date", date)
        )
    }
}
