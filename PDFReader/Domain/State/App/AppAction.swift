import Foundation

enum AppAction {
    // MARK: - User events

    case appStarted
    case fileImporterPresentationRequested
    case fileImporterDismissed
    case pdfFileImportRequested(URL)
    case pdfFileSelectionChanged(UUID?)
    case importedPDFFileRemovalRequested(UUID)
    case importedPDFFileRevealRequested(UUID)
    case readingPositionChanged(PDFScrollPosition)
    case bookmarkToggled(pageIndex: Int)
    case bookmarkRemovalRequested(pageIndex: Int)
    case bookmarkCommentChanged(pageIndex: Int, comment: String?)
    case nightModeToggled
    case allHighlightsRemovalRequested
    case allHighlightsRemovalHandled
    case pdfSummaryRequested(PDFPageRange)
    case pdfQuestionSubmitted(question: String, pageRange: PDFPageRange?)
    case pdfInquiryRetryRequested
    case pdfInquiryCancellationRequested
    case pdfInquiryAvailabilityRefreshRequested
    case appearanceSelected(AppearanceTheme)
    case pdfAnswerProviderSelected(PDFAnswerProvider)
    case codexExecutablePathChanged(String)

    // MARK: - Effect results

    case appInitialDataLoaded(AppInitialData)
    case pdfFileImported(ImportedPDFFile?)
    case selectedPDFFileResolved(identifier: UUID, fileURL: URL?, availability: PDFInquiryAvailability)
    case pdfInquiryAvailabilityChecked(
        availability: PDFInquiryAvailability,
        provider: PDFAnswerProvider,
        codexExecutablePath: String
    )
    case pdfPageContentsExtracted(
        requestIdentifier: UUID,
        question: String,
        pageRange: PDFPageRange?,
        pageContents: [PDFPageContent]
    )
    case pdfInquiryResponseGenerated(
        requestIdentifier: UUID,
        responseIdentifier: UUID,
        pageRange: PDFPageRange?,
        response: PDFGeneratedResponse
    )
    case pdfInquiryFailed(requestIdentifier: UUID?, failure: PDFInquiryFailure)
}

struct AppInitialData {
    let importedPDFFiles: [ImportedPDFFile]
    let appearanceTheme: AppearanceTheme
    let pdfAnswerProvider: PDFAnswerProvider
    let codexExecutablePath: String
    let pdfInquiryAvailability: PDFInquiryAvailability
}
