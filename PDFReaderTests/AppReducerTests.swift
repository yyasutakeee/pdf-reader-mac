import Foundation
import Testing
@testable import PDFReader

@Suite("AppReducer")
struct AppReducerTests {
    @Test("ファイルインポーター表示要求は表示状態だけを変更する")
    // WHY: this proves a presentation event cannot accidentally mutate unrelated domain state.
    func fileImporterPresentationRequestedChangesOnlyPresentationState() {
        let environment: AppEnvironment = AppEnvironment(
            pdfLibraryClient: PDFLibraryClient(loadSavedPDFFiles: { [] }, persistPDFFiles: { _ in }),
            storedPDFFileClient: StoredPDFFileClient(
                migrateLegacyStoredFiles: {},
                importPDFFile: { _ in nil },
                resolveStoredFileURL: { _ in nil },
                deleteStoredPDFFile: { _ in },
                revealStoredPDFFile: { _ in }
            ),
            appearanceClient: AppearanceClient(loadAppearanceTheme: { .system }, persistAppearanceTheme: { _ in }),
            pdfAnswerConfigurationClient: PDFAnswerConfigurationClient(
                loadPDFAnswerProvider: { .appleIntelligence },
                persistPDFAnswerProvider: { _ in },
                loadCodexExecutablePath: { "" },
                persistCodexExecutablePath: { _ in }
            ),
            pdfInquiryClient: PDFInquiryClient(
                checkAvailability: { _, _ in .unavailable },
                extractPageContents: { _, _ in .success([]) },
                generateResponse: { _, _, _, _ in .failure(.generationFailed) }
            ),
            makeUUID: UUID.init,
            currentDate: Date.init
        )
        let reducer: AppReducer = AppReducer()
        var state: AppState = AppState()
        var expectedState: AppState = AppState()
        expectedState.isFileImporterPresented = true

        _ = reducer.reduce(into: &state, action: .fileImporterPresentationRequested, environment: environment)

        #expect(state == expectedState)
    }

    @Test("PDF選択は以前の文書に由来する問い合わせ状態をすべて消去する")
    // WHY: document switching must not let request state or content from the previous PDF cross the boundary.
    func pdfFileSelectionChangedClearsPreviousDocumentState() {
        let selectedIdentifier: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let previousRequestIdentifier: UUID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let importedPDFFile: ImportedPDFFile = makeImportedPDFFile(identifier: selectedIdentifier)
        let environment: AppEnvironment = AppEnvironment(
            pdfLibraryClient: PDFLibraryClient(loadSavedPDFFiles: { [] }, persistPDFFiles: { _ in }),
            storedPDFFileClient: StoredPDFFileClient(
                migrateLegacyStoredFiles: {},
                importPDFFile: { _ in nil },
                resolveStoredFileURL: { _ in nil },
                deleteStoredPDFFile: { _ in },
                revealStoredPDFFile: { _ in }
            ),
            appearanceClient: AppearanceClient(loadAppearanceTheme: { .system }, persistAppearanceTheme: { _ in }),
            pdfAnswerConfigurationClient: PDFAnswerConfigurationClient(
                loadPDFAnswerProvider: { .appleIntelligence },
                persistPDFAnswerProvider: { _ in },
                loadCodexExecutablePath: { "" },
                persistCodexExecutablePath: { _ in }
            ),
            pdfInquiryClient: PDFInquiryClient(
                checkAvailability: { _, _ in .unavailable },
                extractPageContents: { _, _ in .success([]) },
                generateResponse: { _, _, _, _ in .failure(.generationFailed) }
            ),
            makeUUID: UUID.init,
            currentDate: Date.init
        )
        let reducer: AppReducer = AppReducer()
        var state: AppState = AppState(
            importedPDFFiles: [importedPDFFile],
            selectedPDFFileURL: URL(fileURLWithPath: "/previous.pdf"),
            isSelectedPDFFileMissing: true,
            isAllHighlightsRemovalPending: true,
            pdfInquiryEntries: [PDFInquiryEntry(
                id: previousRequestIdentifier,
                author: .person,
                text: "Previous",
                pageRange: nil,
                citedPageIndices: []
            )],
            pdfInquiryPhase: .generating(nil),
            pdfInquiryRequestIdentifier: previousRequestIdentifier
        )
        var expectedState: AppState = AppState(importedPDFFiles: [importedPDFFile])
        expectedState.selectedPDFFileIdentifier = selectedIdentifier

        _ = reducer.reduce(into: &state, action: .pdfFileSelectionChanged(selectedIdentifier), environment: environment)

        #expect(state == expectedState)
    }

