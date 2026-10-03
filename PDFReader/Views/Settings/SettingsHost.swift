import SettingsFeature
import SwiftUI

struct SettingsHost: View {
    @StateObject private var viewStore: SettingsViewStore

    // WHY: this wrapper owns the settings adapter without creating another domain state owner.
    init(store: Store<AppState, AppAction, AppEnvironment>) {
        _viewStore = StateObject(wrappedValue: SettingsViewStore(store: store))
    }

    var body: some View {
        SettingsView(model: viewStore)
    }
}
