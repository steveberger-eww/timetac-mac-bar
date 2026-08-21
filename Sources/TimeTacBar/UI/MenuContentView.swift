import SwiftUI
import TimeTacKit

/// The dropdown panel.
struct MenuContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var isPickingTask = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch state.phase {
            case .setup, .signedOut:
                signedOutHeader
            case .loading:
                loadingHeader
            case .ready:
                statusHeader
            }

            if let error = state.lastError {
                Divider().padding(.vertical, 6)
                errorRow(error)
            }

            if state.phase == .ready {
                Divider().padding(.vertical, 6)
                actions
            }

            Divider().padding(.vertical, 6)
            footer
        }
        .padding(10)
        .frame(width: 300)
        .task {
            // Opening the panel is a good moment to re-sync, but don't hammer the API when it's
            // opened and closed repeatedly.
            await state.refreshIfStale()
        }
    }

    // MARK: - Headers

    private var statusHeader: some View {
        let snapshot = state.snapshot
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: snapshot.status.symbolName)
                    .foregroundStyle(snapshot.status.tint)
                Text(snapshot.status.label)
                    .fontWeight(.semibold)
                if let taskName = snapshot.taskName, snapshot.status.isTracking {
                    Text("·").foregroundStyle(.tertiary)
                    Text(taskName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if let startedAt = snapshot.startedAt, let elapsed = snapshot.elapsed(asOf: state.tick) {
                Text("Started \(DurationFormat.clock(startedAt))  ·  \(DurationFormat.long(elapsed))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 4) {
                Text("Today")
                Text(DurationFormat.long(snapshot.todayTotal)).monospacedDigit()
                if let lastUpdated = state.lastUpdated {
                    Text("·").foregroundStyle(.tertiary)
                    Text("synced \(DurationFormat.clock(lastUpdated))")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            if !snapshot.leave.isEmpty {
                leaveBanner(snapshot.leave)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func leaveBanner(_ leave: [AbsenceDay]) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "beach.umbrella.fill")
            Text("On leave today · \(leave.map(\.displayName).joined(separator: ", "))")
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.blue)
        .padding(.top, 4)
    }

    private var loadingHeader: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Checking your status…").foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var signedOutHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.phase == .setup ? "Set up TimeTacBar" : "You're signed out")
                .fontWeight(.semibold)
            Text(state.phase == .setup
                 ? "Point TimeTacBar at your company account to get started."
                 : "Sign in again to pick your tracking back up.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                openWindow(id: state.phase == .setup ? WindowID.companySetup : WindowID.login)
                activateApp()
            } label: {
                MenuRowLabel(title: state.phase == .setup ? "Set up…" : "Sign in…",
                             symbol: "person.badge.key")
            }
            .buttonStyle(.menuRow)
            .padding(.horizontal, -10)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        let status = state.snapshot.status

        if status.isTracking {
            if status == .onBreak {
                Button { Task { await state.startWork(taskID: nil) } } label: {
                    MenuRowLabel(title: "Back to work", symbol: "play.fill")
                }
                .buttonStyle(.menuRow)
            } else {
                breakButton
            }

            Button { Task { await state.clockOut() } } label: {
                MenuRowLabel(title: "Clock out", symbol: "stop.fill")
            }
            .buttonStyle(.menuRow)
        } else {
            Button { Task { await state.startWork(taskID: nil) } } label: {
                MenuRowLabel(title: "Clock in", symbol: "play.fill")
            }
            .buttonStyle(.menuRow)
        }

        Button { withAnimation(.snappy(duration: 0.15)) { isPickingTask.toggle() } } label: {
            MenuRowLabel(
                title: state.snapshot.status.isTracking ? "Switch task" : "Start a specific task",
                symbol: "arrow.left.arrow.right",
                trailing: isPickingTask ? "chevron.down" : "chevron.right"
            )
        }
        .buttonStyle(.menuRow)

        if isPickingTask {
            TaskPickerView { taskID in
                isPickingTask = false
                Task { await state.switchTask(to: taskID) }
            }
        }
    }

    /// With one break task this starts it directly; with several it offers a menu, since TimeTac
    /// accounts often separate "Break" from "Lunch".
    @ViewBuilder
    private var breakButton: some View {
        if state.breakTasks.count > 1 {
            Menu {
                ForEach(state.breakTasks) { task in
                    Button(task.name) { Task { await state.takeBreak(taskID: task.id) } }
                }
            } label: {
                MenuRowLabel(title: "Take a break", symbol: "pause.fill", trailing: "chevron.right")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        } else {
            Button { Task { await state.takeBreak() } } label: {
                MenuRowLabel(title: "Take a break", symbol: "pause.fill")
            }
            .buttonStyle(.menuRow)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button { Task { await state.refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .disabled(state.phase == .setup || state.phase == .signedOut)

            Spacer()

            Button("Settings") {
                openWindow(id: WindowID.settings)
                activateApp()
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }
}
