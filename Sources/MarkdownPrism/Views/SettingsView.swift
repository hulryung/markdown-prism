import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        TabView {
            AppearanceSettings(settings: settings)
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            FontSettings(settings: settings)
                .tabItem { Label("Fonts", systemImage: "textformat") }
        }
        .frame(width: 460)
    }
}

private struct AppearanceSettings: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Theme:", selection: $settings.appearance) {
                ForEach(AppSettings.Appearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            .pickerStyle(.inline)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
    }

    private var explanation: String {
        switch settings.appearance {
        case .system:
            return "Follows the macOS appearance, including the automatic switch at sunset."
        case .light:
            return "Stays light whatever the system is set to."
        case .dark:
            return "Stays dark whatever the system is set to."
        }
    }
}

private struct FontSettings: View {
    @ObservedObject var settings: AppSettings

    private let monospacedFamilies = NSFont.monospacedFamilyNames()
    private let proportionalFamilies = NSFont.proportionalFamilyNames()

    var body: some View {
        Form {
            Section("Editor") {
                Picker("Font:", selection: $settings.editorFontName) {
                    Text("System Monospaced").tag(AppSettings.systemFontName)
                    Divider()
                    ForEach(monospacedFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                sizeControl(value: $settings.editorFontSize)
                Text("Fixed-pitch faces only, so Markdown source keeps its columns.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                Picker("Font:", selection: $settings.previewFontName) {
                    Text("System").tag(AppSettings.systemFontName)
                    Divider()
                    ForEach(proportionalFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                sizeControl(value: $settings.previewFontSize)
                Text("Code blocks stay monospaced.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sizeControl(value: Binding<CGFloat>) -> some View {
        HStack {
            Text("Size:")
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0) }),
                in: Double(AppSettings.minimumFontSize)...Double(AppSettings.maximumFontSize),
                step: 1
            )
            Text("\(Int(value.wrappedValue)) pt")
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
        }
    }
}
