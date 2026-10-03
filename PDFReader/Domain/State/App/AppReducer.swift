import Foundation

struct AppReducer: Reducer {
    private enum CancelIdentifier {
        case pdfInquiry
    }

    // WHY: one routing switch keeps every shared-state mutation and effect decision behind Store.dispatch(_:).
    func reduce(
        into state: inout AppState,
        action: AppAction,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        switch action {
        case .appStarted:
            return reduceAppStarted(state: &state, environment: environment)
        case .fileImporterPresentationRequested:
            state.isFileImporterPresented = true
            return .none
        case .fileImporterDismissed:
            state.isFileImporterPresented = false
            return .none
        case .pdfFileImportRequested(let sourceURL):
            return reducePDFFileImportRequested(sourceURL: sourceURL, environment: environment)
        case .pdfFileSelectionChanged(let identifier):
            return reducePDFFileSelectionChanged(identifier: identifier, state: &state, environment: environment)
        case .importedPDFFileRemovalRequested(let identifier):
            return reduceImportedPDFFileRemovalRequested(identifier: identifier, state: &state, environment: environment)
        case .importedPDFFileRevealRequested(let identifier):
            return reduceImportedPDFFileRevealRequested(identifier: identifier, state: state, environment: environment)
        case .readingPositionChanged(let position):
            return reduceReadingPositionChanged(position: position, state: &state, environment: environment)
        case .bookmarkToggled(let pageIndex):
            return reduceBookmarkToggled(pageIndex: pageIndex, state: &state, environment: environment)
        case .bookmarkRemovalRequested(let pageIndex):
            return reduceBookmarkRemovalRequested(pageIndex: pageIndex, state: &state, environment: environment)
        case .bookmarkCommentChanged(let pageIndex, let comment):
            return reduceBookmarkCommentChanged(pageIndex: pageIndex, comment: comment, state: &state, environment: environment)
        case .nightModeToggled:
            state.isNightModeEnabled.toggle()
            return .none
        case .allHighlightsRemovalRequested:
            state.isAllHighlightsRemovalPending = true
            return .none
        case .allHighlightsRemovalHandled:
            state.isAllHighlightsRemovalPending = false
            return .none
        case .pdfSummaryRequested(let pageRange):
            return reducePDFInquiryRequested(
                question: "指定したページを日本語で要約してください。",
                pageRange: pageRange,
                state: &state,
                environment: environment
            )
        case .pdfQuestionSubmitted(let question, let pageRange):
            return reducePDFQuestionSubmitted(question: question, pageRange: pageRange, state: &state, environment: environment)
        case .pdfInquiryRetryRequested:
            return reducePDFInquiryRetryRequested(state: &state, environment: environment)
        case .pdfInquiryCancellationRequested:
            return reducePDFInquiryCancellationRequested(state: &state)
        case .pdfInquiryAvailabilityRefreshRequested:
            return reducePDFInquiryAvailabilityCheck(state: state, environment: environment)
        case .appearanceSelected(let appearanceTheme):
            return reduceAppearanceSelected(appearanceTheme: appearanceTheme, state: &state, environment: environment)
        case .pdfAnswerProviderSelected(let provider):
            return reducePDFAnswerProviderSelected(provider: provider, state: &state, environment: environment)
        case .codexExecutablePathChanged(let executablePath):
            return reduceCodexExecutablePathChanged(executablePath: executablePath, state: &state, environment: environment)
        case .appInitialDataLoaded(let initialData):
            return reduceAppInitialDataLoaded(initialData: initialData, state: &state)
        case .pdfFileImported(let importedPDFFile):
            return reducePDFFileImported(importedPDFFile: importedPDFFile, state: &state, environment: environment)
        case .selectedPDFFileResolved(let identifier, let fileURL, let availability):
            return reduceSelectedPDFFileResolved(identifier: identifier, fileURL: fileURL, availability: availability, state: &state)
        case .pdfInquiryAvailabilityChecked(let availability, let provider, let codexExecutablePath):
            return reducePDFInquiryAvailabilityChecked(
                availability: availability,
                provider: provider,
                codexExecutablePath: codexExecutablePath,
                state: &state
            )
        case .pdfPageContentsExtracted(let requestIdentifier, let question, let pageRange, let pageContents):
            return reducePDFPageContentsExtracted(
                requestIdentifier: requestIdentifier,
                question: question,
                pageRange: pageRange,
                pageContents: pageContents,
                state: &state,
                environment: environment
            )
        case .pdfInquiryResponseGenerated(let requestIdentifier, let responseIdentifier, let pageRange, let response):
            return reducePDFInquiryResponseGenerated(
                requestIdentifier: requestIdentifier,
                responseIdentifier: responseIdentifier,
                pageRange: pageRange,
                response: response,
                state: &state
            )
        case .pdfInquiryFailed(let requestIdentifier, let failure):
            return reducePDFInquiryFailed(requestIdentifier: requestIdentifier, failure: failure, state: &state)
        }
    }

