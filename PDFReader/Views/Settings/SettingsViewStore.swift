import Combine
import SettingsFeature

@MainActor
final class SettingsViewStore: SettingsViewModel {
    @Published private(set) var appearanceOptions: [AppearanceOption] = []
    @Published private(set) var selectedAppearanceIdentifier: String = AppearanceTheme.system.rawValue
    @Published private(set) var pdfAnswerProviderOptions: [PDFAnswerProviderOptionData] = []
    @Published private(set) var selectedPDFAnswerProviderIdentifier: String = PDFAnswerProvider.appleIntelligence.rawValue
    @Published private(set) var codexExecutablePath: String = ""
    @Published private(set) var showsCodexExecutablePath: Bool = false

    private let store: Store<AppState, AppAction, AppEnvironment>
    private var storeSubscriptions: Set<AnyCancellable> = []

    // WHY: the adapter derives all settings display values from one completed root-state snapshot.
    init(store: Store<AppState, AppAction, AppEnvironment>) {
        self.store = store
        observeAppStateChanges()
        recompute(from: store.state)
    }

    // WHY: the settings package sends a string identifier so it never imports the domain preference type.
    func send(_ event: SettingsEvent) {
        switch event {
        case .appearanceSelected(let identifier): selectAppearanceTheme(identifier: identifier)
        case .pdfAnswerProviderSelected(let identifier): selectPDFAnswerProvider(identifier: identifier)
        case .codexExecutablePathChanged(let executablePath): store.dispatch(.codexExecutablePathChanged(executablePath))
        }
    }

    // WHY: didChange carries the selected post-mutation preference without a stale store read.
    private func observeAppStateChanges() {
        store.didChange
            .sink { [weak self] appState in self?.recompute(from: appState) }
            .store(in: &storeSubscriptions)
    }

    // WHY: the state parameter fixes every displayed setting to the same app-state snapshot.
    private func recompute(from appState: AppState) {
        appearanceOptions = AppearanceTheme.allCases.map(makeAppearanceOption)
        selectedAppearanceIdentifier = appState.appearanceTheme.rawValue
        pdfAnswerProviderOptions = PDFAnswerProvider.allCases.map(makePDFAnswerProviderOptionData)
        selectedPDFAnswerProviderIdentifier = appState.pdfAnswerProvider.rawValue
        codexExecutablePath = appState.codexExecutablePath
        showsCodexExecutablePath = appState.pdfAnswerProvider == .localCodex
    }

    // WHY: domain choices become primitive package values only at the app boundary.
    private func makeAppearanceOption(appearanceTheme: AppearanceTheme) -> AppearanceOption {
        AppearanceOption(id: appearanceTheme.rawValue, title: appearanceTheme.label)
    }

    // WHY: invalid identifiers from UI state are ignored instead of corrupting the persisted preference.
    private func selectAppearanceTheme(identifier: String) {
        guard let appearanceTheme: AppearanceTheme = AppearanceTheme(rawValue: identifier) else { return }
        store.dispatch(.appearanceSelected(appearanceTheme))
    }

    // WHY: domain provider values are converted into package-owned display data at the app boundary.
    private func makePDFAnswerProviderOptionData(provider: PDFAnswerProvider) -> PDFAnswerProviderOptionData {
        PDFAnswerProviderOptionData(id: provider.rawValue, title: makePDFAnswerProviderTitle(provider))
    }

    // WHY: provider names are presentation copy and therefore remain outside the domain model.
    private func makePDFAnswerProviderTitle(_ provider: PDFAnswerProvider) -> String {
        switch provider {
        case .appleIntelligence: return "Apple Intelligence (On-Device)"
        case .localCodex: return "Codex Subscription (Local CLI)"
        }
    }

    // WHY: invalid package identifiers are rejected before they can become persisted domain state.
    private func selectPDFAnswerProvider(identifier: String) {
        guard let provider: PDFAnswerProvider = PDFAnswerProvider(rawValue: identifier) else { return }
        store.dispatch(.pdfAnswerProviderSelected(provider))
    }
}
