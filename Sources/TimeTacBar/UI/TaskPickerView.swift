import SwiftUI
import TimeTacKit

/// Inline task list: favourites and recents up top, then a searchable view of everything else.
struct TaskPickerView: View {
    @Environment(AppState.self) private var state
    @State private var searchText = ""

    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.top, 2)

            if searchText.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        section("Favourites", tasks: state.favouriteTasks)
                        section("Recent", tasks: state.recentTasks)
                        if state.favouriteTasks.isEmpty && state.recentTasks.isEmpty {
                            emptyHint("No favourites or recent tasks yet — search to find one.")
                        }
                    }
                }
                .frame(maxHeight: 220)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        if matches.isEmpty {
                            emptyHint("No task matches “\(searchText)”.")
                        } else {
                            ForEach(matches) { task in row(task) }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private var matches: [TTTask] {
        let needle = searchText.lowercased()
        return state.allTasks
            .filter { $0.isWorkable && $0.displayPath.lowercased().contains(needle) }
            .prefix(50)
            .map { $0 }
    }

    @ViewBuilder
    private func section(_ title: String, tasks: [TTTask]) -> some View {
        if !tasks.isEmpty {
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 10)
                .padding(.top, 6)
            ForEach(tasks) { task in row(task) }
        }
    }

    private func row(_ task: TTTask) -> some View {
        let isCurrent = state.snapshot.taskID == task.id && state.snapshot.status.isTracking
        return Button { onSelect(task.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: isCurrent ? "largecircle.fill.circle" : "circle")
                    .font(.caption)
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text(task.name).lineLimit(1)
                    if let namePath = task.namePath, namePath != task.name {
                        Text(namePath)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.menuRow)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}
