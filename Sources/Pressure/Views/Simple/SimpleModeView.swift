import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SimpleModeView: View {
    @ObservedObject var compressionManager: CompressionManager
    @AppStorage("defaultFormat") private var format: CompressionFormat = .zip

    @State private var selectedFiles: [URL] = []
    @State private var isDropTargeted = false
    @State private var isCompressing = false
    @State private var compressionProgress: Double = 0.0
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            dropZone

            HStack {
                Picker("", selection: $format) {
                    ForEach(CompressionFormat.allCases.filter { $0 != .rar }, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 100)

                Spacer()

                Button("or choose files...") {
                    chooseFiles()
                }
                .buttonStyle(.link)
            }
            .frame(maxWidth: 420)

            if !selectedFiles.isEmpty {
                Button(isCompressing ? "Saving…" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isCompressing)

                if isCompressing {
                    ProgressView(value: compressionProgress, total: 1.0)
                        .frame(width: 200)
                }
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Status", isPresented: .constant(!statusMessage.isEmpty)) {
            Button("OK") { statusMessage = "" }
        } message: {
            Text(statusMessage)
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
            .foregroundColor(isDropTargeted ? .accentColor : Color(NSColor.tertiaryLabelColor))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .frame(maxWidth: 420, minHeight: 220)
            .overlay(dropZoneContent)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
    }

    private var dropZoneContent: some View {
        VStack(spacing: 8) {
            Image(systemName: selectedFiles.isEmpty ? "arrow.down.doc" : "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            if selectedFiles.isEmpty {
                Text("Drop files here")
                    .font(.headline)
            } else {
                Text("\(selectedFiles.count) item\(selectedFiles.count == 1 ? "" : "s") selected")
                    .font(.headline)
                Text(selectedFiles.map(\.lastPathComponent).joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
    }

    private func chooseFiles() {
        Task {
            guard let fileURLs = await NSOpenPanel.showOpenPanel(
                canChooseFiles: true,
                canChooseDirectories: true,
                allowsMultipleSelection: true,
                allowedContentTypes: [UTType.item.identifier]
            ) else {
                return
            }

            await MainActor.run {
                selectedFiles.append(contentsOf: fileURLs)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var hasValidFiles = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                hasValidFiles = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }

                    Task { @MainActor in
                        selectedFiles.append(url)
                    }
                }
            }
        }

        return hasValidFiles
    }

    private func save() {
        Task {
            guard let outputURL = await NSSavePanel.showSavePanel(
                allowedContentTypes: [format.fileType.identifier],
                nameFieldStringValue: "Archive.\(format.rawValue)"
            ) else {
                return
            }

            isCompressing = true
            compressionProgress = 0.0

            do {
                _ = try await compressionManager.compress(
                    files: selectedFiles,
                    to: outputURL,
                    format: format,
                    progress: { progress in
                        await MainActor.run {
                            compressionProgress = progress
                        }
                    }
                )

                await MainActor.run {
                    isCompressing = false
                    selectedFiles = []
                    statusMessage = "Saved \(outputURL.lastPathComponent)"
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
