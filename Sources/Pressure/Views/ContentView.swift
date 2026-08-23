import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var compressionManager = CompressionManager()
    @StateObject private var archiveModel: ArchiveModel
    @State private var selectedFiles: [URL] = []
    @State private var selectedArchiveItems: Set<String> = []
    @State private var leftPaneCollapsed = false
    @State private var showSaveDialog = false
    @State private var selectedFormat: CompressionFormat = .zip
    @State private var compressionLevel: Int = 6
    @State private var isCompressing = false
    @State private var compressionProgress: Double = 0.0
    @State private var statusMessage = ""
    @State private var draggedFiles: [URL] = []
    
    init() {
        let manager = CompressionManager()
        _compressionManager = StateObject(wrappedValue: manager)
        _archiveModel = StateObject(wrappedValue: ArchiveModel(compressionManager: manager))
    }
    
    var body: some View {
        HSplitView {
            // Left pane - File System Navigator
            if !leftPaneCollapsed {
                FileSystemNavigator(selectedFiles: $selectedFiles)
                    .frame(minWidth: 200, idealWidth: 300)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: { leftPaneCollapsed.toggle() }) {
                                Image(systemName: "sidebar.left")
                            }
                        }
                    }
            }
            
            // Right pane - Archive Navigator
            VStack(spacing: 0) {
                ArchiveNavigator(
                    archiveModel: archiveModel,
                    selectedArchiveItems: $selectedArchiveItems
                )
                
                // Bottom toolbar
                HStack {
                    if !leftPaneCollapsed {
                        Button(action: { leftPaneCollapsed.toggle() }) {
                            Image(systemName: "sidebar.left")
                        }
                    } else {
                        Button(action: { leftPaneCollapsed.toggle() }) {
                            Image(systemName: "sidebar.right")
                        }
                    }
                    
                    Button("Open Archive") {
                        openArchive()
                    }
                    .disabled(isCompressing)
                    
                    Spacer()
                    
                    Button("Add Files") {
                        addFilesToArchive()
                    }
                    .disabled(isCompressing)
                    
                    Button("Save") {
                        if archiveModel.archiveURL != nil {
                            saveArchive()
                        } else {
                            showSaveDialog = true
                        }
                    }
                    .disabled(isCompressing || archiveModel.items.isEmpty)
                    
                    Button("Save As...") {
                        showSaveDialog = true
                    }
                    .disabled(isCompressing)
                    
                    if isCompressing {
                        ProgressView(value: compressionProgress, total: 1.0)
                            .frame(width: 100)
                    }
                }
                .padding()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            return handleDropSync(providers: providers)
        }
        .sheet(isPresented: $showSaveDialog) {
            SaveDialog(
                isPresented: $showSaveDialog,
                selectedFormat: $selectedFormat,
                compressionLevel: $compressionLevel
            ) { url, format, level in
                Task {
                    await saveArchiveAs(to: url, format: format, level: level)
                }
            }
        }
        .alert("Status", isPresented: .constant(!statusMessage.isEmpty)) {
            Button("OK") {
                statusMessage = ""
            }
        } message: {
            Text(statusMessage)
        }
    }
    
    private func addFilesToArchive() {
        Task {
            guard let fileURLs = await NSOpenPanel.showOpenPanel(
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: true,
                allowedContentTypes: [UTType.item.identifier]
            ) else {
                return
            }
            
            await MainActor.run {
                for url in fileURLs {
                    archiveModel.addFileToArchive(url, at: archiveModel.currentPath)
                }
            }
        }
    }
    
    private func handleDropSync(providers: [NSItemProvider]) -> Bool {
        var hasValidFiles = false
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                hasValidFiles = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    
                    Task { @MainActor in
                        archiveModel.addFileToArchive(url, at: archiveModel.currentPath)
                    }
                }
            }
        }
        
        return hasValidFiles
    }
    
    private func saveArchive() {
        guard let archiveURL = archiveModel.archiveURL else {
            showSaveDialog = true
            return
        }
        
        Task {
            await saveArchiveAs(to: archiveURL, format: selectedFormat, level: compressionLevel)
        }
    }
    
    private func saveArchiveAs(to url: URL, format: CompressionFormat, level: Int) async {
        isCompressing = true
        compressionProgress = 0.0
        statusMessage = ""
        
        do {
            // Get files from archive model
            let filesToCompress = archiveModel.getFilesForCompression()
            
            if !filesToCompress.isEmpty {
                let outputURL = try await compressionManager.compress(
                    files: filesToCompress,
                    to: url,
                    format: format,
                    compressionLevel: format == .zip ? level : nil,
                    progress: { progress in
                        await MainActor.run {
                            compressionProgress = progress
                        }
                    }
                )
                
                await MainActor.run {
                    isCompressing = false
                    compressionProgress = 1.0
                    statusMessage = "Successfully saved to \(outputURL.lastPathComponent)"
                    archiveModel.archiveURL = outputURL
                }
            } else {
                await MainActor.run {
                    isCompressing = false
                    statusMessage = "No files to compress"
                }
            }
        } catch {
            await MainActor.run {
                isCompressing = false
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    private func openArchive() {
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
                await MainActor.run {
                    statusMessage = "Archive opened: \(fileURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    statusMessage = "Error opening archive: \(error.localizedDescription)"
                }
            }
        }
    }
}
