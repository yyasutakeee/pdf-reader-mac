import Combine
import Foundation
import PDFReaderFeature

@MainActor
final class PDFReaderViewStore: PDFReaderViewModel {
    @Published private(set) var documentURL: URL? = nil
    @Published private(set) var isDocumentFileMissing: Bool = false
    @Published private(set) var initialPosition: PDFReaderPosition? = nil
    @Published private(set) var isNightModeEnabled: Bool = false
    @Published private(set) var isAllHighlightsRemovalPending: Bool = false
    @Published private(set) var currentPageIndex: Int? = nil
    @Published private(set) var bookmarks: [PDFBookmarkItem] = []
    @Published private(set) var isCurrentPageBookmarked: Bool = false
    @Published private(set) var bookmarkNavigationPageIndex: Int? = nil
    @Published private(set) var totalPageCount: Int = 0
    @Published private(set) var assistantMessages: [PDFAssistantMessage] = []
    @Published private(set) var assistantAvailability: PDFAssistantAvailability = .unavailable(title: "AI Unavailable", description: "Try again later.")
    @Published private(set) var isAssistantGenerating: Bool = false
    @Published private(set) var assistantStatusDescription: String? = nil

    private let appStore: AppStore
    private var storeSubscriptions: Set<AnyCancellable> = []
    private var selectedPDFFileIdentifier: UUID? = nil

    init(appStore: AppStore) {
        self.appStore = appStore
        observeAppStateChanges()
        recompute(from: appStore.state)
    }

    // WHY: reader gestures become domain actions only at the app-owned package boundary.
    func send(_ event: PDFReaderEvent) {
        switch event {
        case .nightModeToggled: appStore.toggleNightMode()
        case .allHighlightsRemovalRequested: appStore.requestAllHighlightsRemoval()
        case .allHighlightsRemovalHandled: appStore.finishAllHighlightsRemoval()
        case .currentPageChanged(let pageIndex): setCurrentPageIndex(pageIndex)
        case .currentPageBookmarkToggled: toggleCurrentPageBookmark()
        case .bookmarkSelected(let pageIndex): setBookmarkNavigationPageIndex(pageIndex)
        case .bookmarkRemoved(let pageIndex): appStore.removeBookmark(pageIndex: pageIndex)
        case .bookmarkCommentChanged(let pageIndex, let comment): appStore.updateBookmarkComment(pageIndex: pageIndex, comment: comment)
        case .bookmarkNavigationHandled: setBookmarkNavigationPageIndex(nil)
        case .positionChanged(let position): appStore.saveReadingPosition(makeDomainPosition(position))
        case .assistantSummaryRequested(let startPageNumber, let endPageNumber): requestAssistantSummary(startPageNumber: startPageNumber, endPageNumber: endPageNumber)
        case .assistantQuestionSubmitted(let question, let startPageNumber, let endPageNumber, let usesSelectedPages): submitAssistantQuestion(question, startPageNumber: startPageNumber, endPageNumber: endPageNumber, usesSelectedPages: usesSelectedPages)
        case .assistantRetryRequested: appStore.retryPDFInquiry()
        case .assistantGenerationCancelled: appStore.cancelPDFInquiry()
        case .assistantAvailabilityRefreshRequested: appStore.refreshPDFInquiryAvailability()
        case .assistantReferenceSelected(let pageNumber): setBookmarkNavigationPageIndex(pageNumber - 1)
        }
    }

    // WHY: didChange supplies the post-mutation state needed by this manual Combine bridge.
    private func observeAppStateChanges() {
        appStore.didChange
            .sink { [weak self] appState in self?.recompute(from: appState) }
            .store(in: &storeSubscriptions)
    }

