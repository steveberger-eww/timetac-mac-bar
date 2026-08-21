import Foundation
import Testing
@testable import TimeTacKit

/// Drives the full state machine against `MockClient` — the same path the real UI takes, minus
/// the network. This is what proves start / break / switch / clock out actually work.
@Suite("App state", .serialized)
@MainActor
struct AppStateTests {
    private func makeState(running: Bool = false) async -> AppState {
        let state = AppState(api: MockClient(startRunning: running))
        await state.start()
        return state
    }

    @Test("Comes up clocked out when nothing is running")
    func startsIdle() async {
        let state = await makeState()
        defer { state.stop() }

        #expect(state.phase == .ready)
        #expect(state.snapshot.status == .offline)
        #expect(state.snapshot.elapsed() == nil)
        #expect(state.lastError == nil)
        #expect(state.user?.id == 42)
    }

    @Test("Picks up a tracking that was already running")
    func resumesRunningTracking() async {
        let state = await makeState(running: true)
        defer { state.stop() }

        #expect(state.snapshot.status == .working)
        #expect(state.snapshot.taskName == "Development")
        let elapsed = state.snapshot.elapsed() ?? 0
        #expect(elapsed > 2 * 3600, "the seeded tracking started 2h14m ago")
    }

    @Test("Loads tasks and separates work from breaks")
    func loadsTasks() async {
        let state = await makeState()
        defer { state.stop() }

        #expect(state.allTasks.count == 8)
        #expect(state.breakTasks.map(\.name).sorted() == ["Break", "Lunch"])
        #expect(state.favouriteTasks.map(\.id) == [101, 102])
        // Recents must not repeat anything already pinned as a favourite.
        #expect(state.recentTasks.map(\.id) == [105, 103, 104])
        #expect(!state.breakTasks.contains { state.favouriteTasks.contains($0) })
    }

    @Test("Clocking in starts working")
    func clockIn() async {
        let state = await makeState()
        defer { state.stop() }

        await state.startWork(taskID: 103)
        #expect(state.snapshot.status == .working)
        #expect(state.snapshot.taskName == "Meetings")
        #expect(state.lastError == nil)
    }

    /// A break is just a tracking on a non-working task — this is the behaviour that stands in for
    /// the pause endpoint TimeTac doesn't have.
    @Test("Taking a break switches to a non-working task")
    func takeBreak() async {
        let state = await makeState(running: true)
        defer { state.stop() }

        await state.takeBreak()
        #expect(state.snapshot.status == .onBreak)
        #expect(state.snapshot.taskName == "Break")
    }

    @Test("Back to work resumes the task from before the break")
    func backToWork() async {
        let state = await makeState()
        defer { state.stop() }

        await state.startWork(taskID: 105)
        #expect(state.snapshot.taskName == "Migration")

        await state.takeBreak(taskID: 901)
        #expect(state.snapshot.status == .onBreak)
        #expect(state.snapshot.taskName == "Lunch")

        // No task id: it should remember what was running before the break rather than guessing.
        await state.startWork(taskID: nil)
        #expect(state.snapshot.status == .working)
        #expect(state.snapshot.taskName == "Migration")
    }

    @Test("Switching task keeps the clock running on the new task")
    func switchTask() async {
        let state = await makeState(running: true)
        defer { state.stop() }

        await state.switchTask(to: 104)
        #expect(state.snapshot.status == .working)
        #expect(state.snapshot.taskName == "Support")
    }

    @Test("Clocking out stops the clock and clears elapsed time")
    func clockOut() async {
        let state = await makeState(running: true)
        defer { state.stop() }

        await state.clockOut()
        #expect(state.snapshot.status == .offline)
        #expect(state.snapshot.elapsed() == nil)
        #expect(state.snapshot.taskName == nil)
    }

    @Test("Today's total accumulates across a clock-in and clock-out cycle")
    func todayTotalAccumulates() async {
        let state = await makeState(running: true)
        defer { state.stop() }

        let whileRunning = state.snapshot.todayTotal
        #expect(whileRunning > 2 * 3600)

        await state.clockOut()
        // The finished tracking still counts once the clock stops. Timestamps are stored to
        // whole seconds, so closing a running tracking can shed a fraction of a second.
        #expect(abs(state.snapshot.todayTotal - whileRunning) < 1)
    }

    @Test("Break time doesn't count towards the day's work total")
    func breakDoesNotCount() async {
        let state = await makeState()
        defer { state.stop() }

        await state.takeBreak(taskID: 900)
        #expect(state.snapshot.status == .onBreak)
        #expect(state.snapshot.todayTotal == 0, "a break shouldn't add to worked time")
    }
}