    // WHY: launch-time persistence reads are effects so the composition root constructs dependencies without reading them.
    private func reduceAppStarted(
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard state.initializationPhase == .notStarted else { return .none }
        state.initializationPhase = .loading
        return .run { dispatch in
            environment.storedPDFFileClient.migrateLegacyStoredFiles()
            let provider: PDFAnswerProvider = environment.pdfAnswerConfigurationClient.loadPDFAnswerProvider()
            let executablePath: String = environment.pdfAnswerConfigurationClient.loadCodexExecutablePath()
            dispatch(.appInitialDataLoaded(AppInitialData(
                importedPDFFiles: environment.pdfLibraryClient.loadSavedPDFFiles(),
                appearanceTheme: environment.appearanceClient.loadAppearanceTheme(),
                pdfAnswerProvider: provider,
                codexExecutablePath: executablePath,
                pdfInquiryAvailability: environment.pdfInquiryClient.checkAvailability(provider, executablePath)
            )))
        }
    }

    // WHY: launch data becomes one authoritative state snapshot only after every persisted value has been read.
    private func reduceAppInitialDataLoaded(
        initialData: AppInitialData,
        state: inout AppState
    ) -> Effect<AppAction> {
        guard state.initializationPhase == .loading else { return .none }
        state.initializationPhase = .loaded
        state.importedPDFFiles = initialData.importedPDFFiles
        state.appearanceTheme = initialData.appearanceTheme
        state.pdfAnswerProvider = initialData.pdfAnswerProvider
        state.codexExecutablePath = initialData.codexExecutablePath
        state.pdfInquiryAvailability = initialData.pdfInquiryAvailability
        return .none
    }

    // WHY: importing is I/O and therefore returns a result action instead of mutating state around file operations.
    private func reducePDFFileImportRequested(
        sourceURL: URL,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        .run { dispatch in
            let importedPDFFile: ImportedPDFFile? = environment.storedPDFFileClient.importPDFFile(sourceURL)
            dispatch(.pdfFileImported(importedPDFFile))
        }
    }

    // WHY: selection clears document-derived state immediately while file resolution remains an injected effect.
    private func reducePDFFileSelectionChanged(
        identifier: UUID?,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let identifier else { return reducePDFFileDeselected(state: &state) }
        guard let importedPDFFile: ImportedPDFFile = findImportedPDFFile(identifier: identifier, state: state) else { return .none }
        prepareSelectedPDFFile(identifier: identifier, state: &state)
        return .merge([
            .cancel(identifier: CancelIdentifier.pdfInquiry),
            reduceSelectedPDFFileResolution(importedPDFFile: importedPDFFile, state: state, environment: environment)
        ])
    }

    // WHY: deselection invalidates every value and effect derived from the former document in one transition.
    private func reducePDFFileDeselected(state: inout AppState) -> Effect<AppAction> {
        clearSelectedPDFFile(state: &state)
        return .cancel(identifier: CancelIdentifier.pdfInquiry)
    }

    // WHY: destructive storage work receives an immutable record while state removal remains synchronous and observable.
    private func reduceImportedPDFFileRemovalRequested(
        identifier: UUID,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let importedPDFFile: ImportedPDFFile = findImportedPDFFile(identifier: identifier, state: state) else { return .none }
        let isSelectedPDFFile: Bool = state.selectedPDFFileIdentifier == identifier
        removeImportedPDFFile(identifier: identifier, state: &state)
        return .merge([
            reduceStoredPDFFileDeletion(importedPDFFile: importedPDFFile, environment: environment),
            reducePersistPDFFiles(state: state, environment: environment),
            isSelectedPDFFile ? .cancel(identifier: CancelIdentifier.pdfInquiry) : .none
        ])
    }

