import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultFormat") private var defaultFormat: CompressionFormat = .zip
    @AppStorage("defaultCompressionLevel") private var defaultCompressionLevel: Int = 6

    var body: some View {
        Form {
            Picker("Default format", selection: $defaultFormat) {
                ForEach(CompressionFormat.allCases.filter { $0 != .rar }, id: \.self) { format in
                    Text(format.rawValue.uppercased()).tag(format)
                }
            }

            if defaultFormat == .zip {
                Stepper(value: $defaultCompressionLevel, in: 0...9) {
                    Text("Default compression level: \(defaultCompressionLevel)")
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