    // WHY: the state parameter prevents the subscriber from reading a different app-state moment.
    private func recompute(from appState: AppState) {
        documentURL = appState.selectedPDFFileURL
        isDocumentFileMissing = appState.isSelectedPDFFileMissing
        initialPosition = makeReaderPosition(appState: appState)
        isNightModeEnabled = appState.isNightModeEnabled
        isAllHighlightsRemovalPending = appState.isAllHighlightsRemovalPending
        updateSelectedPDFFile(appState: appState)
        bookmarks = makeBookmarkItems(appState: appState)
        isCurrentPageBookmarked = calculateIsCurrentPageBookmarked(bookmarks: bookmarks, currentPageIndex: currentPageIndex)
        totalPageCount = findSelectedPDFFile(appState: appState)?.totalPageCount ?? 0
        assistantMessages = appState.pdfInquiryEntries.map(makeAssistantMessage)
        assistantAvailability = makeAssistantAvailability(appState.pdfInquiryAvailability)
        isAssistantGenerating = makeIsAssistantGenerating(appState.pdfInquiryPhase)
        assistantStatusDescription = makeAssistantStatusDescription(appState.pdfInquiryPhase)
    }

    // WHY: switching documents resets page-local presentation state before new PDFKit callbacks arrive.
    private func updateSelectedPDFFile(appState: AppState) {
        guard selectedPDFFileIdentifier != appState.selectedPDFFileIdentifier else { return }
        selectedPDFFileIdentifier = appState.selectedPDFFileIdentifier
        currentPageIndex = makeSelectedPageIndex(appState: appState)
        bookmarkNavigationPageIndex = nil
    }

    // WHY: immediate page publication keeps toolbar status synchronized while position persistence remains debounced.
    private func setCurrentPageIndex(_ pageIndex: Int) {
        currentPageIndex = pageIndex
        isCurrentPageBookmarked = calculateIsCurrentPageBookmarked(bookmarks: bookmarks, currentPageIndex: pageIndex)
    }

    // WHY: the package navigation request is retained only until PDFKit acknowledges handling it.
    private func setBookmarkNavigationPageIndex(_ pageIndex: Int?) {
        bookmarkNavigationPageIndex = pageIndex
    }

    // WHY: the current page is required before bookmark intent can be forwarded to persistent domain state.
    private func toggleCurrentPageBookmark() {
        guard let currentPageIndex else { return }
        appStore.toggleBookmark(pageIndex: currentPageIndex)
    }

    // WHY: the selected document's persisted pages become display-only inspector rows at the app boundary.
    private func makeBookmarkItems(appState: AppState) -> [PDFBookmarkItem] {
        guard let importedPDFFile: ImportedPDFFile = findSelectedPDFFile(appState: appState) else { return [] }
        return importedPDFFile.bookmarks
            .filter { $0.pageIndex >= 0 }
            .sorted { $0.pageIndex < $1.pageIndex }
            .map { PDFBookmarkItem(pageIndex: $0.pageIndex, comment: $0.comment) }
    }

    // WHY: bookmark fill state is derived from the same rows shown by the inspector.
    private func calculateIsCurrentPageBookmarked(bookmarks: [PDFBookmarkItem], currentPageIndex: Int?) -> Bool {
        guard let currentPageIndex else { return false }
        return bookmarks.contains { $0.pageIndex == currentPageIndex }
    }

    // WHY: initial toolbar state uses the saved page until PDFKit reports its actual destination.
    private func makeSelectedPageIndex(appState: AppState) -> Int? {
        findSelectedPDFFile(appState: appState)?.lastReadPageIndex
    }

    // WHY: selected-file lookup has one definition for position and bookmark mappings.
    private func findSelectedPDFFile(appState: AppState) -> ImportedPDFFile? {
        guard let identifier: UUID = appState.selectedPDFFileIdentifier else { return nil }
        return appState.importedPDFFiles.first { $0.identifier == identifier }
    }

    // WHY: the selected identifier is resolved to its saved position without exposing the domain item.
    private func makeReaderPosition(appState: AppState) -> PDFReaderPosition? {
        findSelectedPDFFile(appState: appState)?.lastReadScrollPosition.map(makeReaderPosition)
    }

    // WHY: the app boundary translates persisted coordinates into the feature-owned value type.
    private func makeReaderPosition(domainPosition: PDFScrollPosition) -> PDFReaderPosition {
        PDFReaderPosition(
            pageIndex: domainPosition.pageIndex,
            pagePointX: domainPosition.pagePointX,
            pagePointY: domainPosition.pagePointY,
            zoomScale: domainPosition.zoomScale
        )
    }

