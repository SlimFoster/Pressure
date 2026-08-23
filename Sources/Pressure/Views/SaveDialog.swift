import SwiftUI
import AppKit

struct SaveDialog: View {
    @Binding var isPresented: Bool
    @Binding var selectedFormat: CompressionFormat
    @Binding var compressionLevel: Int
    var onSave: (URL, CompressionFormat, Int) -> Void
    
    @State private var saveURL: URL?
    @State private var showFilePicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save Archive")
                .font(.title2)
                .fontWeight(.bold)
            
            // Format selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Compression Format:")
                    .font(.headline)
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(CompressionFormat.allCases.filter { $0 != .rar }, id: \.self) { format in
                        Text(format.rawValue.uppercased())
                            .tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Compression level (for formats that support it)
            if selectedFormat == .zip {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Compression Level:")
                        .font(.headline)
                    
                    HStack {
                        Text("None")
                        Slider(value: Binding(
                            get: { Double(compressionLevel) },
                            set: { compressionLevel = Int($0) }
                        ), in: 0...9, step: 1)
                        Text("Maximum")
                    }
                    
                    Text("Level \(compressionLevel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // File location
            VStack(alignment: .leading, spacing: 10) {
                Text("Location:")
                    .font(.headline)
                
                HStack {
                    TextField("", text: .constant(saveURL?.path ?? "Choose location..."))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    
                    Button("Choose...") {
                        showFilePicker = true
                    }
                }
            }
            
            // Buttons
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save") {
                    if let url = saveURL {
                        onSave(url, selectedFormat, compressionLevel)
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(saveURL == nil)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onChange(of: showFilePicker) { isShowing in
            if isShowing {
                Task {
                    if let url = await NSSavePanel.showSavePanel(
                        allowedContentTypes: [selectedFormat.fileType.identifier],
                        nameFieldStringValue: "archive.\(selectedFormat.rawValue)"
                    ) {
                        await MainActor.run {
                            saveURL = url
                            showFilePicker = false
                        }
                    } else {
                        await MainActor.run {
                            showFilePicker = false
                        }
                    }
                }
            }
        }
    }
}

extension CompressionFormat {
    var supportsCompressionLevel: Bool {
        switch self {
        case .zip:
            return true
        default:
            return false
        }
    }
}

