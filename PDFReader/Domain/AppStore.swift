import Foundation
import PDFKit

final class AppStore: Store<AppState> {
    private let pdfLibraryRepository: PDFLibraryRepository
    private let pdfFileStorageService: PDFFileStorageService
    private let pdfThumbnailService: PDFThumbnailService
    private let pdfThumbnailRepository: PDFThumbnailRepository
    private let appearanceRepository: AppearanceRepository
    private let pdfAnswerConfigurationRepository: PDFAnswerConfigurationRepository
    private let pdfPageContentExtractor: PDFPageContentExtractor
    private let appleFoundationModelPDFAnswerGenerator: any PDFAnswerGenerating
    private var pdfInquiryTask: Task<Void, Never>? = nil

    init(
        pdfLibraryRepository: PDFLibraryRepository = PDFLibraryRepository(),
        pdfFileStorageService: PDFFileStorageService = PDFFileStorageService(),
        pdfThumbnailService: PDFThumbnailService = PDFThumbnailService(),
        pdfThumbnailRepository: PDFThumbnailRepository = PDFThumbnailRepository(),
        appearanceRepository: AppearanceRepository = AppearanceRepository(),
        pdfAnswerConfigurationRepository: PDFAnswerConfigurationRepository = PDFAnswerConfigurationRepository(),
        pdfPageContentExtractor: PDFPageContentExtractor = PDFPageContentExtractor(),
        pdfAnswerGenerator: any PDFAnswerGenerating = AppleFoundationModelPDFAnswerGenerator()
    ) {
        self.pdfLibraryRepository = pdfLibraryRepository
        self.pdfFileStorageService = pdfFileStorageService
        self.pdfThumbnailService = pdfThumbnailService
        self.pdfThumbnailRepository = pdfThumbnailRepository
        self.appearanceRepository = appearanceRepository
        self.pdfAnswerConfigurationRepository = pdfAnswerConfigurationRepository
        self.pdfPageContentExtractor = pdfPageContentExtractor
        self.appleFoundationModelPDFAnswerGenerator = pdfAnswerGenerator
        pdfFileStorageService.migrateLegacyStoredFiles()
        let pdfAnswerProvider: PDFAnswerProvider = pdfAnswerConfigurationRepository.loadPDFAnswerProvider()
        let codexExecutablePath: String = pdfAnswerConfigurationRepository.loadCodexExecutablePath()
        let selectedPDFAnswerGenerator: any PDFAnswerGenerating
        switch pdfAnswerProvider {
        case .appleIntelligence: selectedPDFAnswerGenerator = pdfAnswerGenerator
        case .localCodex: selectedPDFAnswerGenerator = LocalCodexPDFAnswerGenerator(executablePath: codexExecutablePath)
        }
        super.init(initialState: AppState(
            importedPDFFiles: pdfLibraryRepository.loadSavedPDFFiles(),
            appearanceTheme: appearanceRepository.loadAppearanceTheme(),
            pdfAnswerProvider: pdfAnswerProvider,
            codexExecutablePath: codexExecutablePath,
            pdfInquiryAvailability: selectedPDFAnswerGenerator.checkAvailability()
        ))
    }

    // WHY: the import picker is app navigation state coordinated through the single state tree.
    func presentFileImporter() {
        setState { $0.isFileImporterPresented = true }
    }

    // WHY: cancellation and completion both return importer presentation to its resting state.
    func dismissFileImporter() {
        setState { $0.isFileImporterPresented = false }
    }

    // WHY: importing owns security-scoped access and every persistence write behind the store boundary.
    func importPDFFile(from sourceURL: URL) {
        let isAccessGranted: Bool = sourceURL.startAccessingSecurityScopedResource()
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        print("[AppStore] startAccessingSecurityScopedResource: \(isAccessGranted)")
        guard let importedPDFFile: ImportedPDFFile = makeImportedPDFFile(sourceURL: sourceURL) else { return }
        setState { appState in
            appState.importedPDFFiles.append(importedPDFFile)
            appState.isFileImporterPresented = false
        }
        persistImportedPDFFiles()
    }