    @Test("読書位置変更は選択中PDFの位置と更新日時を同じ状態遷移で保存する")
    // WHY: the complete record comparison protects every persisted field from unintended position-update writes.
    func readingPositionChangedUpdatesSelectedPDFRecord() {
        let selectedIdentifier: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let currentDate: Date = Date(timeIntervalSince1970: 1_000)
        let position: PDFScrollPosition = PDFScrollPosition(pageIndex: 4, pagePointX: 12, pagePointY: 24, zoomScale: 1.5)
        let importedPDFFile: ImportedPDFFile = makeImportedPDFFile(identifier: selectedIdentifier)
        let environment: AppEnvironment = AppEnvironment(
            pdfLibraryClient: PDFLibraryClient(loadSavedPDFFiles: { [] }, persistPDFFiles: { _ in }),
            storedPDFFileClient: StoredPDFFileClient(
                migrateLegacyStoredFiles: {},
                importPDFFile: { _ in nil },
                resolveStoredFileURL: { _ in nil },
                deleteStoredPDFFile: { _ in },
                revealStoredPDFFile: { _ in }
            ),
            appearanceClient: AppearanceClient(loadAppearanceTheme: { .system }, persistAppearanceTheme: { _ in }),
            pdfAnswerConfigurationClient: PDFAnswerConfigurationClient(
                loadPDFAnswerProvider: { .appleIntelligence },
                persistPDFAnswerProvider: { _ in },
                loadCodexExecutablePath: { "" },
                persistCodexExecutablePath: { _ in }
            ),
            pdfInquiryClient: PDFInquiryClient(
                checkAvailability: { _, _ in .unavailable },
                extractPageContents: { _, _ in .success([]) },
                generateResponse: { _, _, _, _ in .failure(.generationFailed) }
            ),
            makeUUID: UUID.init,
            currentDate: { currentDate }
        )
        let reducer: AppReducer = AppReducer()
        var state: AppState = AppState(
            importedPDFFiles: [importedPDFFile],
            selectedPDFFileIdentifier: selectedIdentifier
        )
        var expectedPDFFile: ImportedPDFFile = importedPDFFile
        expectedPDFFile.lastReadPageIndex = position.pageIndex
        expectedPDFFile.lastReadScrollPosition = position
        expectedPDFFile.lastReadDate = currentDate
        let expectedState: AppState = AppState(
            importedPDFFiles: [expectedPDFFile],
            selectedPDFFileIdentifier: selectedIdentifier
        )

        _ = reducer.reduce(into: &state, action: .readingPositionChanged(position), environment: environment)

        #expect(state == expectedState)
    }

