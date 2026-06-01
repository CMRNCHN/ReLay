import SwiftUI
import ReLayV2

struct WorkspaceListView: View {

    @EnvironmentObject private var model: AppModel
    @State private var showingSaveSheet = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showingSaveSheet) {
            SaveWorkspaceSheet { name in
                model.captureWorkspace(name: name)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("ReLay")
                .font(.headline)
            Spacer()
            Button(action: { showingSaveSheet = true }) {
                Label("Save Current", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isCapturing)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if model.workspaces.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No saved workspaces")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Arrange your windows, then tap "Save Current".")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var list: some View {
        List {
            ForEach(model.workspaces) { workspace in
                WorkspaceRow(workspace: workspace)
                    .environmentObject(model)
            }
        }
        .listStyle(.inset)
    }
}

struct WorkspaceRow: View {

    let workspace: Workspace
    @EnvironmentObject private var model: AppModel

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workspace.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 12) {
                    Text(Self.dateFormatter.string(from: workspace.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if workspace.activationCount > 0 {
                        Label("\(workspace.activationCount)", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button("Activate") {
                model.activate(workspace)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button(role: .destructive) {
                model.delete(workspace)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
}