    // WHY: selection resolves the app-owned filename into the concrete URL needed by observers.
    func selectPDFFile(identifier: UUID?) {
        guard let identifier else { deselectPDFFile(); return }
        guard let importedPDFFile: ImportedPDFFile = findImportedPDFFile(identifier: identifier) else { return }
        cancelPDFInquiryTask()
        let fileURL: URL? = pdfFileStorageService.resolveStoredFileURL(storedFileName: importedPDFFile.storedFileName)
        let pdfInquiryAvailability: PDFInquiryAvailability = makeSelectedPDFAnswerGenerator().checkAvailability()
        setState { appState in
            appState.selectedPDFFileIdentifier = identifier
            appState.selectedPDFFileURL = fileURL
            appState.isSelectedPDFFileMissing = fileURL == nil
            appState.isAllHighlightsRemovalPending = false
            appState.pdfInquiryEntries = []
            appState.pdfInquiryPhase = .idle
            appState.pdfInquiryAvailability = pdfInquiryAvailability
            appState.pdfInquiryRequestIdentifier = nil
        }
    }

    // WHY: an empty library selection must clear every value derived from the previous document.
    func deselectPDFFile() {
        cancelPDFInquiryTask()
        setState { appState in
            appState.selectedPDFFileIdentifier = nil
            appState.selectedPDFFileURL = nil
            appState.isSelectedPDFFileMissing = false
            appState.pdfInquiryRequestIdentifier = nil
            appState.isAllHighlightsRemovalPending = false
            appState.pdfInquiryEntries = []
            appState.pdfInquiryPhase = .idle
        }
    }

    // WHY: removal coordinates the stored PDF, cached thumbnail, metadata, and active selection atomically.
    func removeImportedPDFFile(identifier: UUID) {
        guard let importedPDFFile: ImportedPDFFile = findImportedPDFFile(identifier: identifier) else { return }
        cancelPDFInquiryIfSelected(identifier: identifier)
        pdfFileStorageService.deleteStoredFile(storedFileName: importedPDFFile.storedFileName)
        pdfThumbnailRepository.deleteThumbnail(for: identifier)
        setState { removeImportedPDFFile(identifier: identifier, from: &$0) }
        persistImportedPDFFiles()
    }

    // WHY: callers need the current app-owned location without gaining direct access to file storage.
    func findStoredPDFFileURL(identifier: UUID) -> URL? {
        guard let importedPDFFile: ImportedPDFFile = findImportedPDFFile(identifier: identifier) else { return nil }
        return pdfFileStorageService.resolveStoredFileURL(storedFileName: importedPDFFile.storedFileName)
    }

