import SwiftUI

@main
struct PDFReaderApp: App {
    @StateObject private var store: Store<AppState, AppAction, AppEnvironment>

    // WHY: the app lifecycle must own exactly one stable generic store for every scene it composes.
    init() {
        _store = StateObject(wrappedValue: Self.makeStore())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(store: store)
        }

        Settings {
            SettingsHost(store: store)
        }
    }

    // WHY: the application entry point is the sole owner that constructs live dependencies and the root store.
    private static func makeStore() -> Store<AppState, AppAction, AppEnvironment> {
        let environment: AppEnvironment = AppEnvironment.live()
        return Store(
            initialState: AppState(),
            reducer: AppReducer(),
            environment: environment
        )
    }
}
