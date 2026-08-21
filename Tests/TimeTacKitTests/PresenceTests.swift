import Foundation
import Testing
@testable import TimeTacKit

@Suite("Presence")
struct PresenceTests {
    private let vienna = "Europe/Vienna"

    private func overview(status: Int, running: Bool, nonworking: Bool = false) -> UserStatusOverview {
        UserStatusOverview(
            userID: 5,
            status: status,
            isRunning: running,
            timeTrackingStartTime: "2026-08-21 08:15:00",
            timeTrackingStartTimeTimezoneID: vienna,
            timeTrackingTaskID: 101,
            timeTrackingIsNonworking: nonworking
        )
    }

    @Test("Maps the documented status codes")
    func statusCodes() {
        #expect(PresenceStatus(rawStatus: 0) == .offline)
        #expect(PresenceStatus(rawStatus: 1) == .working)
        #expect(PresenceStatus(rawStatus: 2) == .onBreak)
        #expect(PresenceStatus(rawStatus: 3) == .onLeave)
        #expect(PresenceStatus(rawStatus: 5) == .coreTimeViolation)
        // 4 is unassigned in the spec; anything unknown should read as offline rather than crash.
        #expect(PresenceStatus(rawStatus: 4) == .offline)
    }

    @Test("Prefers the status overview over the raw tracking")
    func overviewWins() {
        let status = PresenceSnapshot.status(overview: overview(status: 2, running: true), tracking: nil)
        #expect(status == .onBreak)
    }

    /// If the overview read fails or is empty, a running tracking is still enough to tell working
    /// from break from clocked out.
    @Test("Falls back to the running tracking when there's no overview")
    func trackingFallback() {
        let working = TimeTracking(id: 1, userID: 5, taskID: 101,
                                   startTime: "2026-08-21 08:15:00", startTimeTimezone: vienna)
        #expect(PresenceSnapshot.status(overview: nil, tracking: working) == .working)

        let onBreak = TimeTracking(id: 2, userID: 5, taskID: 900,
                                   startTime: "2026-08-21 12:00:00", startTimeTimezone: vienna,
                                   isNonworking: true)
        #expect(PresenceSnapshot.status(overview: nil, tracking: onBreak) == .onBreak)

        let finished = TimeTracking(id: 3, userID: 5, taskID: 101,
                                    startTime: "2026-08-21 08:15:00", startTimeTimezone: vienna,
                                    endTime: "2026-08-21 12:00:00", endTimeTimezone: vienna)
        #expect(PresenceSnapshot.status(overview: nil, tracking: finished) == .offline)
        #expect(PresenceSnapshot.status(overview: nil, tracking: nil) == .offline)
    }

    @Test("Shows elapsed time only while something is running")
    func elapsedOnlyWhenTracking() {
        let started = Date().addingTimeInterval(-3600)
        let running = PresenceSnapshot(status: .working, startedAt: started)
        let elapsed = try? #require(running.elapsed())
        #expect((elapsed ?? 0) >= 3599)

        #expect(PresenceSnapshot(status: .offline, startedAt: started).elapsed() == nil)
        #expect(PresenceSnapshot(status: .working, startedAt: nil).elapsed() == nil)
    }
}

@Suite("Today's total")
struct WorkedSecondsTests {
    private let vienna = "Europe/Vienna"

    private func tracking(
        id: Int, start: String, end: String? = nil, nonworking: Bool = false
    ) -> TimeTracking {
        TimeTracking(id: id, userID: 5, taskID: 101, startTime: start,
                     startTimeTimezone: vienna, endTime: end,
                     endTimeTimezone: end == nil ? nil : vienna, isNonworking: nonworking)
    }

    @Test("Sums closed trackings and skips breaks")
    func excludesBreaks() throws {
        let now = try #require(TimeTacTime.parse("2026-08-21 12:00:00", timeZone: vienna))
        let total = PresenceSnapshot.workedSeconds(in: [
            tracking(id: 1, start: "2026-08-21 08:00:00", end: "2026-08-21 10:00:00"),
            tracking(id: 2, start: "2026-08-21 10:00:00", end: "2026-08-21 10:30:00", nonworking: true),
            tracking(id: 3, start: "2026-08-21 10:30:00", end: "2026-08-21 11:00:00"),
        ], now: now)

        // 2h + 30m of work; the 30m break doesn't count.
        #expect(total == 2.5 * 3600)
    }

