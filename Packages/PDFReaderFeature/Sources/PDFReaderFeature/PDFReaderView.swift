import AppKit
import SwiftUI

public struct PDFReaderView<Model: PDFReaderViewModel>: View {
    @ObservedObject private var model: Model
    @State private var isShowingRemovalConfirmation: Bool = false
    @State private var isShowingReaderInspector: Bool = false
    @State private var selectedInspectorSection: InspectorSection = .assistant
    @State private var assistantStartPageNumber: Int = 1
    @State private var assistantEndPageNumber: Int = 1
    @State private var assistantQuestion: String = ""
    @State private var isAssistantSparklesAnimating: Bool = false
    @State private var isUsingSelectedPages: Bool = true

    public init(model: Model) {
        self.model = model
    }

    public var body: some View {
        readerContent
            .toolbar { readerToolbar }
            .inspector(isPresented: $isShowingReaderInspector) { readerInspector }
            .alert("Remove all highlights?", isPresented: $isShowingRemovalConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Remove All", role: .destructive) { model.send(.allHighlightsRemovalRequested) }
            } message: {
                Text("This cannot be undone.")
            }
            .onChange(of: model.documentURL) { isShowingRemovalConfirmation = false }
            .onChange(of: model.documentURL) { synchronizeAssistantPageRange() }
            .onChange(of: model.totalPageCount) { synchronizeAssistantPageRange() }
    }

    @ViewBuilder
    private var readerContent: some View {
        if let documentURL: URL = model.documentURL {
            PDFDocumentView(
                documentURL: documentURL,
                initialPosition: model.initialPosition,
                isAllHighlightsRemovalPending: model.isAllHighlightsRemovalPending,
                bookmarkNavigationPageIndex: model.bookmarkNavigationPageIndex,
                onEvent: model.send
            )
            .overlay { nightModeOverlay }
        } else if model.isDocumentFileMissing {
            missingDocumentPlaceholder
        } else {
            noSelectionPlaceholder
        }
    }

    @ViewBuilder
    private var nightModeOverlay: some View {
        if model.isNightModeEnabled {
            Color.black.opacity(0.5).allowsHitTesting(false)
        }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        if model.documentURL != nil {
            ToolbarItem(placement: .primaryAction) { currentPageBookmarkButton }
            ToolbarItem(placement: .primaryAction) { assistantInspectorButton }
            ToolbarItem(placement: .primaryAction) { bookmarksInspectorButton }
            ToolbarItem(placement: .primaryAction) { nightModeButton }
            ToolbarItem(placement: .primaryAction) { removeAllHighlightsButton }
        }
    }

