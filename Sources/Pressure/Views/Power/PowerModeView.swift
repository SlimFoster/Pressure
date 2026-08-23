import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct PowerModeView: View {
    @ObservedObject var compressionManager: CompressionManager
    @ObservedObject var archiveModel: ArchiveModel

    @State private var selectedItems: Set<String> = []
    @State private var searchText = ""
    @State private var showInspector = true
    @State private var format: CompressionFormat = .zip
    @State private var compressionLevel: Int = 6
    @State private var errorMessage = ""
    @State private var showPasswordPrompt = false
    @State private var pendingUnlockURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            PowerToolbar(
                archiveModel: archiveModel,
                selectedItems: $selectedItems,
                searchText: $searchText,
                onAddFiles: { urls in Task { await handleDroppedFiles(urls) } },
                onError: { errorMessage = $0 }
            )
            Divider()

            if archiveModel.archiveURL == nil && archiveModel.items.isEmpty {
                emptyState
            } else {
                HSplitView {
                    ArchiveSidebarView(
                        archiveName: archiveDisplayName,
                        items: archiveModel.items,
                        selectedPath: Binding(
                            get: { archiveModel.currentPath },
                            set: { archiveModel.navigateToPath($0) }
                        )
                    )
                    .frame(minWidth: 160, idealWidth: 200, maxWidth: 280)

                    ArchiveContentsTable(
                        archiveModel: archiveModel,
                        selectedItems: $selectedItems,
                        searchText: $searchText,
                        onDropFiles: { urls in Task { await handleDroppedFiles(urls) } }
                    )
                    .frame(minWidth: 400)
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            ArchiveInspectorPanel(
                archiveModel: archiveModel,
                format: $format,
                compressionLevel: $compressionLevel,
                onError: { errorMessage = $0 }
            )
        }
        .sheet(isPresented: $showPasswordPrompt) {
            PasswordPromptSheet(isPresented: $showPasswordPrompt) { enteredPassword in
                guard let url = pendingUnlockURL else { return false }
                do {
                    try await archiveModel.loadArchive(from: url, password: enteredPassword)
                    return true
                } catch CompressionError.incorrectPassword {
                    return false
                } catch {
                    await MainActor.run { errorMessage = error.localizedDescription }
                    return true // dismiss the prompt; the real error is shown via the alert
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showInspector.toggle() }) {
                    Image(systemName: "sidebar.right")
                }
            }
        }
        .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK") { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: archiveModel.archiveURL) { _, newURL in
            if let newURL {
                format = compressionManager.detectFormat(from: newURL)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(archiveDisplayName)
                .font(.headline)
            Text(subtitleText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var archiveDisplayName: String {
        archiveModel.archiveURL?.lastPathComponent ?? "New Archive"
    }

    private var subtitleText: String {
        let stats = archiveModel.archiveStats
        guard stats.itemCount > 0 else { return "No items" }
        let itemsPart = "\(stats.itemCount) item\(stats.itemCount == 1 ? "" : "s")"
        let packedPart = "\(formattedByteCount(stats.packedSize)) packed"
        let originalPart = "\(formattedByteCount(stats.originalSize)) original"
        return [itemsPart, packedPart, originalPart].joined(separator: " · ")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No archive open")
                .font(.headline)
            HStack(spacing: 12) {
                Button("Open Archive…") { openExistingArchive() }
                Button("New Archive…") { Task { await ensureArchiveExists() } }
            }
            Text("or drop files here to start a new one")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDropProviders(providers)
        }
    }

    private func openExistingArchive() {
        Task {
            guard let fileURLs = await NSOpenPanel.showOpenPanel(
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: false,
                allowedContentTypes: CompressionFormat.allCases.filter { $0 != .rar }.map { $0.fileType.identifier }
            ), let fileURL = fileURLs.first else {
                return
            }

            do {
                try await archiveModel.loadArchive(from: fileURL)
            } catch CompressionError.incorrectPassword {
                await MainActor.run {
                    pendingUnlockURL = fileURL
                    showPasswordPrompt = true
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    @MainActor
    private func ensureArchiveExists() async {
        guard archiveModel.archiveURL == nil else { return }
        guard let url = await NSSavePanel.showSavePanel(
            allowedContentTypes: [format.fileType.identifier],
            nameFieldStringValue: "Archive.\(format.rawValue)"
        ) else {
            return
        }
        archiveModel.archiveURL = url
    }

    private func handleDropProviders(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            await handleDroppedFiles(urls)
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    private func handleDroppedFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        await ensureArchiveExists()
        guard archiveModel.archiveURL != nil else { return } // user cancelled the save panel

        for url in urls {
            archiveModel.addFileToArchive(url, at: archiveModel.currentPath)
        }

        do {
            try await archiveModel.commit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
