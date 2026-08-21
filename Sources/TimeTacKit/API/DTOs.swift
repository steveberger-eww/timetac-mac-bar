import Foundation

// MARK: - Lenient decoding
//
// TimeTac's PHP backend is loose about JSON scalars: the same field can arrive as `1`, `"1"`,
// `true`, or `null` depending on the endpoint and the record. Strict `Codable` synthesis breaks on
// that, so every field below goes through these helpers.

extension KeyedDecodingContainer {
    func flexibleInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? 1 : 0 }
        return nil
    }

    func flexibleBool(_ key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            switch value.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no", "": return false
            default: return nil
            }
        }
        return nil
    }

    func flexibleString(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value.isEmpty ? nil : value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func flexibleDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

// MARK: - Entities

public struct TTUser: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let username: String?
    public let firstname: String?
    public let lastname: String?
    public let fullname: String?

    public var displayName: String {
        if let fullname, !fullname.isEmpty { return fullname }
        let parts = [firstname, lastname].compactMap { $0 }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        return username ?? "User \(id)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, username, firstname, lastname, fullname
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleInt(.id) ?? 0
        username = c.flexibleString(.username)
        firstname = c.flexibleString(.firstname)
        lastname = c.flexibleString(.lastname)
        fullname = c.flexibleString(.fullname)
    }

    public init(id: Int, username: String? = nil, firstname: String? = nil,
                lastname: String? = nil, fullname: String? = nil) {
        self.id = id
        self.username = username
        self.firstname = firstname
        self.lastname = lastname
        self.fullname = fullname
    }
}

public struct TimeTracking: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let userID: Int?
    public let taskID: Int?
    public let startTime: String?
    public let startTimeTimezone: String?
    public let endTime: String?
    public let endTimeTimezone: String?
    public let isNonworking: Bool
    public let notes: String?
    public let duration: Double?

    /// Instant the tracking began, resolved through its own timezone field.
    public var startDate: Date? {
        TimeTacTime.parse(startTime, timeZone: startTimeTimezone)
    }

    public var endDate: Date? {
        TimeTacTime.parse(endTime, timeZone: endTimeTimezone ?? startTimeTimezone)
    }

    public var isRunning: Bool {
        endTime == nil || endTime?.isEmpty == true
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case taskID = "task_id"
        case startTime = "start_time"
        case startTimeTimezone = "start_time_timezone"
        case endTime = "end_time"
        case endTimeTimezone = "end_time_timezone"
        case isNonworking = "is_nonworking"
        case notes, duration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleInt(.id) ?? 0
        userID = c.flexibleInt(.userID)
        taskID = c.flexibleInt(.taskID)
        startTime = c.flexibleString(.startTime)
        startTimeTimezone = c.flexibleString(.startTimeTimezone)
        endTime = c.flexibleString(.endTime)
        endTimeTimezone = c.flexibleString(.endTimeTimezone)
        isNonworking = c.flexibleBool(.isNonworking) ?? false
        notes = c.flexibleString(.notes)
        duration = c.flexibleDouble(.duration)
    }

    public init(id: Int, userID: Int?, taskID: Int?, startTime: String?,
                startTimeTimezone: String?, endTime: String? = nil,
                endTimeTimezone: String? = nil, isNonworking: Bool = false,
                notes: String? = nil, duration: Double? = nil) {
        self.id = id
        self.userID = userID
        self.taskID = taskID
        self.startTime = startTime
        self.startTimeTimezone = startTimeTimezone
        self.endTime = endTime
        self.endTimeTimezone = endTimeTimezone
        self.isNonworking = isNonworking
        self.notes = notes
        self.duration = duration
    }
}

public struct UserStatusOverview: Decodable, Sendable, Equatable {
    public let userID: Int
    public let status: Int
    public let isRunning: Bool
    public let timeTrackingID: Int?
    public let timeTrackingStartTime: String?
    public let timeTrackingStartTimeTimezoneID: String?
    public let timeTrackingTaskID: Int?
    public let timeTrackingIsNonworking: Bool
    public let currentAbsenceIDs: String?
    public let userFullname: String?
    public let coreTimeViolation: Bool

    public var startDate: Date? {
        TimeTacTime.parse(timeTrackingStartTime, timeZone: timeTrackingStartTimeTimezoneID)
    }

