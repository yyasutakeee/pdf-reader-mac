import SwiftUI
internal import UniformTypeIdentifiers

public struct PDFLibraryView<Model: PDFLibraryViewModel, Detail: View>: View {
    @ObservedObject private var model: Model
    private let detail: () -> Detail

    public init(model: Model, @ViewBuilder detail: @escaping () -> Detail) {
        self.model = model
        self.detail = detail
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            detail()
        }
        .fileImporter(
            isPresented: fileImporterPresentation,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false,
            onCompletion: handleFileImportResult
        )
    }

    private var sidebar: some View {
        libraryContent
            .navigationTitle("Library")
            .toolbar { importToolbarItem }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if model.items.isEmpty { emptyLibraryPlaceholder } else { libraryList }
    }

    private var libraryList: some View {
        List(model.items, selection: selectedItemIdentifier) { item in
            PDFLibraryItemView(
                item: item,
                isSelected: model.selectedItemIdentifier == item.id,
                onRevealRequested: { model.send(.libraryItemRevealRequested(item.id)) },
                onDeleteRequested: { model.send(.libraryItemRemovalRequested(item.id)) }
            )
            .tag(item.id)
        }
    }

    private var selectedItemIdentifier: Binding<UUID?> {
        Binding(
            get: { model.selectedItemIdentifier },
            set: { sendAfterViewUpdate(.libraryItemSelected($0)) }
        )
    }

    // WHY: SwiftUI writes list selection during a view update, so mutating the store must wait for the next
    // main-actor turn; sending it inline publishes observable changes from inside that update.
    private func sendAfterViewUpdate(_ event: PDFLibraryEvent) {
        Task { @MainActor in model.send(event) }
    }

    private var fileImporterPresentation: Binding<Bool> {
        Binding(
            get: { model.isFileImporterPresented },
            set: { isPresented in if !isPresented { model.send(.fileImporterDismissed) } }
        )
    }

    private var importToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Import PDF", systemImage: "plus") { model.send(.importButtonTapped) }
        }
    }

    private var emptyLibraryPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No PDFs in your library")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Click + to import a PDF.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // WHY: the package translates the system picker result into user intent without knowing storage policy.
    private func handleFileImportResult(_ result: Result<[URL], any Error>) {
        guard case .success(let URLs) = result, let selectedURL: URL = URLs.first else {
            model.send(.fileImporterDismissed)
            return
        }
        model.send(.pdfFileSelected(selectedURL))
    }
}