    // WHY: the reverse mapping keeps the package's display type out of persistence metadata.
    private func makeDomainPosition(_ readerPosition: PDFReaderPosition) -> PDFScrollPosition {
        PDFScrollPosition(
            pageIndex: readerPosition.pageIndex,
            pagePointX: readerPosition.pagePointX,
            pagePointY: readerPosition.pagePointY,
            zoomScale: readerPosition.zoomScale
        )
    }

    // WHY: presentation page numbers are converted to zero-based domain indices at the app boundary.
    private func requestAssistantSummary(startPageNumber: Int, endPageNumber: Int) {
        appStore.generatePDFSummary(pageRange: makePDFPageRange(startPageNumber: startPageNumber, endPageNumber: endPageNumber))
    }

    // WHY: free-form questions and their selected scope cross into domain behavior together.
    private func submitAssistantQuestion(_ question: String, startPageNumber: Int, endPageNumber: Int, usesSelectedPages: Bool) {
        let pageRange: PDFPageRange? = usesSelectedPages ? makePDFPageRange(startPageNumber: startPageNumber, endPageNumber: endPageNumber) : nil
        appStore.answerPDFQuestion(question, pageRange: pageRange)
    }

    // WHY: one conversion prevents one-based display values from leaking into PDFKit-facing domain state.
    private func makePDFPageRange(startPageNumber: Int, endPageNumber: Int) -> PDFPageRange {
        PDFPageRange(lowerPageIndex: startPageNumber - 1, upperPageIndex: endPageNumber - 1)
    }

    // WHY: persisted inquiry values become display-only messages without exposing domain types to the package.
    private func makeAssistantMessage(_ entry: PDFInquiryEntry) -> PDFAssistantMessage {
        PDFAssistantMessage(
            id: entry.id,
            author: entry.author == .person ? .person : .assistant,
            text: entry.text,
            pageRangeDescription: entry.pageRange?.pageNumberDescription ?? "General question",
            referencePageNumbers: entry.citedPageIndices.map { $0 + 1 }
        )
    }

    // WHY: system capability reasons are converted into concise actionable reader copy at the UI boundary.
    private func makeAssistantAvailability(_ availability: PDFInquiryAvailability) -> PDFAssistantAvailability {
        switch availability {
        case .available: return .available
        case .codexExecutableMissing: return .unavailable(title: "Codex CLI Not Found", description: "Set the absolute Codex executable path in Settings, then try again.")
        case .deviceNotEligible: return .unavailable(title: "Apple Intelligence Not Supported", description: "This Mac cannot run the on-device AI model.")
        case .appleIntelligenceNotEnabled: return .unavailable(title: "Turn On Apple Intelligence", description: "Enable Apple Intelligence in System Settings, then try again.")
        case .modelNotReady: return .unavailable(title: "AI Model Is Preparing", description: "The on-device model is still downloading. Try again shortly.")
        case .unsupportedLanguage: return .unavailable(title: "Language Not Supported", description: "The current app language is not supported by the on-device model.")
        case .unavailable: return .unavailable(title: "AI Unavailable", description: "The on-device model is unavailable right now.")
        }
    }

    // WHY: every active phase disables duplicate requests through one derived flag.
    private func makeIsAssistantGenerating(_ phase: PDFInquiryPhase) -> Bool {
        switch phase {
        case .extracting, .generating: return true
        case .idle, .failed: return false
        }
    }

    // WHY: domain phases become specific progress and recovery messages without introducing UI wording into the store.
    private func makeAssistantStatusDescription(_ phase: PDFInquiryPhase) -> String? {
        switch phase {
        case .idle: return nil
        case .extracting(let pageRange): return pageRange.map { "Reading \($0.pageNumberDescription)…" } ?? "Preparing answer…"
        case .generating(let pageRange): return pageRange.map { "Analyzing \($0.pageNumberDescription)…" } ?? "Preparing answer…"
        case .failed(let failure): return makeAssistantFailureDescription(failure)
        }
    }

    // WHY: failure copy has one mapping so every failed path gives a consistent next step.
    private func makeAssistantFailureDescription(_ failure: PDFInquiryFailure) -> String {
        switch failure {
        case .documentUnavailable: return "The PDF could not be opened."
        case .invalidPageRange: return "Choose a valid page range."
        case .noReadableText: return "No readable text was found in these pages."
        case .generationFailed: return "The answer could not be generated. Try again."
        }
    }
}