    @Test("Counts a still-running tracking up to now")
    func countsRunningTracking() throws {
        let now = try #require(TimeTacTime.parse("2026-08-21 12:00:00", timeZone: vienna))
        let total = PresenceSnapshot.workedSeconds(in: [
            tracking(id: 1, start: "2026-08-21 09:00:00"),
        ], now: now)
        #expect(total == 3 * 3600)
    }

    @Test("Ignores rows with no parseable start time")
    func ignoresUnparseable() throws {
        let now = try #require(TimeTacTime.parse("2026-08-21 12:00:00", timeZone: vienna))
        let total = PresenceSnapshot.workedSeconds(in: [tracking(id: 1, start: "")], now: now)
        #expect(total == 0)
    }
}

@Suite("Time and formatting")
struct TimeTests {
    /// TimeTac sends wall-clock strings with the zone in a sibling field, so parsing has to take
    /// the zone explicitly — otherwise the elapsed timer is off by the UTC offset.
    @Test("Parses wall-clock timestamps in the supplied zone")
    func parsesWithZone() throws {
        let vienna = try #require(TimeTacTime.parse("2026-08-21 08:15:00", timeZone: "Europe/Vienna"))
        let utc = try #require(TimeTacTime.parse("2026-08-21 08:15:00", timeZone: "UTC"))
        // Vienna is UTC+2 in August, so the same wall clock is two hours earlier in absolute time.
        #expect(utc.timeIntervalSince(vienna) == 2 * 3600)
    }

    @Test("Returns nil for empty or missing input")
    func parsesNothing() {
        #expect(TimeTacTime.parse(nil, timeZone: "UTC") == nil)
        #expect(TimeTacTime.parse("", timeZone: "UTC") == nil)
    }

    @Test("Round-trips the wall-clock format the API expects back")
    func roundTrip() throws {
        let zone = try #require(TimeZone(identifier: "Europe/Vienna"))
        let date = try #require(TimeTacTime.parse("2026-08-21 08:15:00", timeZone: "Europe/Vienna"))
        #expect(TimeTacTime.wallClock(date, timeZone: zone) == "2026-08-21 08:15:00")
        #expect(TimeTacTime.day(date, timeZone: zone) == "2026-08-21")
    }

    @Test("Formats durations for the menu bar and the dropdown")
    func durations() {
        #expect(DurationFormat.compact(2 * 3600 + 14 * 60) == "2:14")
        #expect(DurationFormat.compact(12 * 60) == "0:12")
        #expect(DurationFormat.compact(-5) == "0:00")
        #expect(DurationFormat.long(2 * 3600 + 14 * 60) == "2h 14m")
        #expect(DurationFormat.long(14 * 60) == "14m")
    }
}

@Suite("Task classification")
struct TaskTests {
    @Test("Separates startable work from breaks")
    func workableVersusBreak() {
        let work = TTTask(id: 1, name: "Development")
        let pause = TTTask(id: 900, name: "Break", isNonworking: true)
        let blocked = TTTask(id: 2, name: "Archived", isStartable: false)
        let finished = TTTask(id: 3, name: "Shipped", status: 2)

        #expect(work.isWorkable && !work.isBreak)
        #expect(pause.isBreak && !pause.isWorkable)
        #expect(!blocked.isWorkable && !blocked.isBreak)
        #expect(!finished.isWorkable, "a finished task shouldn't be offered")
    }

    @Test("Falls back to the bare name when there's no path")
    func displayPath() {
        #expect(TTTask(id: 1, name: "Dev", namePath: "Internal / Dev").displayPath == "Internal / Dev")
        #expect(TTTask(id: 1, name: "Dev").displayPath == "Dev")
    }
}
