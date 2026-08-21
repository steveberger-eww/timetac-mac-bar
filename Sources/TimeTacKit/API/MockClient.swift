import Foundation

/// In-memory stand-in for the real API.
///
/// Exists so the entire app — menu bar item, dropdown, task picker, elapsed timer — can be built
/// and driven before TimeTac issues API credentials. Enabled with `TIMETACBAR_MOCK=1`.
public actor MockClient: TimeTacAPI {
    private let user = TTUser(id: 42, username: "demo", firstname: "Demo", lastname: "User",
                              fullname: "Demo User")

    private let catalogue: [TTTask] = [
        TTTask(id: 101, name: "Development", namePath: "Internal / Development", isFavourite: true),
        TTTask(id: 102, name: "Code review", namePath: "Internal / Code review", isFavourite: true),
        TTTask(id: 103, name: "Meetings", namePath: "Internal / Meetings"),
        TTTask(id: 104, name: "Support", namePath: "Customers / Support"),
        TTTask(id: 105, name: "Migration", namePath: "Customers / Acme / Migration"),
        TTTask(id: 106, name: "Documentation", namePath: "Internal / Documentation"),
        TTTask(id: 900, name: "Break", namePath: "Break", isNonworking: true),
        TTTask(id: 901, name: "Lunch", namePath: "Lunch", isNonworking: true),
    ]

    private var running: TimeTracking?
    private var finishedToday: [TimeTracking] = []
    private var nextID = 5000

    /// Seeds a tracking that started earlier today so the elapsed timer has something to show
    /// immediately on launch.
    public init(startRunning: Bool = true) {
        if startRunning {
            let started = Date().addingTimeInterval(-2 * 3600 - 14 * 60)
            running = TimeTracking(
                id: 4999,
                userID: 42,
                taskID: 101,
                startTime: TimeTacTime.wallClock(started),
                startTimeTimezone: TimeZone.current.identifier
            )
        }
    }

    public func currentUser() async throws -> TTUser { user }

    public func statusOverview(userID: Int) async throws -> UserStatusOverview? {
        guard let running else {
            return UserStatusOverview(userID: userID, status: 0, isRunning: false)
        }
        return UserStatusOverview(
            userID: userID,
            status: running.isNonworking ? 2 : 1,
            isRunning: true,
            timeTrackingID: running.id,
            timeTrackingStartTime: running.startTime,
            timeTrackingStartTimeTimezoneID: running.startTimeTimezone,
            timeTrackingTaskID: running.taskID,
            timeTrackingIsNonworking: running.isNonworking,
            userFullname: user.fullname
        )
    }

    public func currentTracking() async throws -> TimeTracking? { running }

    public func tasks() async throws -> [TTTask] { catalogue }

    public func favouriteTaskIDs(userID: Int) async throws -> [Int] { [101, 102] }

    public func recentTaskIDs(userID: Int) async throws -> [Int] { [105, 103, 104] }

    public func trackingsToday(userID: Int) async throws -> [TimeTracking] {
        finishedToday + [running].compactMap { $0 }
    }

    public func absenceDaysToday(userID: Int) async throws -> [AbsenceDay] { [] }

    @discardableResult
    public func startTracking(userID: Int, taskID: Int?) async throws -> TimeTracking? {
        closeRunning()
        let task = catalogue.first { $0.id == taskID }
        nextID += 1
        let tracking = TimeTracking(
            id: nextID,
            userID: userID,
            taskID: taskID ?? 101,
            startTime: TimeTacTime.wallClock(Date()),
            startTimeTimezone: TimeZone.current.identifier,
            isNonworking: task?.isNonworking ?? false
        )
        running = tracking
        return tracking
    }

    public func stopTracking(userID: Int) async throws {
        closeRunning()
    }

    private func closeRunning() {
        guard let running else { return }
        finishedToday.append(TimeTracking(
            id: running.id,
            userID: running.userID,
            taskID: running.taskID,
            startTime: running.startTime,
            startTimeTimezone: running.startTimeTimezone,
            endTime: TimeTacTime.wallClock(Date()),
            endTimeTimezone: TimeZone.current.identifier,
            isNonworking: running.isNonworking
        ))
        self.running = nil
    }
}
