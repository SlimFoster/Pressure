import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var compressionManager = CompressionManager()
    @State private var selectedFiles: [URL] = []
    @State private var selectedFormat: CompressionFormat = .zip
    @State private var isCompressing = false
    @State private var compressionProgress: Double = 0.0
    @State private var showFilePicker = false
    @State private var statusMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Text("Pressure")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)
            
            // File selection area
            VStack(alignment: .leading, spacing: 10) {
                Text("Selected Files:")
                    .font(.headline)
                
                if selectedFiles.isEmpty {
                    Text("No files selected")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(selectedFiles, id: \.self) { file in
                                HStack {
                                    Image(systemName: "doc")
                                    Text(file.lastPathComponent)
                                        .lineLimit(1)
                                    Spacer()
                                    Button(action: {
                                        selectedFiles.removeAll { $0 == file }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                        .padding()
                    }
                    .frame(maxHeight: 200)
                }
                
                Button(action: {
                    showFilePicker = true
                }) {
                    Label("Select Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Format selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Compression Format:")
                    .font(.headline)
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(CompressionFormat.allCases, id: \.self) { format in
                        Text(format.rawValue.uppercased())
                            .tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            
            // Progress indicator
            if isCompressing {
                VStack(spacing: 10) {
                    ProgressView(value: compressionProgress, total: 1.0)
                    Text("Compressing... \(Int(compressionProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            
            // Status message
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundColor(statusMessage.contains("Error") ? .red : .green)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(statusMessage.contains("Error") ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Action buttons
            HStack(spacing: 20) {
                Button(action: compressFiles) {
                    Label("Compress", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFiles.isEmpty || isCompressing)
                
                Button(action: decompressFile) {
                    Label("Decompress", systemImage: "arrow.up.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isCompressing)
            }
            .padding()
        }
        .padding()
        .frame(minWidth: 600, minHeight: 500)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                selectedFiles.append(contentsOf: urls)
            case .failure(let error):
                statusMessage = "Error selecting files: \(error.localizedDescription)"
            }
        }
    }
    
    private func compressFiles() {
        guard !selectedFiles.isEmpty else { return }
        
        isCompressing = true
        compressionProgress = 0.0
        statusMessage = ""
        
        Task {
            do {
                if let saveURL = await NSSavePanel.showSavePanel(
                    allowedContentTypes: [selectedFormat.fileType.identifier],
                    nameFieldStringValue: "archive.\(selectedFormat.rawValue)"
                ) {
                    let outputURL = try await compressionManager.compress(
                        files: selectedFiles,
                        to: saveURL,
                        format: selectedFormat,
                        progress: { progress in
                            await MainActor.run {
                                compressionProgress = progress
                            }
                        }
                    )
                    
                    await MainActor.run {
                        isCompressing = false
                        compressionProgress = 1.0
                        statusMessage = "Successfully compressed to \(outputURL.lastPathComponent)"
                        selectedFiles.removeAll()
                    }
                } else {
                    await MainActor.run {
                        isCompressing = false
                    }
                }
            } catch {
                await MainActor.run {
                    isCompressing = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func decompressFile() {
        Task {
            guard let fileURLs = await NSOpenPanel.showOpenPanel(
                canChooseFiles: true,
                canChooseDirectories: false,
                allowsMultipleSelection: false,
                allowedContentTypes: CompressionFormat.allCases.map { $0.fileType.identifier }
            ), let fileURL = fileURLs.first else {
                return
            }
            
            await MainActor.run {
                isCompressing = true
                compressionProgress = 0.0
                statusMessage = ""
            }
            
            do {
                guard let outputDirs = await NSOpenPanel.showOpenPanel(
                    canChooseFiles: false,
                    canChooseDirectories: true,
                    allowsMultipleSelection: false
                ), let outputDir = outputDirs.first else {
                    await MainActor.run {
                        isCompressing = false
                    }
                    return
                }
                
                let extractedFiles = try await compressionManager.decompress(
                    file: fileURL,
                    to: outputDir,
                    progress: { progress in
                        await MainActor.run {
                            compressionProgress = progress
                        }
                    }
                )
                
                await MainActor.run {
                    isCompressing = false
                    compressionProgress = 1.0
                    statusMessage = "Successfully extracted \(extractedFiles.count) file(s)"
                }
            } catch {
                await MainActor.run {
                    isCompressing = false
                    statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
