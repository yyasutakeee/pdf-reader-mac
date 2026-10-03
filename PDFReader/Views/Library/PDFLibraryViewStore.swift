import Combine
import Foundation
import PDFLibraryFeature

@MainActor
final class PDFLibraryViewStore: PDFLibraryViewModel {
    @Published private(set) var items: [PDFLibraryItem] = []
    @Published private(set) var selectedItemIdentifier: UUID? = nil
    @Published private(set) var isFileImporterPresented: Bool = false

    private let store: Store<AppState, AppAction, AppEnvironment>
    private var storeSubscriptions: Set<AnyCancellable> = []

    // WHY: the adapter subscribes once so package display values always derive from completed root snapshots.
    init(store: Store<AppState, AppAction, AppEnvironment>) {
        self.store = store
        observeAppStateChanges()
        recompute(from: store.state)
    }

    // WHY: package events are translated here so the UI package never imports the app domain.
    func send(_ event: PDFLibraryEvent) {
        switch event {
        case .importButtonTapped: store.dispatch(.fileImporterPresentationRequested)
        case .fileImporterDismissed: store.dispatch(.fileImporterDismissed)
        case .pdfFileSelected(let url): store.dispatch(.pdfFileImportRequested(url))
        case .libraryItemSelected(let identifier): store.dispatch(.pdfFileSelectionChanged(identifier))
        case .libraryItemRevealRequested(let identifier): store.dispatch(.importedPDFFileRevealRequested(identifier))
        case .libraryItemRemovalRequested(let identifier): store.dispatch(.importedPDFFileRemovalRequested(identifier))
        }
    }

    // WHY: didChange supplies the post-mutation value required for an accurate display snapshot.
    private func observeAppStateChanges() {
        store.didChange
            .sink { [weak self] appState in self?.recompute(from: appState) }
            .store(in: &storeSubscriptions)
    }

    // WHY: taking AppState as input makes stale reads from the store impossible inside the subscriber.
    private func recompute(from appState: AppState) {
        items = appState.importedPDFFiles.map(makeLibraryItem)
        selectedItemIdentifier = appState.selectedPDFFileIdentifier
        isFileImporterPresented = appState.isFileImporterPresented
    }

    // WHY: the app boundary maps persistence-shaped metadata into the feature's display-shaped item.
    private func makeLibraryItem(importedPDFFile: ImportedPDFFile) -> PDFLibraryItem {
        PDFLibraryItem(
            id: importedPDFFile.identifier,
            title: importedPDFFile.displayName,
            thumbnailURL: importedPDFFile.thumbnailFileURLAbsoluteString.flatMap(URL.init(string:)),
            currentPageNumber: importedPDFFile.lastReadPageIndex + 1,
            totalPageCount: importedPDFFile.totalPageCount,
            lastReadDate: importedPDFFile.lastReadDate
        )
    }
}
