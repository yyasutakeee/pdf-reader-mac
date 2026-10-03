import PDFReaderFeature
import SwiftUI

struct PDFReaderHost: View {
    @StateObject private var viewStore: PDFReaderViewStore

    // WHY: this wrapper gives the reader package one stable adapter backed by the injected root store.
    init(store: Store<AppState, AppAction, AppEnvironment>) {
        _viewStore = StateObject(wrappedValue: PDFReaderViewStore(store: store))
    }

    var body: some View {
        PDFReaderView(model: viewStore)
    }
}
