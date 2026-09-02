import SwiftUI

public struct SettingsView<Model: SettingsViewModel>: View {
    @ObservedObject private var model: Model

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        Form {
            appearanceSection
            pdfAnswerSection
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: selectedAppearanceIdentifier) {
                ForEach(model.appearanceOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.radioGroup)
        }
    }

    private var pdfAnswerSection: some View {
        Section("AI Answers") {
            Picker("Provider", selection: selectedPDFAnswerProviderIdentifier) {
                ForEach(model.pdfAnswerProviderOptions) { option in
                    Text(option.title).tag(option.id)
                }
            }
            if model.showsCodexExecutablePath {
                TextField("Codex executable path", text: codexExecutablePath)
                codexSetupGuide
            }
            Text("Only text extracted from the page range you choose is sent to the selected AI provider.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var codexSetupGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to find this path")
                .font(.headline)
            Text("1. Open Terminal from Applications > Utilities.")
            Text("2. Enter this command and press Return:")
            Text("which codex")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text("3. Copy the result and paste it above. It should look like:")
            Text("/opt/homebrew/bin/codex")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text("If nothing is shown, install Codex CLI first. On first use, run codex login in Terminal.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private var selectedAppearanceIdentifier: Binding<String> {
        Binding(
            get: { model.selectedAppearanceIdentifier },
            set: { model.send(.appearanceSelected($0)) }
        )
    }

    private var selectedPDFAnswerProviderIdentifier: Binding<String> {
        Binding(
            get: { model.selectedPDFAnswerProviderIdentifier },
            set: { model.send(.pdfAnswerProviderSelected($0)) }
        )
    }

    private var codexExecutablePath: Binding<String> {
        Binding(
            get: { model.codexExecutablePath },
            set: { model.send(.codexExecutablePathChanged($0)) }
        )
    }
}