    @Test("質問送信は要求内容と抽出フェーズを一つの状態スナップショットへ記録する")
    // WHY: request initialization must be complete before asynchronous extraction can report a result.
    func pdfQuestionSubmittedRecordsRequestAndExtractionPhase() {
        let selectedIdentifier: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let requestIdentifier: UUID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let pageRange: PDFPageRange = PDFPageRange(lowerPageIndex: 0, upperPageIndex: 1)
        let selectedURL: URL = URL(fileURLWithPath: "/selected.pdf")
        let importedPDFFile: ImportedPDFFile = makeImportedPDFFile(identifier: selectedIdentifier)
        let environment: AppEnvironment = AppEnvironment(
            pdfLibraryClient: PDFLibraryClient(loadSavedPDFFiles: { [] }, persistPDFFiles: { _ in }),
            storedPDFFileClient: StoredPDFFileClient(
                migrateLegacyStoredFiles: {},
                importPDFFile: { _ in nil },
                resolveStoredFileURL: { _ in nil },
                deleteStoredPDFFile: { _ in },
                revealStoredPDFFile: { _ in }
            ),
            appearanceClient: AppearanceClient(loadAppearanceTheme: { .system }, persistAppearanceTheme: { _ in }),
            pdfAnswerConfigurationClient: PDFAnswerConfigurationClient(
                loadPDFAnswerProvider: { .appleIntelligence },
                persistPDFAnswerProvider: { _ in },
                loadCodexExecutablePath: { "" },
                persistCodexExecutablePath: { _ in }
            ),
            pdfInquiryClient: PDFInquiryClient(
                checkAvailability: { _, _ in .unavailable },
                extractPageContents: { _, _ in .success([]) },
                generateResponse: { _, _, _, _ in .failure(.generationFailed) }
            ),
            makeUUID: { requestIdentifier },
            currentDate: Date.init
        )
        let reducer: AppReducer = AppReducer()
        var state: AppState = AppState(
            importedPDFFiles: [importedPDFFile],
            selectedPDFFileIdentifier: selectedIdentifier,
            selectedPDFFileURL: selectedURL,
            pdfInquiryAvailability: .available
        )
        let inquiryEntry: PDFInquiryEntry = PDFInquiryEntry(
            id: requestIdentifier,
            author: .person,
            text: "What happened?",
            pageRange: pageRange,
            citedPageIndices: []
        )
        let expectedState: AppState = AppState(
            importedPDFFiles: [importedPDFFile],
            selectedPDFFileIdentifier: selectedIdentifier,
            selectedPDFFileURL: selectedURL,
            pdfInquiryEntries: [inquiryEntry],
            pdfInquiryPhase: .extracting(pageRange),
            pdfInquiryAvailability: .available,
            pdfInquiryRequestIdentifier: requestIdentifier
        )

        _ = reducer.reduce(
            into: &state,
            action: .pdfQuestionSubmitted(question: "  What happened?  ", pageRange: pageRange),
            environment: environment
        )

        #expect(state == expectedState)
    }

    @Test("古い問い合わせの回答は現在の状態へ追加されない")
    // WHY: superseded model work may finish late and must never publish into a newer request lifecycle.
    func stalePDFInquiryResponseDoesNotChangeState() {
        let currentRequestIdentifier: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let staleRequestIdentifier: UUID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let responseIdentifier: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let environment: AppEnvironment = AppEnvironment(
            pdfLibraryClient: PDFLibraryClient(loadSavedPDFFiles: { [] }, persistPDFFiles: { _ in }),
            storedPDFFileClient: StoredPDFFileClient(
                migrateLegacyStoredFiles: {},
                importPDFFile: { _ in nil },
                resolveStoredFileURL: { _ in nil },
                deleteStoredPDFFile: { _ in },
                revealStoredPDFFile: { _ in }
            ),
            appearanceClient: AppearanceClient(loadAppearanceTheme: { .system }, persistAppearanceTheme: { _ in }),
            pdfAnswerConfigurationClient: PDFAnswerConfigurationClient(
                loadPDFAnswerProvider: { .appleIntelligence },
                persistPDFAnswerProvider: { _ in },
                loadCodexExecutablePath: { "" },
                persistCodexExecutablePath: { _ in }
            ),
            pdfInquiryClient: PDFInquiryClient(
                checkAvailability: { _, _ in .unavailable },
                extractPageContents: { _, _ in .success([]) },
                generateResponse: { _, _, _, _ in .failure(.generationFailed) }
            ),
            makeUUID: UUID.init,
            currentDate: Date.init
        )
        let reducer: AppReducer = AppReducer()
        let expectedState: AppState = AppState(
            pdfInquiryPhase: .generating(nil),
            pdfInquiryRequestIdentifier: currentRequestIdentifier
        )
        var state: AppState = expectedState

        _ = reducer.reduce(
            into: &state,
            action: .pdfInquiryResponseGenerated(
                requestIdentifier: staleRequestIdentifier,
                responseIdentifier: responseIdentifier,
                pageRange: nil,
                response: PDFGeneratedResponse(answer: "Stale", citedPageIndices: [])
            ),
            environment: environment
        )

        #expect(state == expectedState)
    }

    // WHY: tests need one valid persisted record whose unrelated fields remain stable during state comparisons.
    private func makeImportedPDFFile(identifier: UUID) -> ImportedPDFFile {
        ImportedPDFFile(
            identifier: identifier,
            displayName: "Document",
            storedFileName: "document.pdf",
            thumbnailFileURLAbsoluteString: nil,
            importedDate: Date(timeIntervalSince1970: 100),
            totalPageCount: 10
        )
    }
}
