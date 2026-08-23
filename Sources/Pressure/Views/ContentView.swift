import SwiftUI

struct ContentView: View {
    @StateObject private var compressionManager = CompressionManager()
    @StateObject private var archiveModel: ArchiveModel

    @AppStorage("appMode") private var appMode: AppMode = .power
    @AppStorage("colorSchemeOverride") private var colorSchemeOverride: ColorSchemeOverride = .system

    init() {
        let manager = CompressionManager()
        _compressionManager = StateObject(wrappedValue: manager)
        _archiveModel = StateObject(wrappedValue: ArchiveModel(compressionManager: manager))
    }

    var body: some View {
        VStack(spacing: 0) {
            ModeToggleBar()

            switch appMode {
            case .simple:
                SimpleModeView(compressionManager: compressionManager)
            case .power:
                PowerModeView(compressionManager: compressionManager, archiveModel: archiveModel)
            }
        }
        .preferredColorScheme(colorSchemeOverride.colorScheme)
    }
}
