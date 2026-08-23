import SwiftUI

enum SplitPreset: Int64, CaseIterable, Identifiable {
    case none = 0
    case mb100 = 104_857_600 // 100 MB
    case mb650 = 681_574_400 // 650 MB (CD)
    case gb4 = 4_294_967_296 // 4 GB (FAT32 limit)
    case gb47 = 5_046_586_573 // 4.7 GB (single-layer DVD)

    var id: Int64 { rawValue }

    var label: String {
        switch self {
        case .none: return "Do not split"
        case .mb100: return "100 MB"
        case .mb650: return "650 MB"
        case .gb4: return "4 GB"
        case .gb47: return "4.7 GB"
        }
    }
}

struct ArchiveInspectorPanel: View {
    @ObservedObject var archiveModel: ArchiveModel
    @Binding var format: CompressionFormat
    @Binding var compressionLevel: Int
    var onError: (String) -> Void

    @State private var encryptEnabled = false
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isApplyingPassword = false

    @State private var splitPreset: SplitPreset = .none
    @State private var isApplyingSplit = false

    private var stats: ArchiveStats { archiveModel.archiveStats }

    var body: some View {
        Form {
            Section {
                LabeledContent("Items", value: "\(stats.itemCount)")
                LabeledContent("Original", value: formattedByteCount(stats.originalSize))
                LabeledContent("Packed", value: formattedByteCount(stats.packedSize))
                if let saved = stats.savedPercent {
                    LabeledContent("Saved", value: String(format: "%.0f%%", saved * 100))
                }
            }

            Section("Archive") {
                Picker("Format", selection: $format) {
                    ForEach(CompressionFormat.allCases.filter { $0 != .rar }, id: \.self) { format in
                        Text(format.rawValue.uppercased()).tag(format)
                    }
                }

                if format.supportsCompressionLevel {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Compression")
                            Spacer()
                            Text(compressionLevelLabel)
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(compressionLevel) },
                                set: { compressionLevel = Int($0) }
                            ),
                            in: 0...9,
                            step: 1
                        )
                    }
                }

                encryptSection
                splitSection
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 240, idealWidth: 260)
        .onAppear { syncArchiveControlState() }
        .onChange(of: archiveModel.archiveURL) { _, _ in syncArchiveControlState() }
        .onChange(of: format) { _, newFormat in
            if newFormat != .zip, encryptEnabled {
                encryptEnabled = false
                password = ""
                confirmPassword = ""
                applyPassword(nil)
            }
        }
    }

    private var encryptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Encrypt with a password", isOn: $encryptEnabled)
                .disabled(format != .zip)
                .onChange(of: encryptEnabled) { _, newValue in
                    if !newValue {
                        password = ""
                        confirmPassword = ""
                        applyPassword(nil)
                    }
                }

            if encryptEnabled {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyPasswordIfValid)

                if !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords don't match")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button(isApplyingPassword ? "Applying…" : "Apply") { applyPasswordIfValid() }
                    .disabled(!canApplyPassword || isApplyingPassword)
            }

            Text(format == .zip
                 ? "AES-256 (WinZip AE-2) — compatible with Finder, 7-Zip, and other standard tools."
                 : "Encryption is ZIP-only — no comparable standard exists for this format.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Split", selection: $splitPreset) {
                ForEach(SplitPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .onChange(of: splitPreset) { _, newValue in applySplit(newValue) }

            if isApplyingSplit {
                Text("Splitting…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(splitCaption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var splitCaption: String {
        guard splitPreset != .none else {
            return format == .zip
                ? "ZIP disk-spanning — recognizable by other tools; reliably reopening it means rejoining the volumes with Pressure first."
                : "Generic byte-split volumes — joinable with any tool via `cat`, or by reopening with Pressure."
        }
        return format == .zip
            ? "Splitting into numbered .z01/.z02/…/.zip volumes."
            : "Splitting into numbered .001/.002/… parts."
    }

    private var canApplyPassword: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private func applyPasswordIfValid() {
        guard canApplyPassword else { return }
        applyPassword(password)
    }

    private func applyPassword(_ newPassword: String?) {
        isApplyingPassword = true
        Task {
            archiveModel.password = newPassword
            do {
                try await archiveModel.commit()
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
            await MainActor.run { isApplyingPassword = false }
        }
    }

    private func applySplit(_ preset: SplitPreset) {
        isApplyingSplit = true
        Task {
            archiveModel.splitVolumeSize = preset == .none ? nil : preset.rawValue
            do {
                try await archiveModel.commit()
            } catch {
                await MainActor.run { onError(error.localizedDescription) }
            }
            await MainActor.run { isApplyingSplit = false }
        }
    }

    private func syncArchiveControlState() {
        encryptEnabled = archiveModel.password != nil
        password = ""
        confirmPassword = ""
        splitPreset = archiveModel.splitVolumeSize.flatMap(SplitPreset.init(rawValue:)) ?? .none
    }

    private var compressionLevelLabel: String {
        switch compressionLevel {
        case 0: return "None"
        case 9: return "Maximum"
        default: return "Level \(compressionLevel)"
        }
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