    // WHY: revealing a stored file is a platform consequence represented by the originating action's effect.
    private func reduceImportedPDFFileRevealRequested(
        identifier: UUID,
        state: AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let importedPDFFile: ImportedPDFFile = findImportedPDFFile(identifier: identifier, state: state) else { return .none }
        return .run { _ in environment.storedPDFFileClient.revealStoredPDFFile(importedPDFFile) }
    }

    // WHY: saved reading progress updates the selected record and persists the completed state snapshot.
    private func reduceReadingPositionChanged(
        position: PDFScrollPosition,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return .none }
        updateReadingPosition(position, identifier: identifier, date: environment.currentDate(), state: &state)
        return reducePersistPDFFiles(state: state, environment: environment)
    }

    // WHY: bookmark toggle semantics and persistence must be one reducer-owned state transition.
    private func reduceBookmarkToggled(
        pageIndex: Int,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return .none }
        toggleBookmark(pageIndex: pageIndex, identifier: identifier, state: &state)
        return reducePersistPDFFiles(state: state, environment: environment)
    }

    // WHY: explicit bookmark removal changes only the selected record before persisting the new snapshot.
    private func reduceBookmarkRemovalRequested(
        pageIndex: Int,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return .none }
        removeBookmark(pageIndex: pageIndex, identifier: identifier, state: &state)
        return reducePersistPDFFiles(state: state, environment: environment)
    }

    // WHY: comment normalization is a domain rule shared by every source of bookmark edits.
    private func reduceBookmarkCommentChanged(
        pageIndex: Int,
        comment: String?,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return .none }
        let normalizedComment: String? = normalizeBookmarkComment(comment)
        updateBookmarkComment(pageIndex: pageIndex, comment: normalizedComment, identifier: identifier, state: &state)
        return reducePersistPDFFiles(state: state, environment: environment)
    }

    // WHY: empty questions never become recorded requests or trigger model work.
    private func reducePDFQuestionSubmitted(
        question: String,
        pageRange: PDFPageRange?,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        let normalizedQuestion: String = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { return .none }
        return reducePDFInquiryRequested(question: normalizedQuestion, pageRange: pageRange, state: &state, environment: environment)
    }

    // WHY: retry reuses the last immutable person request so scope and wording remain auditable.
    private func reducePDFInquiryRetryRequested(
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let entry: PDFInquiryEntry = state.pdfInquiryEntries.last(where: { $0.author == .person }) else { return .none }
        return reducePDFInquiryRequested(question: entry.text, pageRange: entry.pageRange, state: &state, environment: environment)
    }

    // WHY: cancellation updates observable phase and terminates the identified task through one action.
    private func reducePDFInquiryCancellationRequested(state: inout AppState) -> Effect<AppAction> {
        state.pdfInquiryPhase = .idle
        state.pdfInquiryRequestIdentifier = nil
        return .cancel(identifier: CancelIdentifier.pdfInquiry)
    }

    // WHY: appearance changes are optimistic while persistence mirrors the resulting setting through an effect.
    private func reduceAppearanceSelected(
        appearanceTheme: AppearanceTheme,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        state.appearanceTheme = appearanceTheme
        return .run { _ in environment.appearanceClient.persistAppearanceTheme(appearanceTheme) }
    }

    // WHY: provider changes invalidate active work before availability is recalculated for the new configuration.
    private func reducePDFAnswerProviderSelected(
        provider: PDFAnswerProvider,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        state.pdfAnswerProvider = provider
        state.pdfInquiryPhase = .idle
        state.pdfInquiryRequestIdentifier = nil
        return .merge([
            .cancel(identifier: CancelIdentifier.pdfInquiry),
            .run { _ in environment.pdfAnswerConfigurationClient.persistPDFAnswerProvider(provider) },
            reducePDFInquiryAvailabilityCheck(state: state, environment: environment)
        ])
    }

    // WHY: path normalization gives persistence and availability checks one canonical executable location.
    private func reduceCodexExecutablePathChanged(
        executablePath: String,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        let normalizedExecutablePath: String = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        state.codexExecutablePath = normalizedExecutablePath
        let availabilityEffect: Effect<AppAction> = state.pdfAnswerProvider == .localCodex
            ? reducePDFInquiryAvailabilityCheck(state: state, environment: environment)
            : .none
        return .merge([
            .run { _ in environment.pdfAnswerConfigurationClient.persistCodexExecutablePath(normalizedExecutablePath) },
            availabilityEffect
        ])
    }

    // WHY: successful import publication waits until file copying and metadata construction finish.
    private func reducePDFFileImported(
        importedPDFFile: ImportedPDFFile?,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard let importedPDFFile else { return .none }
        state.importedPDFFiles.append(importedPDFFile)
        state.isFileImporterPresented = false
        return reducePersistPDFFiles(state: state, environment: environment)
    }

    // WHY: asynchronous resolution is accepted only while its document remains selected.
    private func reduceSelectedPDFFileResolved(
        identifier: UUID,
        fileURL: URL?,
        availability: PDFInquiryAvailability,
        state: inout AppState
    ) -> Effect<AppAction> {
        guard state.selectedPDFFileIdentifier == identifier else { return .none }
        state.selectedPDFFileURL = fileURL
        state.isSelectedPDFFileMissing = fileURL == nil
        state.pdfInquiryAvailability = availability
        return .none
    }

    // WHY: availability results include their configuration so stale checks cannot overwrite newer settings.
    private func reducePDFInquiryAvailabilityChecked(
        availability: PDFInquiryAvailability,
        provider: PDFAnswerProvider,
        codexExecutablePath: String,
        state: inout AppState
    ) -> Effect<AppAction> {
        guard state.pdfAnswerProvider == provider else { return .none }
        guard state.codexExecutablePath == codexExecutablePath else { return .none }
        state.pdfInquiryAvailability = availability
        return .none
    }

    // WHY: extraction completion advances only the request that still owns the inquiry lifecycle.
    private func reducePDFPageContentsExtracted(
        requestIdentifier: UUID,
        question: String,
        pageRange: PDFPageRange?,
        pageContents: [PDFPageContent],
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard state.pdfInquiryRequestIdentifier == requestIdentifier else { return .none }
        guard pageRange == nil || pageContents.contains(where: { !$0.text.isEmpty }) else {
            return reducePDFInquiryFailed(requestIdentifier: requestIdentifier, failure: .noReadableText, state: &state)
        }
        state.pdfInquiryPhase = .generating(pageRange)
        return reducePDFResponseGeneration(
            requestIdentifier: requestIdentifier,
            question: question,
            pageRange: pageRange,
            pageContents: pageContents,
            state: state,
            environment: environment
        )
    }

    // WHY: a generated response is published only if its request still owns the current lifecycle.
    private func reducePDFInquiryResponseGenerated(
        requestIdentifier: UUID,
        responseIdentifier: UUID,
        pageRange: PDFPageRange?,
        response: PDFGeneratedResponse,
        state: inout AppState
    ) -> Effect<AppAction> {
        guard state.pdfInquiryRequestIdentifier == requestIdentifier else { return .none }
        state.pdfInquiryEntries.append(makePDFInquiryResponseEntry(
            response: response,
            pageRange: pageRange,
            identifier: responseIdentifier
        ))
        state.pdfInquiryPhase = .idle
        state.pdfInquiryRequestIdentifier = nil
        return .none
    }

    // WHY: terminal failures share one guarded transition so superseded requests cannot publish errors.
    private func reducePDFInquiryFailed(
        requestIdentifier: UUID?,
        failure: PDFInquiryFailure,
        state: inout AppState
    ) -> Effect<AppAction> {
        guard requestIdentifier == nil || state.pdfInquiryRequestIdentifier == requestIdentifier else { return .none }
        state.pdfInquiryPhase = .failed(failure)
        state.pdfInquiryRequestIdentifier = nil
        return .none
    }

    // WHY: request validation and lifecycle initialization are centralized before any extraction begins.
    private func reducePDFInquiryRequested(
        question: String,
        pageRange: PDFPageRange?,
        state: inout AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        guard pageRange == nil || state.selectedPDFFileURL != nil else {
            return reducePDFInquiryFailed(requestIdentifier: nil, failure: .documentUnavailable, state: &state)
        }
        guard state.pdfInquiryAvailability == .available else {
            return reducePDFInquiryAvailabilityCheck(state: state, environment: environment)
        }
        guard isValidPDFPageRangeIfNeeded(pageRange, state: state) else {
            return reducePDFInquiryFailed(requestIdentifier: nil, failure: .invalidPageRange, state: &state)
        }
        let requestIdentifier: UUID = environment.makeUUID()
        state.pdfInquiryEntries.append(makePDFInquiryQuestionEntry(question: question, pageRange: pageRange, identifier: environment.makeUUID()))
        state.pdfInquiryPhase = .extracting(pageRange)
        state.pdfInquiryRequestIdentifier = requestIdentifier
        return .merge([
            .cancel(identifier: CancelIdentifier.pdfInquiry),
            reducePDFPageExtraction(
                requestIdentifier: requestIdentifier,
                question: question,
                pageRange: pageRange,
                documentURL: state.selectedPDFFileURL,
                environment: environment
            )
        ])
    }

    // WHY: file resolution and provider readiness are external reads returned as one consistent selection result.
    private func reduceSelectedPDFFileResolution(
        importedPDFFile: ImportedPDFFile,
        state: AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        let provider: PDFAnswerProvider = state.pdfAnswerProvider
        let codexExecutablePath: String = state.codexExecutablePath
        return .run { dispatch in
            let fileURL: URL? = environment.storedPDFFileClient.resolveStoredFileURL(importedPDFFile.storedFileName)
            let availability: PDFInquiryAvailability = environment.pdfInquiryClient.checkAvailability(provider, codexExecutablePath)
            dispatch(.selectedPDFFileResolved(identifier: importedPDFFile.identifier, fileURL: fileURL, availability: availability))
        }
    }

    // WHY: availability is an injected external capability read whose result carries the checked configuration.
    private func reducePDFInquiryAvailabilityCheck(
        state: AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        let provider: PDFAnswerProvider = state.pdfAnswerProvider
        let codexExecutablePath: String = state.codexExecutablePath
        return .run { dispatch in
            let availability: PDFInquiryAvailability = environment.pdfInquiryClient.checkAvailability(provider, codexExecutablePath)
            dispatch(.pdfInquiryAvailabilityChecked(
                availability: availability,
                provider: provider,
                codexExecutablePath: codexExecutablePath
            ))
        }
    }

    // WHY: extraction remains cancellable I/O and reports either domain content or a stable failure action.
    private func reducePDFPageExtraction(
        requestIdentifier: UUID,
        question: String,
        pageRange: PDFPageRange?,
        documentURL: URL?,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        .run(identifier: CancelIdentifier.pdfInquiry) { dispatch in
            let result: Result<[PDFPageContent], PDFInquiryFailure> = environment.pdfInquiryClient.extractPageContents(pageRange, documentURL)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let pageContents):
                dispatch(.pdfPageContentsExtracted(
                    requestIdentifier: requestIdentifier,
                    question: question,
                    pageRange: pageRange,
                    pageContents: pageContents
                ))
            case .failure(let failure):
                dispatch(.pdfInquiryFailed(requestIdentifier: requestIdentifier, failure: failure))
            }
        }
    }

    // WHY: model generation is long-running work identified by the same request cancellation boundary.
    private func reducePDFResponseGeneration(
        requestIdentifier: UUID,
        question: String,
        pageRange: PDFPageRange?,
        pageContents: [PDFPageContent],
        state: AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        let provider: PDFAnswerProvider = state.pdfAnswerProvider
        let codexExecutablePath: String = state.codexExecutablePath
        return .run(identifier: CancelIdentifier.pdfInquiry) { dispatch in
            let result: Result<PDFGeneratedResponse, PDFInquiryFailure> = await environment.pdfInquiryClient.generateResponse(
                provider,
                codexExecutablePath,
                question,
                pageContents
            )
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let response):
                dispatch(.pdfInquiryResponseGenerated(
                    requestIdentifier: requestIdentifier,
                    responseIdentifier: environment.makeUUID(),
                    pageRange: pageRange,
                    response: response
                ))
            case .failure(let failure):
                dispatch(.pdfInquiryFailed(requestIdentifier: requestIdentifier, failure: failure))
            }
        }
    }

    // WHY: storage deletion is isolated from the already-completed state transition as fire-and-forget work.
    private func reduceStoredPDFFileDeletion(
        importedPDFFile: ImportedPDFFile,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        .run { _ in environment.storedPDFFileClient.deleteStoredPDFFile(importedPDFFile) }
    }

    // WHY: every metadata mutation persists the same post-mutation snapshot that subscribers receive.
    private func reducePersistPDFFiles(
        state: AppState,
        environment: AppEnvironment
    ) -> Effect<AppAction> {
        let importedPDFFiles: [ImportedPDFFile] = state.importedPDFFiles
        return .run { _ in environment.pdfLibraryClient.persistPDFFiles(importedPDFFiles) }
    }

    // WHY: selection initialization prevents values from the previous document surviving asynchronous resolution.
    private func prepareSelectedPDFFile(identifier: UUID, state: inout AppState) {
        state.selectedPDFFileIdentifier = identifier
        state.selectedPDFFileURL = nil
        state.isSelectedPDFFileMissing = false
        state.isAllHighlightsRemovalPending = false
        state.pdfInquiryEntries = []
        state.pdfInquiryPhase = .idle
        state.pdfInquiryRequestIdentifier = nil
    }

    // WHY: deselection and selected-file deletion share the same complete document-state reset.
    private func clearSelectedPDFFile(state: inout AppState) {
        state.selectedPDFFileIdentifier = nil
        state.selectedPDFFileURL = nil
        state.isSelectedPDFFileMissing = false
        state.isAllHighlightsRemovalPending = false
        state.pdfInquiryEntries = []
        state.pdfInquiryPhase = .idle
        state.pdfInquiryRequestIdentifier = nil
    }

    // WHY: removal clears active-document values atomically when the removed record owns them.
    private func removeImportedPDFFile(identifier: UUID, state: inout AppState) {
        state.importedPDFFiles.removeAll { $0.identifier == identifier }
        guard state.selectedPDFFileIdentifier == identifier else { return }
        clearSelectedPDFFile(state: &state)
    }

    // WHY: one mutation keeps the selected record's page, coordinates, and recency synchronized.
    private func updateReadingPosition(
        _ position: PDFScrollPosition,
        identifier: UUID,
        date: Date,
        state: inout AppState
    ) {
        guard let index: Int = findImportedPDFFileIndex(identifier: identifier, state: state) else { return }
        state.importedPDFFiles[index].lastReadPageIndex = position.pageIndex
        state.importedPDFFiles[index].lastReadScrollPosition = position
        state.importedPDFFiles[index].lastReadDate = date
    }

    // WHY: toggle semantics guarantee at most one bookmark for each document page.
    private func toggleBookmark(pageIndex: Int, identifier: UUID, state: inout AppState) {
        guard let index: Int = findImportedPDFFileIndex(identifier: identifier, state: state) else { return }
        guard !hasBookmark(pageIndex: pageIndex, fileIndex: index, state: state) else {
            removeBookmark(pageIndex: pageIndex, fileIndex: index, state: &state)
            return
        }
        addBookmark(pageIndex: pageIndex, fileIndex: index, state: &state)
    }

    // WHY: explicit removal targets one document and delegates the shared page-matching rule.
    private func removeBookmark(pageIndex: Int, identifier: UUID, state: inout AppState) {
        guard let index: Int = findImportedPDFFileIndex(identifier: identifier, state: state) else { return }
        removeBookmark(pageIndex: pageIndex, fileIndex: index, state: &state)
    }

    // WHY: a dedicated predicate keeps bookmark matching out of the reducer's mutation flow.
    private func hasBookmark(pageIndex: Int, fileIndex: Int, state: AppState) -> Bool {
        state.importedPDFFiles[fileIndex].bookmarks.contains { $0.pageIndex == pageIndex }
    }

    // WHY: one insertion path preserves ascending page order after every toggle.
    private func addBookmark(pageIndex: Int, fileIndex: Int, state: inout AppState) {
        state.importedPDFFiles[fileIndex].bookmarks.append(PDFPageBookmark(pageIndex: pageIndex, comment: nil))
        state.importedPDFFiles[fileIndex].bookmarks.sort { $0.pageIndex < $1.pageIndex }
    }

    // WHY: toggle and explicit deletion use an identical bookmark matching rule.
    private func removeBookmark(pageIndex: Int, fileIndex: Int, state: inout AppState) {
        state.importedPDFFiles[fileIndex].bookmarks.removeAll { $0.pageIndex == pageIndex }
    }

    // WHY: optional comments use one whitespace rule so empty notes never become persisted content.
    private func normalizeBookmarkComment(_ comment: String?) -> String? {
        guard let trimmedComment: String = comment?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return trimmedComment.isEmpty ? nil : trimmedComment
    }

    // WHY: comment edits require an existing bookmark and never create an implicit page marker.
    private func updateBookmarkComment(
        pageIndex: Int,
        comment: String?,
        identifier: UUID,
        state: inout AppState
    ) {
        guard let fileIndex: Int = findImportedPDFFileIndex(identifier: identifier, state: state) else { return }
        guard let bookmarkIndex: Int = findBookmarkIndex(pageIndex: pageIndex, fileIndex: fileIndex, state: state) else { return }
        state.importedPDFFiles[fileIndex].bookmarks[bookmarkIndex].comment = comment
    }

    // WHY: bookmark lookup has one discoverable condition for comment mutation.
    private func findBookmarkIndex(pageIndex: Int, fileIndex: Int, state: AppState) -> Int? {
        state.importedPDFFiles[fileIndex].bookmarks.firstIndex { $0.pageIndex == pageIndex }
    }

    // WHY: identifier lookup has one definition for every document-owned state transition.
    private func findImportedPDFFile(identifier: UUID, state: AppState) -> ImportedPDFFile? {
        state.importedPDFFiles.first { $0.identifier == identifier }
    }

    // WHY: index lookup centralizes the identity rule used by all in-place record mutations.
    private func findImportedPDFFileIndex(identifier: UUID, state: AppState) -> Int? {
        state.importedPDFFiles.firstIndex { $0.identifier == identifier }
    }

    // WHY: page-scoped inquiries must fit entirely inside the selected document's persisted page count.
    private func isValidPDFPageRange(_ pageRange: PDFPageRange, state: AppState) -> Bool {
        guard let identifier: UUID = state.selectedPDFFileIdentifier else { return false }
        guard let pageCount: Int = findImportedPDFFile(identifier: identifier, state: state)?.totalPageCount else { return false }
        return pageRange.lowerPageIndex >= 0
            && pageRange.upperPageIndex < pageCount
            && pageRange.lowerPageIndex <= pageRange.upperPageIndex
    }

    // WHY: general questions intentionally bypass document-range validation.
    private func isValidPDFPageRangeIfNeeded(_ pageRange: PDFPageRange?, state: AppState) -> Bool {
        guard let pageRange else { return true }
        return isValidPDFPageRange(pageRange, state: state)
    }

    // WHY: questions are recorded before work starts so their original request remains visible after failure.
    private func makePDFInquiryQuestionEntry(
        question: String,
        pageRange: PDFPageRange?,
        identifier: UUID
    ) -> PDFInquiryEntry {
        PDFInquiryEntry(
            id: identifier,
            author: .person,
            text: question,
            pageRange: pageRange,
            citedPageIndices: []
        )
    }

    // WHY: citations outside the requested range are discarded before becoming trusted source indices.
    private func makePDFInquiryResponseEntry(
        response: PDFGeneratedResponse,
        pageRange: PDFPageRange?,
        identifier: UUID
    ) -> PDFInquiryEntry {
        let citedPageIndices: [Int] = pageRange.map { response.citedPageIndices.filter($0.pageIndices.contains) } ?? []
        return PDFInquiryEntry(
            id: identifier,
            author: .model,
            text: response.answer,
            pageRange: pageRange,
            citedPageIndices: citedPageIndices
        )
    }
}
