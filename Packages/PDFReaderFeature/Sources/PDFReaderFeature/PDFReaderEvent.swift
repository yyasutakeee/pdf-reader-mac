public enum PDFReaderEvent {
    case nightModeToggled
    case allHighlightsRemovalRequested
    case allHighlightsRemovalHandled
    case currentPageChanged(Int)
    case currentPageBookmarkToggled
    case bookmarkSelected(Int)
    case bookmarkRemoved(Int)
    case bookmarkCommentChanged(pageIndex: Int, comment: String?)
    case bookmarkNavigationHandled
    case positionChanged(PDFReaderPosition)
    case assistantSummaryRequested(startPageNumber: Int, endPageNumber: Int)
    case assistantQuestionSubmitted(question: String, startPageNumber: Int, endPageNumber: Int, usesSelectedPages: Bool)
    case assistantRetryRequested
    case assistantGenerationCancelled
    case assistantAvailabilityRefreshRequested
    case assistantReferenceSelected(pageNumber: Int)
}
