import SwiftUI

struct AppRootView: View {
    @ObservedObject var store: Store<AppState, AppAction, AppEnvironment>

    var body: some View {
        PDFLibraryHost(store: store)
            .preferredColorScheme(makeColorScheme(appearanceTheme: store.state.appearanceTheme))
            .task { store.dispatch(.appStarted) }
    }

    // WHY: SwiftUI's ColorScheme remains in the view layer instead of leaking into domain state.
    private func makeColorScheme(appearanceTheme: AppearanceTheme) -> ColorScheme? {
        switch appearanceTheme {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
