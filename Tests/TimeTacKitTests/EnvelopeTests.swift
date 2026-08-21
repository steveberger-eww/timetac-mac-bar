import Foundation
import Testing
@testable import TimeTacKit

@Suite("Response envelope")
struct EnvelopeTests {
    private func decode<T: Decodable & Sendable>(_ json: String, as: T.Type) throws -> APIEnvelope<T> {
        try JSONDecoder().decode(APIEnvelope<T>.self, from: Data(json.utf8))
    }

    @Test("Decodes a successful resource response")
    func successfulResponse() throws {
        let envelope = try decode(#"""
        {
          "Host": "api.timetac.com", "Success": true, "NumResults": 1,
          "ResourceName": "timeTrackings", "ServerTimeZone": "Europe/Vienna",
          "Results": [{"id": 12, "user_id": 5, "task_id": 101,
                       "start_time": "2026-08-21 08:15:00",
                       "start_time_timezone": "Europe/Vienna"}]
        }
        """#, as: TimeTracking.self)

        #expect(envelope.success)
        #expect(envelope.results.count == 1)
        #expect(envelope.results.first?.id == 12)
        #expect(envelope.serverTimeZone == "Europe/Vienna")
    }

    /// The whole reason `TimeTacClient` never trusts the status code on its own.
    @Test("Treats Success:false as a failure even though it arrives as HTTP 200")
    func failureInsideOkResponse() throws {
        let envelope = try decode(#"""
        {
          "Success": false, "ResourceName": "timeTrackings", "Error": 403,
          "ErrorMessage": "Generic access denied for user: 17 | Action:start"
        }
        """#, as: TimeTracking.self)

        #expect(envelope.success == false)
        #expect(envelope.error == 403)
        #expect(envelope.errorMessage?.contains("access denied") == true)
        #expect(envelope.results.isEmpty)
    }

    @Test("Survives an absent Results array, as stop returns")
    func missingResults() throws {
        let envelope = try decode(#"{"Success": true, "NumResults": 0}"#, as: TimeTracking.self)
        #expect(envelope.success)
        #expect(envelope.results.isEmpty)
    }

    @Test("Accepts Error as a string as well as an integer")
    func stringErrorCode() throws {
        let envelope = try decode(#"{"Success": false, "Error": "401", "ErrorMessage": "nope"}"#,
                                  as: TimeTracking.self)
        #expect(envelope.error == 401)
    }

    @Test("Reads the OAuth token response")
    func tokenResponse() throws {
        let token = try JSONDecoder().decode(TokenResponse.self, from: Data(#"""
        {"access_token": "abc", "refresh_token": "def", "token_type": "bearer", "expires_in": 3600}
        """#.utf8))
        #expect(token.accessToken == "abc")
        #expect(token.refreshToken == "def")
        #expect(token.expiresIn == 3600)
    }
}

@Suite("Lenient scalar decoding")
struct LenientDecodingTests {
    /// TimeTac's backend returns the same field as an int, a string or a bool depending on the
    /// endpoint, so every DTO field goes through the flexible helpers.
    @Test("Reads booleans written as 1, \"1\" and true")
    func flexibleBooleans() throws {
        for raw in ["1", "\"1\"", "true"] {
            let json = #"{"id": 1, "name": "Break", "is_nonworking": \#(raw), "is_startable": 1}"#
            let task = try JSONDecoder().decode(TTTask.self, from: Data(json.utf8))
            #expect(task.isNonworking, "is_nonworking as \(raw) should decode to true")
            #expect(task.isStartable)
        }
    }

    @Test("Reads numbers written as strings")
    func flexibleIntegers() throws {
        let json = #"{"id": "77", "user_id": "5", "task_id": 101, "start_time": "2026-08-21 08:15:00"}"#
        let tracking = try JSONDecoder().decode(TimeTracking.self, from: Data(json.utf8))
        #expect(tracking.id == 77)
        #expect(tracking.userID == 5)
        #expect(tracking.taskID == 101)
    }

    @Test("Treats null and empty string as absent")
    func nullHandling() throws {
        let json = #"{"id": 3, "name": "Task", "name_path": null, "is_favourite": null}"#
        let task = try JSONDecoder().decode(TTTask.self, from: Data(json.utf8))
        #expect(task.namePath == nil)
        #expect(task.isFavourite == false)
        #expect(task.displayPath == "Task")
    }
}

@Suite("Response body sniffing")
struct BodySniffingTests {
    /// A wrong path style answers with an HTML error page. That must drive the path probe, while a
    /// genuine JSON shape mismatch must surface as a decoding error instead of a bogus 404.
    @Test("Recognises an HTML error page")
    func detectsHTML() {
        #expect(TimeTacClient.looksLikeHTML(Data("<!DOCTYPE html><html>…".utf8)))
        #expect(TimeTacClient.looksLikeHTML(Data("\n  <html>".utf8)))
    }

    @Test("Doesn't mistake JSON for HTML")
    func ignoresJSON() {
        #expect(!TimeTacClient.looksLikeHTML(Data(#"{"Success": true}"#.utf8)))
        #expect(!TimeTacClient.looksLikeHTML(Data("  [1,2]".utf8)))
        #expect(!TimeTacClient.looksLikeHTML(Data()))
    }
}