    private enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case status
        case isRunning = "is_running"
        case timeTrackingID = "time_tracking_id"
        case timeTrackingStartTime = "time_tracking_start_time"
        case timeTrackingStartTimeTimezoneID = "time_tracking_start_time_timezone_id"
        case timeTrackingTaskID = "time_tracking_task_id"
        case timeTrackingIsNonworking = "time_tracking_is_nonworking"
        case currentAbsenceIDs = "current_absence_ids"
        case userFullname = "user_fullname"
        case coreTimeViolation = "core_time_violation"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = c.flexibleInt(.userID) ?? 0
        status = c.flexibleInt(.status) ?? 0
        isRunning = c.flexibleBool(.isRunning) ?? false
        timeTrackingID = c.flexibleInt(.timeTrackingID)
        timeTrackingStartTime = c.flexibleString(.timeTrackingStartTime)
        timeTrackingStartTimeTimezoneID = c.flexibleString(.timeTrackingStartTimeTimezoneID)
        timeTrackingTaskID = c.flexibleInt(.timeTrackingTaskID)
        timeTrackingIsNonworking = c.flexibleBool(.timeTrackingIsNonworking) ?? false
        currentAbsenceIDs = c.flexibleString(.currentAbsenceIDs)
        userFullname = c.flexibleString(.userFullname)
        coreTimeViolation = c.flexibleBool(.coreTimeViolation) ?? false
    }

    public init(userID: Int, status: Int, isRunning: Bool, timeTrackingID: Int? = nil,
                timeTrackingStartTime: String? = nil, timeTrackingStartTimeTimezoneID: String? = nil,
                timeTrackingTaskID: Int? = nil, timeTrackingIsNonworking: Bool = false,
                currentAbsenceIDs: String? = nil, userFullname: String? = nil,
                coreTimeViolation: Bool = false) {
        self.userID = userID
        self.status = status
        self.isRunning = isRunning
        self.timeTrackingID = timeTrackingID
        self.timeTrackingStartTime = timeTrackingStartTime
        self.timeTrackingStartTimeTimezoneID = timeTrackingStartTimeTimezoneID
        self.timeTrackingTaskID = timeTrackingTaskID
        self.timeTrackingIsNonworking = timeTrackingIsNonworking
        self.currentAbsenceIDs = currentAbsenceIDs
        self.userFullname = userFullname
        self.coreTimeViolation = coreTimeViolation
    }
}

public struct TTTask: Decodable, Sendable, Identifiable, Equatable, Hashable {
    public let id: Int
    public let name: String
    public let namePath: String?
    public let isStartable: Bool
    public let isNonworking: Bool
    public let isFavourite: Bool
    /// 1 = in progress, 2 = finished.
    public let status: Int?

    /// `Project / Sub / Task` when the server provides it, otherwise the bare name.
    public var displayPath: String {
        guard let namePath, !namePath.isEmpty else { return name }
        return namePath
    }

    /// Can this be started as ordinary work?
    public var isWorkable: Bool {
        isStartable && !isNonworking && status != 2
    }

    /// Can this be started as a break?
    public var isBreak: Bool {
        isStartable && isNonworking && status != 2
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, status
        case namePath = "name_path"
        case isStartable = "is_startable"
        case isNonworking = "is_nonworking"
        case isFavourite = "is_favourite"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleInt(.id) ?? 0
        name = c.flexibleString(.name) ?? "Untitled"
        namePath = c.flexibleString(.namePath)
        isStartable = c.flexibleBool(.isStartable) ?? true
        isNonworking = c.flexibleBool(.isNonworking) ?? false
        isFavourite = c.flexibleBool(.isFavourite) ?? false
        status = c.flexibleInt(.status)
    }

    public init(id: Int, name: String, namePath: String? = nil, isStartable: Bool = true,
                isNonworking: Bool = false, isFavourite: Bool = false, status: Int? = 1) {
        self.id = id
        self.name = name
        self.namePath = namePath
        self.isStartable = isStartable
        self.isNonworking = isNonworking
        self.isFavourite = isFavourite
        self.status = status
    }
}

/// `favouriteTasks` and `recentTasks` both return references rather than tasks: `node_id` is the
/// task id, which has to be resolved against `tasks/read`.
public struct TaskReference: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let userID: Int?
    public let nodeID: Int
    public let lastStarted: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case nodeID = "node_id"
        case lastStarted = "last_started"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleInt(.id) ?? 0
        userID = c.flexibleInt(.userID)
        nodeID = c.flexibleInt(.nodeID) ?? 0
        lastStarted = c.flexibleString(.lastStarted)
    }

    public init(id: Int, userID: Int?, nodeID: Int, lastStarted: String? = nil) {
        self.id = id
        self.userID = userID
        self.nodeID = nodeID
        self.lastStarted = lastStarted
    }
}

public struct AbsenceDay: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let userID: Int?
    public let date: String?
    public let type: String?
    public let subtype: String?
    /// 0 open · 1 granted · 2 declined · 3 cancelled.
    public let status: Int?
    public let comment: String?

    /// Only granted absences should surface as "on leave".
    public var isGranted: Bool { status == 1 }

    /// `Sick leave` from `sick_leave`.
    public var displayName: String {
        let raw = subtype ?? type ?? "Absence"
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, type, subtype, status, comment
        case userID = "user_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.flexibleInt(.id) ?? 0
        userID = c.flexibleInt(.userID)
        date = c.flexibleString(.date)
        type = c.flexibleString(.type)
        subtype = c.flexibleString(.subtype)
        status = c.flexibleInt(.status)
        comment = c.flexibleString(.comment)
    }

    public init(id: Int, userID: Int?, date: String?, type: String?, subtype: String? = nil,
                status: Int? = 1, comment: String? = nil) {
        self.id = id
        self.userID = userID
        self.date = date
        self.type = type
        self.subtype = subtype
        self.status = status
        self.comment = comment
    }
}
