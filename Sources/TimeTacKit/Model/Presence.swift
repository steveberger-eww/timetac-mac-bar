import Foundation

/// `userStatusOverview.status`, as documented in the v4 spec.
public enum PresenceStatus: Int, Sendable, CaseIterable {
    case offline = 0
    case working = 1
    case onBreak = 2
    case onLeave = 3
    case coreTimeViolation = 5

    public init(rawStatus: Int) {
        self = PresenceStatus(rawValue: rawStatus) ?? .offline
    }

    public var label: String {
        switch self {
        case .offline: "Clocked out"
        case .working: "Working"
        case .onBreak: "On a break"
        case .onLeave: "On leave"
        case .coreTimeViolation: "Outside core time"
        }
    }

    /// SF Symbol name. Kept as a string so this module stays free of SwiftUI.
    public var symbolName: String {
        switch self {
        case .offline: "circle"
        case .working: "circle.fill"
        case .onBreak: "pause.circle.fill"
        case .onLeave: "beach.umbrella.fill"
        case .coreTimeViolation: "exclamationmark.circle.fill"
        }
    }

    /// Whether a tracking is ticking, and so whether to show elapsed time.
    public var isTracking: Bool {
        self == .working || self == .onBreak || self == .coreTimeViolation
    }
}

/// Everything the menu bar and dropdown render from — one snapshot, so the UI never has to
/// reconcile half-updated fields.
public struct PresenceSnapshot: Sendable, Equatable {
    public var status: PresenceStatus
    public var taskID: Int?
    public var taskName: String?
    public var startedAt: Date?
    public var todayTotal: TimeInterval
    public var leave: [AbsenceDay]

    public init(
        status: PresenceStatus = .offline,
        taskID: Int? = nil,
        taskName: String? = nil,
        startedAt: Date? = nil,
        todayTotal: TimeInterval = 0,
        leave: [AbsenceDay] = []
    ) {
        self.status = status
        self.taskID = taskID
        self.taskName = taskName
        self.startedAt = startedAt
        self.todayTotal = todayTotal
        self.leave = leave
    }

    /// How long the current tracking has been running, as of `reference`.
    public func elapsed(asOf reference: Date = Date()) -> TimeInterval? {
        guard status.isTracking, let startedAt else { return nil }
        return max(0, reference.timeIntervalSince(startedAt))
    }

    /// Sums today's working time, counting a still-running tracking up to now and skipping breaks.
    public static func workedSeconds(
        in trackings: [TimeTracking],
        now: Date = Date()
    ) -> TimeInterval {
        trackings.reduce(0) { total, tracking in
            guard !tracking.isNonworking, let start = tracking.startDate else { return total }
            let end = tracking.endDate ?? now
            return total + max(0, end.timeIntervalSince(start))
        }
    }

    /// Derives status from the two sources that report it, preferring the overview.
    public static func status(
        overview: UserStatusOverview?,
        tracking: TimeTracking?
    ) -> PresenceStatus {
        if let overview, overview.isRunning || overview.status != 0 {
            return PresenceStatus(rawStatus: overview.status)
        }
        guard let tracking, tracking.isRunning else { return .offline }
        return tracking.isNonworking ? .onBreak : .working
    }
}