    // WHY: the reading position is persisted so reopening a document resumes at the last known destination.
    func saveReadingPosition(_ position: PDFScrollPosition) {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return }
        setState { updateReadingPosition(position, identifier: identifier, in: &$0) }
        persistImportedPDFFiles()
    }

    // WHY: a page bookmark belongs to the selected document and must survive future reading sessions.
    func toggleBookmark(pageIndex: Int) {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return }
        setState { toggleBookmark(pageIndex: pageIndex, identifier: identifier, in: &$0) }
        persistImportedPDFFiles()
    }

    // WHY: explicit removal supports deleting a saved page independently from the current reading position.
    func removeBookmark(pageIndex: Int) {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return }
        setState { removeBookmark(pageIndex: pageIndex, identifier: identifier, in: &$0) }
        persistImportedPDFFiles()
    }

    // WHY: bookmark notes belong to the saved document metadata and may be cleared independently from the page marker.
    func updateBookmarkComment(pageIndex: Int, comment: String?) {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return }
        let normalizedComment: String? = normalizeBookmarkComment(comment)
        setState { updateBookmarkComment(pageIndex: pageIndex, comment: normalizedComment, identifier: identifier, in: &$0) }
        persistImportedPDFFiles()
    }

    // WHY: night mode is temporary reader state shared with the package through its view store.
    func toggleNightMode() {
        setState { $0.isNightModeEnabled.toggle() }
    }

    // WHY: highlight removal is modeled as a command state until the retained PDFKit view acknowledges it.
    func requestAllHighlightsRemoval() {
        setState { $0.isAllHighlightsRemovalPending = true }
    }

    // WHY: acknowledgment prevents SwiftUI updates from repeating a completed destructive command.
    func finishAllHighlightsRemoval() {
        setState { $0.isAllHighlightsRemovalPending = false }
    }

    // WHY: one-click summarization uses the same grounded inquiry pipeline as a typed question.
    func generatePDFSummary(pageRange: PDFPageRange) {
        startPDFInquiry(question: "指定したページを日本語で要約してください。", pageRange: pageRange)
    }

    // WHY: document questions are accepted only through the store so extraction and generation share one state lifecycle.
    func answerPDFQuestion(_ question: String, pageRange: PDFPageRange?) {
        let normalizedQuestion: String = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { return }
        startPDFInquiry(question: normalizedQuestion, pageRange: pageRange)
    }

    // WHY: retry reuses the last recorded request and its immutable source range.
    func retryPDFInquiry() {
        guard let entry: PDFInquiryEntry = state.pdfInquiryEntries.last(where: { $0.author == .person }) else { return }
        startPDFInquiry(question: entry.text, pageRange: entry.pageRange)
    }

    // WHY: cancellation must end both the model task and its observable in-progress phase.
    func cancelPDFInquiry() {
        cancelPDFInquiryTask()
        setState { appState in
            appState.pdfInquiryPhase = .idle
            appState.pdfInquiryRequestIdentifier = nil
        }
    }

    // WHY: model readiness and executable availability can change while the app remains open.
    func refreshPDFInquiryAvailability() {
        let pdfInquiryAvailability: PDFInquiryAvailability = makeSelectedPDFAnswerGenerator().checkAvailability()
        setState { $0.pdfInquiryAvailability = pdfInquiryAvailability }
    }

    // WHY: every request starts from a validated selected document and replaces any superseded work.
    private func startPDFInquiry(question: String, pageRange: PDFPageRange?) {
        let documentURL: URL? = state.selectedPDFFileURL
        guard pageRange == nil || documentURL != nil else { setPDFInquiryFailure(.documentUnavailable); return }
        guard state.pdfInquiryAvailability == .available else { refreshPDFInquiryAvailability(); return }
        guard isValidPDFPageRangeIfNeeded(pageRange) else { setPDFInquiryFailure(.invalidPageRange); return }
        cancelPDFInquiryTask()
        let pdfAnswerGenerator: any PDFAnswerGenerating = makeSelectedPDFAnswerGenerator()
        let requestIdentifier: UUID = UUID()
        appendPDFInquiryQuestion(question, pageRange: pageRange)
        setState { appState in
            appState.pdfInquiryPhase = .extracting(pageRange)
            appState.pdfInquiryRequestIdentifier = requestIdentifier
        }
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.performPDFInquiry(
                question: question,
                pageRange: pageRange,
                documentURL: documentURL,
                requestIdentifier: requestIdentifier,
                pdfAnswerGenerator: pdfAnswerGenerator
            )
        }
        setPDFInquiryTask(task)
    }

    // WHY: completion steps are serialized in one task so cancellation cannot append a partial answer.
    private func performPDFInquiry(
        question: String,
        pageRange: PDFPageRange?,
        documentURL: URL?,
        requestIdentifier: UUID,
        pdfAnswerGenerator: any PDFAnswerGenerating
    ) async {
        do {
            let pageContents: [PDFPageContent] = try extractPDFPageContents(pageRange: pageRange, documentURL: documentURL)
            try Task.checkCancellation()
            guard isCurrentPDFInquiry(requestIdentifier) else { return }
            guard pageRange == nil || pageContents.contains(where: { !$0.text.isEmpty }) else {
                setPDFInquiryFailure(.noReadableText, requestIdentifier: requestIdentifier)
                return
            }
            setState { $0.pdfInquiryPhase = .generating(pageRange) }
            let response: PDFGeneratedResponse = try await pdfAnswerGenerator.generateResponse(
                question: question,
                pageContents: pageContents
            )
            try Task.checkCancellation()
            guard isCurrentPDFInquiry(requestIdentifier) else { return }
            appendPDFInquiryResponse(response, pageRange: pageRange, requestIdentifier: requestIdentifier)
        } catch is CancellationError {
            return
        } catch let extractionError as PDFPageContentExtractor.ExtractionError {
            setPDFInquiryFailure(makePDFInquiryFailure(extractionError), requestIdentifier: requestIdentifier)
        } catch {
            setPDFInquiryFailure(.generationFailed, requestIdentifier: requestIdentifier)
        }
    }

    // WHY: validation uses persisted page count so malformed ranges never reach PDFKit.
    private func isValidPDFPageRange(_ pageRange: PDFPageRange) -> Bool {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return false }
        guard let pageCount: Int = findImportedPDFFile(identifier: identifier)?.totalPageCount else { return false }
        return pageRange.lowerPageIndex >= 0 && pageRange.upperPageIndex < pageCount && pageRange.lowerPageIndex <= pageRange.upperPageIndex
    }

    // WHY: general questions intentionally bypass document validation because they do not need a selected page range.
    private func isValidPDFPageRangeIfNeeded(_ pageRange: PDFPageRange?) -> Bool {
        guard let pageRange else { return true }
        return isValidPDFPageRange(pageRange)
    }

    // WHY: only page-scoped questions need extraction; general questions must reach the model without PDF evidence.
    private func extractPDFPageContents(pageRange: PDFPageRange?, documentURL: URL?) throws -> [PDFPageContent] {
        guard let pageRange, let documentURL else { return [] }
        return try pdfPageContentExtractor.extractPageContents(documentURL: documentURL, pageRange: pageRange)
    }

    // WHY: the request is recorded before work begins so its original scope remains auditable.
    private func appendPDFInquiryQuestion(_ question: String, pageRange: PDFPageRange?) {
        let entry: PDFInquiryEntry = PDFInquiryEntry(
            id: UUID(),
            author: .person,
            text: question,
            pageRange: pageRange,
            citedPageIndices: []
        )
        setState { $0.pdfInquiryEntries.append(entry) }
    }

    // WHY: citations outside the requested range are discarded before becoming trusted source indices.
    private func appendPDFInquiryResponse(
        _ response: PDFGeneratedResponse,
        pageRange: PDFPageRange?,
        requestIdentifier: UUID
    ) {
        let citedPageIndices: [Int] = pageRange.map { response.citedPageIndices.filter($0.pageIndices.contains) } ?? []
        let entry: PDFInquiryEntry = PDFInquiryEntry(
            id: UUID(),
            author: .model,
            text: response.answer,
            pageRange: pageRange,
            citedPageIndices: citedPageIndices
        )
        setState { appState in
            guard appState.pdfInquiryRequestIdentifier == requestIdentifier else { return }
            appState.pdfInquiryEntries.append(entry)
            appState.pdfInquiryPhase = .idle
            appState.pdfInquiryRequestIdentifier = nil
        }
    }

    // WHY: extraction errors are translated once into stable domain failures.
    private func makePDFInquiryFailure(_ extractionError: PDFPageContentExtractor.ExtractionError) -> PDFInquiryFailure {
        switch extractionError {
        case .documentUnavailable: return .documentUnavailable
        case .invalidPageRange: return .invalidPageRange
        }
    }

    // WHY: all failed paths publish their terminal state through one mutation point.
    private func setPDFInquiryFailure(_ failure: PDFInquiryFailure, requestIdentifier: UUID? = nil) {
        setState { appState in
            guard requestIdentifier == nil || appState.pdfInquiryRequestIdentifier == requestIdentifier else { return }
            appState.pdfInquiryPhase = .failed(failure)
            appState.pdfInquiryRequestIdentifier = nil
        }
    }

    // WHY: a request identifier prevents superseded work from publishing into a later document or question.
    private func isCurrentPDFInquiry(_ requestIdentifier: UUID) -> Bool {
        state.pdfInquiryRequestIdentifier == requestIdentifier
    }

    // WHY: one mutation door keeps task replacement and cleanup discoverable within the state-owning store.
    private func setPDFInquiryTask(_ task: Task<Void, Never>?) {
        pdfInquiryTask = task
    }

    // WHY: document switches and new requests must prevent stale work from publishing into the current inquiry.
    private func cancelPDFInquiryTask() {
        pdfInquiryTask?.cancel()
        setPDFInquiryTask(nil)
    }


    // WHY: appearance selection is persisted by the store so Settings never touches UserDefaults directly.
    func selectAppearanceTheme(_ appearanceTheme: AppearanceTheme) {
        appearanceRepository.persistAppearanceTheme(appearanceTheme)
        setState { $0.appearanceTheme = appearanceTheme }
    }

    // WHY: changing the answer provider replaces any active request before its response can cross provider state.
    func selectPDFAnswerProvider(_ pdfAnswerProvider: PDFAnswerProvider) {
        cancelPDFInquiryTask()
        pdfAnswerConfigurationRepository.persistPDFAnswerProvider(pdfAnswerProvider)
        let availability: PDFInquiryAvailability = makePDFAnswerGenerator(
            provider: pdfAnswerProvider,
            codexExecutablePath: state.codexExecutablePath
        ).checkAvailability()
        setState { appState in
            appState.pdfAnswerProvider = pdfAnswerProvider
            appState.pdfInquiryAvailability = availability
            appState.pdfInquiryPhase = .idle
            appState.pdfInquiryRequestIdentifier = nil
        }
    }

    // WHY: the CLI path is stored explicitly because a launched macOS app cannot rely on an interactive shell PATH.
    func updateCodexExecutablePath(_ executablePath: String) {
        let normalizedExecutablePath: String = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        pdfAnswerConfigurationRepository.persistCodexExecutablePath(normalizedExecutablePath)
        setState { appState in
            appState.codexExecutablePath = normalizedExecutablePath
            guard appState.pdfAnswerProvider == .localCodex else { return }
            appState.pdfInquiryAvailability = LocalCodexPDFAnswerGenerator(executablePath: normalizedExecutablePath).checkAvailability()
        }
    }

    // WHY: selection logic has one definition for launch, readiness checks, and request execution.
    private func makeSelectedPDFAnswerGenerator() -> any PDFAnswerGenerating {
        makePDFAnswerGenerator(provider: state.pdfAnswerProvider, codexExecutablePath: state.codexExecutablePath)
    }

    // WHY: provider construction remains separate from mutable state so proposed settings can be validated before publication.
    private func makePDFAnswerGenerator(
        provider: PDFAnswerProvider,
        codexExecutablePath: String
    ) -> any PDFAnswerGenerating {
        switch provider {
        case .appleIntelligence: return appleFoundationModelPDFAnswerGenerator
        case .localCodex: return LocalCodexPDFAnswerGenerator(executablePath: codexExecutablePath)
        }
    }

    // WHY: import construction groups file copying and metadata derivation behind one failure boundary.
    private func makeImportedPDFFile(sourceURL: URL) -> ImportedPDFFile? {
        guard let storedFileName: String = pdfFileStorageService.copyPDFFileIntoStorage(from: sourceURL) else { return nil }
        let identifier: UUID = UUID()
        let storedFileURL: URL? = pdfFileStorageService.resolveStoredFileURL(storedFileName: storedFileName)
        return ImportedPDFFile(
            identifier: identifier,
            displayName: sourceURL.deletingPathExtension().lastPathComponent,
            storedFileName: storedFileName,
            thumbnailFileURLAbsoluteString: makeThumbnailURLString(storedFileURL: storedFileURL, identifier: identifier),
            importedDate: Date(),
            totalPageCount: makePageCount(storedFileURL: storedFileURL)
        )
    }

    // WHY: thumbnail generation is optional metadata and must not fail the PDF import itself.
    private func makeThumbnailURLString(storedFileURL: URL?, identifier: UUID) -> String? {
        guard let storedFileURL else { return nil }
        let image = pdfThumbnailService.generateFirstPageThumbnail(for: storedFileURL, thumbnailSize: CGSize(width: 160, height: 220))
        return image.flatMap { pdfThumbnailRepository.saveThumbnail($0, for: identifier) }?.absoluteString
    }

    // WHY: page count is derived once during import to keep library progress rendering lightweight.
    private func makePageCount(storedFileURL: URL?) -> Int? {
        guard let storedFileURL else { return nil }
        return PDFDocument(url: storedFileURL)?.pageCount
    }

    // WHY: identifier lookup has one definition for selection and destructive operations.
    private func findImportedPDFFile(identifier: UUID) -> ImportedPDFFile? {
        state.importedPDFFiles.first { $0.identifier == identifier }
    }

    // WHY: deleting the active document must stop work that still reads its file.
    private func cancelPDFInquiryIfSelected(identifier: UUID) {
        guard state.selectedPDFFileIdentifier == identifier else { return }
        cancelPDFInquiryTask()
    }

    // WHY: removal also clears values derived from the deleted selection in the same mutation.
    private func removeImportedPDFFile(identifier: UUID, from appState: inout AppState) {
        appState.importedPDFFiles.removeAll { $0.identifier == identifier }
        guard appState.selectedPDFFileIdentifier == identifier else { return }
        appState.selectedPDFFileIdentifier = nil
        appState.selectedPDFFileURL = nil
        appState.isSelectedPDFFileMissing = false
        appState.isAllHighlightsRemovalPending = false
        appState.pdfInquiryEntries = []
        appState.pdfInquiryPhase = .idle
        appState.pdfInquiryRequestIdentifier = nil
    }

    // WHY: one mutation keeps persisted progress and the selected document snapshot identical.
    private func updateReadingPosition(_ position: PDFScrollPosition, identifier: UUID, in appState: inout AppState) {
        guard let index: Int = appState.importedPDFFiles.firstIndex(where: { $0.identifier == identifier }) else { return }
        appState.importedPDFFiles[index].lastReadPageIndex = position.pageIndex
        appState.importedPDFFiles[index].lastReadScrollPosition = position
        appState.importedPDFFiles[index].lastReadDate = Date()
    }

    // WHY: toggle semantics guarantee that each document contains at most one bookmark for a page.
    private func toggleBookmark(pageIndex: Int, identifier: UUID, in appState: inout AppState) {
        guard let index: Int = findImportedPDFFileIndex(identifier: identifier, in: appState) else { return }
        guard !appState.importedPDFFiles[index].bookmarks.contains(where: { $0.pageIndex == pageIndex }) else { removeBookmark(pageIndex: pageIndex, index: index, from: &appState); return }
        addBookmark(pageIndex: pageIndex, index: index, to: &appState)
    }

    // WHY: explicit removal changes only the selected document's matching saved page.
    private func removeBookmark(pageIndex: Int, identifier: UUID, in appState: inout AppState) {
        guard let index: Int = findImportedPDFFileIndex(identifier: identifier, in: appState) else { return }
        removeBookmark(pageIndex: pageIndex, index: index, from: &appState)
    }

    // WHY: one insertion path preserves ascending order for every bookmark mutation.
    private func addBookmark(pageIndex: Int, index: Int, to appState: inout AppState) {
        appState.importedPDFFiles[index].bookmarks.append(PDFPageBookmark(pageIndex: pageIndex, comment: nil))
        appState.importedPDFFiles[index].bookmarks.sort { $0.pageIndex < $1.pageIndex }
    }

    // WHY: toggle and explicit deletion share the same matching rule.
    private func removeBookmark(pageIndex: Int, index: Int, from appState: inout AppState) {
        appState.importedPDFFiles[index].bookmarks.removeAll { $0.pageIndex == pageIndex }
    }

    // WHY: optional comments use one whitespace rule so empty notes are never persisted as meaningful content.
    private func normalizeBookmarkComment(_ comment: String?) -> String? {
        guard let trimmedComment: String = comment?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return trimmedComment.isEmpty ? nil : trimmedComment
    }

    // WHY: comment changes must target the existing page marker without creating an implicit bookmark.
    private func updateBookmarkComment(pageIndex: Int, comment: String?, identifier: UUID, in appState: inout AppState) {
        guard let fileIndex: Int = findImportedPDFFileIndex(identifier: identifier, in: appState) else { return }
        guard let bookmarkIndex: Int = appState.importedPDFFiles[fileIndex].bookmarks.firstIndex(where: { $0.pageIndex == pageIndex }) else { return }
        appState.importedPDFFiles[fileIndex].bookmarks[bookmarkIndex].comment = comment
    }

    // WHY: bookmark mutations share one identifier lookup so document selection rules cannot diverge.
    private func findImportedPDFFileIndex(identifier: UUID, in appState: AppState) -> Int? {
        appState.importedPDFFiles.firstIndex { $0.identifier == identifier }
    }

    // WHY: every metadata mutation is encoded from the post-mutation state through one persistence call.
    private func persistImportedPDFFiles() {
        pdfLibraryRepository.persistPDFFiles(state.importedPDFFiles)
    }
}
