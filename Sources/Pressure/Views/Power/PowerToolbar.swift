import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PowerToolbar: View {
    @ObservedObject var archiveModel: ArchiveModel
    @Binding var selectedItems: Set<String>
    @Binding var searchText: String
    var onAddFiles: ([URL]) -> Void
    var onError: (String) -> Void

    @State private var showRenameSheet = false
    @State private var renameText = ""

    var body: some View {
        HStack(spacing: 12) {
            Button {
                extractAll()
            } label: {
                Label("Extract All", systemImage: "arrow.down.doc")
            }
            .disabled(archiveModel.items.isEmpty)

            Button {
                addFiles()
            } label: {
                Label("Add Files", systemImage: "plus")
            }

            Button(role: .destructive) {
                deleteSelected()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selectedItems.isEmpty)

            Button {
                beginRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .disabled(selectedItems.count != 1)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search archive", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 220)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .sheet(isPresented: $showRenameSheet) {
            renameSheet
        }
    }

    private var renameSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename")
                .font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit { commitRename() }

            HStack {
                Spacer()
                Button("Cancel") { showRenameSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") { commitRename() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func extractAll() {
        Task {
            guard let destination = await NSOpenPanel.showOpenPanel(
                canChooseFiles: false,
                canChooseDirectories: true,
                allowsMultipleSelection: false
            )?.first else {
                return
            }

            do {
                try await archiveModel.extractAll(to: destination)
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }

    private func addFiles() {
        Task {
            guard let fileURLs = await NSOpenPanel.showOpenPanel(
                canChooseFiles: true,
                canChooseDirectories: true,
                allowsMultipleSelection: true,
                allowedContentTypes: [UTType.item.identifier]
            ) else {
                return
            }
            onAddFiles(fileURLs)
        }
    }

    private func deleteSelected() {
        let paths = selectedItems
        Task {
            do {
                try await archiveModel.deleteItems(paths: paths)
                await MainActor.run { selectedItems.removeAll() }
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }

    private func beginRename() {
        guard let path = selectedItems.first,
              let item = archiveModel.currentItems.first(where: { $0.path == path }) ?? archiveModel.items.first(where: { $0.path == path }) else {
            return
        }
        renameText = item.name
        showRenameSheet = true
    }

    private func commitRename() {
        guard let path = selectedItems.first else {
            showRenameSheet = false
            return
        }
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        showRenameSheet = false

        Task {
            do {
                try await archiveModel.renameItem(path: path, to: newName)
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
        }
    }
}
