import Foundation

/// Everything the menu bar needs from TimeTac.
///
/// This is the seam `MockClient` plugs into, so the whole UI can be exercised before API
/// credentials exist.
public protocol TimeTacAPI: Sendable {
    /// The signed-in user. Needed because every write requires an explicit `user_id`.
    func currentUser() async throws -> TTUser
    func statusOverview(userID: Int) async throws -> UserStatusOverview?
    func currentTracking() async throws -> TimeTracking?
    func tasks() async throws -> [TTTask]
    func favouriteTaskIDs(userID: Int) async throws -> [Int]
    func recentTaskIDs(userID: Int) async throws -> [Int]
    func trackingsToday(userID: Int) async throws -> [TimeTracking]
    func absenceDaysToday(userID: Int) async throws -> [AbsenceDay]

    @discardableResult
    func startTracking(userID: Int, taskID: Int?) async throws -> TimeTracking?
    func stopTracking(userID: Int) async throws
}
