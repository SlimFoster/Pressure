import SwiftUI

struct ModeToggleBar: View {
    @AppStorage("appMode") private var appMode: AppMode = .power
    @AppStorage("colorSchemeOverride") private var colorSchemeOverride: ColorSchemeOverride = .system
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Spacer()

            Picker("", selection: $appMode) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
            .labelsHidden()

            Button(action: { colorSchemeOverride = colorSchemeOverride.next }) {
                Image(systemName: colorSchemeOverride.iconName)
            }
            .buttonStyle(.borderless)
            .help("Appearance: \(colorSchemeOverride.rawValue.capitalized)")

            Button(action: { openSettings() }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
