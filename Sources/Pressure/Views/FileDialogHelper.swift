import AppKit
import UniformTypeIdentifiers

extension NSSavePanel {
    static func showSavePanel(
        allowedContentTypes: [String] = [],
        nameFieldStringValue: String = "Untitled"
    ) async -> URL? {
        return await withCheckedContinuation { continuation in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = nameFieldStringValue
            
            if !allowedContentTypes.isEmpty {
                panel.allowedContentTypes = allowedContentTypes.compactMap { UTType($0) }
            }
            
            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension NSOpenPanel {
    static func showOpenPanel(
        canChooseFiles: Bool = true,
        canChooseDirectories: Bool = false,
        allowsMultipleSelection: Bool = false,
        allowedContentTypes: [String] = []
    ) async -> [URL]? {
        return await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = canChooseFiles
            panel.canChooseDirectories = canChooseDirectories
            panel.allowsMultipleSelection = allowsMultipleSelection
            
            if !allowedContentTypes.isEmpty {
                panel.allowedContentTypes = allowedContentTypes.compactMap { UTType($0) }
            }
            
            panel.begin { response in
                if response == .OK {
                    continuation.resume(returning: panel.urls)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
