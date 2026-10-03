import PDFLibraryFeature
import SwiftUI

struct PDFLibraryHost: View {
    @StateObject private var viewStore: PDFLibraryViewStore
    private let store: Store<AppState, AppAction, AppEnvironment>

    // WHY: this wrapper owns the package adapter for the lifetime of the library screen.
    init(store: Store<AppState, AppAction, AppEnvironment>) {
        self.store = store
        _viewStore = StateObject(wrappedValue: PDFLibraryViewStore(store: store))
    }

    var body: some View {
        PDFLibraryView(model: viewStore) { PDFReaderHost(store: store) }
    }
}