    private var currentPageBookmarkButton: some View {
        Button(action: { model.send(.currentPageBookmarkToggled) }) {
            Image(systemName: model.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
        }
        .keyboardShortcut("d", modifiers: .command)
        .help(currentPageBookmarkHelp)
        .disabled(model.currentPageIndex == nil)
    }

    private var currentPageBookmarkHelp: String {
        guard let pageIndex: Int = model.currentPageIndex else { return "Bookmark Current Page" }
        let action: String = model.isCurrentPageBookmarked ? "Remove Bookmark from" : "Bookmark"
        return "\(action) Page \(pageIndex + 1)"
    }

    private var assistantInspectorButton: some View {
        Button(action: toggleAssistantInspector) {
            Label("Ask AI", systemImage: "sparkles")
        }
        .help("Ask AI About This PDF")
    }

    private var bookmarksInspectorButton: some View {
        Button(action: { presentInspector(section: .bookmarks) }) {
            Label("Bookmarks", systemImage: "sidebar.right")
        }
        .help("Show Bookmarks")
    }

    private var readerInspector: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $selectedInspectorSection) {
                Text("AI").tag(InspectorSection.assistant)
                Text("Bookmarks").tag(InspectorSection.bookmarks)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            Divider()
            inspectorSectionContent
        }
        .inspectorColumnWidth(min: 300, ideal: 360, max: 480)
    }

    @ViewBuilder
    private var inspectorSectionContent: some View {
        switch selectedInspectorSection {
        case .assistant: assistantInspector
        case .bookmarks: bookmarksInspector
        }
    }

    @ViewBuilder
    private var assistantInspector: some View {
        switch model.assistantAvailability {
        case .available:
            availableAssistantInspector
        case .unavailable(let title, let description):
            makeUnavailableAssistantInspector(title: title, description: description)
        }
    }

    private var availableAssistantInspector: some View {
        VStack(spacing: 0) {
            assistantScopeControls
            Divider()
            assistantConversation
            Divider()
            assistantComposer
        }
    }

    private var assistantScopeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pages").font(.headline)
                Spacer()
                Button("Current") { synchronizeAssistantPageRange() }
                    .buttonStyle(.borderless)
            }
            HStack {
                Stepper("From: \(assistantStartPageNumber)", value: $assistantStartPageNumber, in: assistantPageNumberRange)
                Stepper("To: \(assistantEndPageNumber)", value: $assistantEndPageNumber, in: assistantPageNumberRange)
            }
            .onChange(of: assistantStartPageNumber) {
                assistantEndPageNumber = max(assistantEndPageNumber, assistantStartPageNumber)
            }
            .onChange(of: assistantEndPageNumber) {
                assistantStartPageNumber = min(assistantStartPageNumber, assistantEndPageNumber)
            }
            Button("要約する", systemImage: "text.document") { requestAssistantSummary() }
                .disabled(isAssistantActionDisabled)
        }
        .padding()
    }

    private var assistantConversation: some View {
        Group {
            if model.assistantMessages.isEmpty { emptyAssistantConversation } else { assistantMessageList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyAssistantConversation: some View {
        ContentUnavailableView(
            "Ask About These Pages",
            systemImage: "sparkles",
            description: Text("Summarize a range or ask a question. Answers may contain mistakes.")
        )
    }

    private var assistantMessageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(model.assistantMessages) { makeAssistantMessageRow($0) }
            }
            .padding()
        }
    }

    private func makeAssistantMessageRow(_ message: PDFAssistantMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.author == .person ? "You" : "AI")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message.pageRangeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: { copyAssistantMessage(message.text) }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
            Text(message.text).textSelection(.enabled)
            makeAssistantReferences(message.referencePageNumbers)
        }
        .padding(10)
        .background(message.author == .person ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func makeAssistantReferences(_ pageNumbers: [Int]) -> some View {
        if !pageNumbers.isEmpty {
            HStack(spacing: 6) {
                Text("Sources:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(pageNumbers, id: \.self) { pageNumber in
                    Button("p.\(pageNumber)") {
                        model.send(.assistantReferenceSelected(pageNumber: pageNumber))
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    private var assistantComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let statusDescription: String = model.assistantStatusDescription {
                makeAssistantStatus(statusDescription)
            }
            Toggle("ページを参照", isOn: $isUsingSelectedPages)
                .toggleStyle(.switch)
            HStack(alignment: .bottom) {
                TextField("Ask about selected pages", text: $assistantQuestion, axis: .vertical)
                    .lineLimit(1...5)
                    .onSubmit(submitAssistantQuestion)
                if model.isAssistantGenerating { cancelAssistantButton } else { submitAssistantButton }
            }
            Text("AI-generated answers may be inaccurate. Check the cited pages.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }

    private func makeAssistantStatus(_ description: String) -> some View {
        HStack(spacing: 8) {
            if model.isAssistantGenerating { assistantSparklesIndicator }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.isAssistantGenerating {
                Spacer()
                Button("Try Again") { model.send(.assistantRetryRequested) }
                    .buttonStyle(.borderless)
            }
        }
    }

    private var assistantSparklesIndicator: some View {
        Image(systemName: "sparkles")
            .font(.caption)
            .foregroundStyle(.tint)
            .scaleEffect(isAssistantSparklesAnimating ? 1.12 : 0.88)
            .opacity(isAssistantSparklesAnimating ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isAssistantSparklesAnimating)
            .onAppear { isAssistantSparklesAnimating = true }
            .onDisappear { isAssistantSparklesAnimating = false }
    }

    private var submitAssistantButton: some View {
        Button(action: submitAssistantQuestion) {
            Image(systemName: "arrow.up.circle.fill").font(.title2)
        }
        .buttonStyle(.borderless)
        .disabled(isAssistantActionDisabled || assistantQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .help("Send")
    }

    private var cancelAssistantButton: some View {
        Button(action: { model.send(.assistantGenerationCancelled) }) {
            Image(systemName: "stop.circle.fill").font(.title2)
        }
        .buttonStyle(.borderless)
        .help("Cancel")
    }

    private func makeUnavailableAssistantInspector(title: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "sparkles")
        } description: {
            Text(description)
        } actions: {
            Button("Try Again") { model.send(.assistantAvailabilityRefreshRequested) }
        }
    }

    private var assistantPageNumberRange: ClosedRange<Int> {
        1...max(1, model.totalPageCount)
    }

    private var isAssistantActionDisabled: Bool {
        model.isAssistantGenerating || model.totalPageCount == 0
    }

    private func presentInspector(section: InspectorSection) {
        selectedInspectorSection = section
        if section == .assistant && !isShowingReaderInspector { synchronizeAssistantPageRange() }
        isShowingReaderInspector = true
    }

    // WHY: the existing AI toolbar control provides one consistent entry point for opening and collapsing its inspector.
    private func toggleAssistantInspector() {
        guard isShowingReaderInspector && selectedInspectorSection == .assistant else {
            presentInspector(section: .assistant)
            return
        }
        isShowingReaderInspector = false
    }

    private func synchronizeAssistantPageRange() {
        let pageNumber: Int = min(max((model.currentPageIndex ?? 0) + 1, 1), max(model.totalPageCount, 1))
        assistantStartPageNumber = pageNumber
        assistantEndPageNumber = pageNumber
    }

    private func requestAssistantSummary() {
        model.send(.assistantSummaryRequested(
            startPageNumber: assistantStartPageNumber,
            endPageNumber: assistantEndPageNumber
        ))
    }

    private func submitAssistantQuestion() {
        let question: String = assistantQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        model.send(.assistantQuestionSubmitted(
            question: question,
            startPageNumber: assistantStartPageNumber,
            endPageNumber: assistantEndPageNumber,
            usesSelectedPages: isUsingSelectedPages
        ))
        assistantQuestion = ""
    }

    private func copyAssistantMessage(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var bookmarksInspector: some View {
        Group {
            if model.bookmarks.isEmpty { emptyBookmarksPlaceholder } else { bookmarksList }
        }
        .navigationTitle("Bookmarks")
    }

    private var bookmarksList: some View {
        List(model.bookmarks) { bookmark in
            bookmarkRow(bookmark)
        }
    }

    private func bookmarkRow(_ bookmark: PDFBookmarkItem) -> some View {
        BookmarkRow(
            bookmark: bookmark,
            onSelected: { model.send(.bookmarkSelected(bookmark.pageIndex)) },
            onRemoved: { model.send(.bookmarkRemoved(bookmark.pageIndex)) },
            onCommentChanged: { model.send(.bookmarkCommentChanged(pageIndex: bookmark.pageIndex, comment: $0)) }
        )
    }

    private var emptyBookmarksPlaceholder: some View {
        ContentUnavailableView(
            "No Bookmarks",
            systemImage: "bookmark",
            description: Text("Bookmark a page to find it here.")
        )
    }

    private var nightModeButton: some View {
        Button(action: { model.send(.nightModeToggled) }) {
            Image(systemName: model.isNightModeEnabled ? "moon.fill" : "moon")
        }
        .help("Toggle night mode")
    }

    private var removeAllHighlightsButton: some View {
        Button(action: { isShowingRemovalConfirmation = true }) { Image(systemName: "eraser") }
            .help("Remove all highlights")
    }

    private var noSelectionPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Select a PDF to read")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // WHY: a library entry whose file was moved or deleted must say so instead of looking unselected.
    private var missingDocumentPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("PDF file not found")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("The file was moved or deleted. Import it again.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct BookmarkRow: View {
        let bookmark: PDFBookmarkItem
        let onSelected: () -> Void
        let onRemoved: () -> Void
        let onCommentChanged: (String?) -> Void

        @State private var commentText: String
        @FocusState private var isCommentFocused: Bool

        init(
            bookmark: PDFBookmarkItem,
            onSelected: @escaping () -> Void,
            onRemoved: @escaping () -> Void,
            onCommentChanged: @escaping (String?) -> Void
        ) {
            self.bookmark = bookmark
            self.onSelected = onSelected
            self.onRemoved = onRemoved
            self.onCommentChanged = onCommentChanged
            _commentText = State(initialValue: bookmark.comment ?? "")
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                bookmarkHeader
                commentField
            }
            .contextMenu { removeBookmarkMenuButton }
            .onChange(of: isCommentFocused) { _, isFocused in if !isFocused { commitComment() } }
            .onChange(of: bookmark.comment) { _, comment in synchronizeComment(comment) }
        }

        private var bookmarkHeader: some View {
            HStack {
                Button(action: onSelected) {
                    Label("Page \(bookmark.pageNumber)", systemImage: "bookmark.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Spacer()
                removeBookmarkButton
            }
            .contentShape(Rectangle())
        }

        private var commentField: some View {
            TextField("Add a comment", text: $commentText)
                .textFieldStyle(.roundedBorder)
                .focused($isCommentFocused)
                .onSubmit(commitComment)
        }

        private var removeBookmarkButton: some View {
            Button(action: onRemoved) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Remove Bookmark")
        }

        private var removeBookmarkMenuButton: some View {
            Button(role: .destructive, action: onRemoved) {
                Label("Remove Bookmark", systemImage: "trash")
            }
        }

        private func commitComment() {
            onCommentChanged(commentText)
        }

        private func synchronizeComment(_ comment: String?) {
            guard !isCommentFocused else { return }
            commentText = comment ?? ""
        }
    }

    private enum InspectorSection: Hashable {
        case assistant
        case bookmarks
    }
}
