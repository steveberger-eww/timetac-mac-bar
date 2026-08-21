import Foundation
import Testing
@testable import TimeTacKit

@Suite("Endpoint construction")
struct EndpointTests {
    private let base = URL(string: "https://api.timetac.com/acme")!

    private func url(_ endpoint: Endpoint, style: APIPathStyle = .v4) throws -> URLComponents {
        let url = try #require(endpoint.url(baseURL: base, pathStyle: style))
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    @Test("Builds the documented path, including the uppercase V4 segment")
    func pathShape() throws {
        let components = try url(TimeTacEndpoints.currentTracking())
        #expect(components.host == "api.timetac.com")
        #expect(components.path == "/acme/V4/timeTrackings/current/")
    }

    @Test("Uses the userapi prefix when the account needs that style")
    func alternatePathStyle() throws {
        let components = try url(TimeTacEndpoints.currentTracking(), style: .userapiV4)
        #expect(components.path == "/acme/userapi/v4/timeTrackings/current/")
    }

    @Test("Encodes equality filters as a bare field")
    func equalityFilter() throws {
        let components = try url(TimeTacEndpoints.statusOverview(userID: 5))
        let items = try #require(components.queryItems)
        #expect(items.contains(URLQueryItem(name: "user_id", value: "5")))
        #expect(!items.contains { $0.name == "_op__user_id" })
    }

    /// Anything other than equality needs the companion `_op__` item or the API ignores it.
    @Test("Pairs comparison filters with an _op__ item")
    func comparisonFilter() throws {
        let components = try url(
            TimeTacEndpoints.trackingsSince(userID: 5, dayStart: "2026-08-21 00:00:00")
        )
        let items = try #require(components.queryItems)
        #expect(items.contains(URLQueryItem(name: "_op__start_time", value: "gteq")))
        #expect(items.contains(URLQueryItem(name: "start_time", value: "2026-08-21 00:00:00")))
    }

    @Test("Start sends the required user_id and timezone, and omits task_id when unset")
    func startBody() throws {
        let withTask = TimeTacEndpoints.startTracking(userID: 5, taskID: 101, timeZone: "Europe/Vienna")
        #expect(withTask.method == .post)
        #expect(withTask.body?["user_id"] == .int(5))
        #expect(withTask.body?["task_id"] == .int(101))
        #expect(withTask.body?["start_time_timezone"] == .string("Europe/Vienna"))

        let withoutTask = TimeTacEndpoints.startTracking(userID: 5, taskID: nil, timeZone: "Europe/Vienna")
        #expect(withoutTask.body?["task_id"] == nil)
    }

    @Test("Stop is a PUT carrying end_time_timezone, which the API requires")
    func stopBody() throws {
        let endpoint = TimeTacEndpoints.stopTracking(userID: 5, timeZone: "Europe/Vienna")
        #expect(endpoint.method == .put)
        #expect(endpoint.body?["user_id"] == .int(5))
        #expect(endpoint.body?["end_time_timezone"] == .string("Europe/Vienna"))
    }

    @Test("Percent-encodes form bodies for the token endpoint")
    func formEncoding() {
        let encoded = TokenStore.formEncode([
            "grant_type": "password",
            "password": "p@ss w/ord+1",
        ])
        // Sorted by key, so grant_type leads.
        #expect(encoded == "grant_type=password&password=p%40ss%20w%2Ford%2B1")
    }
}
