import AppKit
import Foundation
import PDFKit

extension AppEnvironment {
    // WHY: the composition root needs one production dependency graph while reducers depend only on closure clients.
    static func live() -> AppEnvironment {
        let pdfLibraryRepository: PDFLibraryRepository = PDFLibraryRepository()
        let pdfFileStorageService: PDFFileStorageService = PDFFileStorageService()
        let pdfThumbnailService: PDFThumbnailService = PDFThumbnailService()
        let pdfThumbnailRepository: PDFThumbnailRepository = PDFThumbnailRepository()
        let appearanceRepository: AppearanceRepository = AppearanceRepository()
        let pdfAnswerConfigurationRepository: PDFAnswerConfigurationRepository = PDFAnswerConfigurationRepository()
        let pdfPageContentExtractor: PDFPageContentExtractor = PDFPageContentExtractor()
        let applePDFAnswerGenerator: any PDFAnswerGenerating = AppleFoundationModelPDFAnswerGenerator()

        return AppEnvironment(
            pdfLibraryClient: makePDFLibraryClient(repository: pdfLibraryRepository),
            storedPDFFileClient: makeStoredPDFFileClient(
                storageService: pdfFileStorageService,
                thumbnailService: pdfThumbnailService,
                thumbnailRepository: pdfThumbnailRepository
            ),
            appearanceClient: makeAppearanceClient(repository: appearanceRepository),
            pdfAnswerConfigurationClient: makePDFAnswerConfigurationClient(repository: pdfAnswerConfigurationRepository),
            pdfInquiryClient: makePDFInquiryClient(
                pageContentExtractor: pdfPageContentExtractor,
                applePDFAnswerGenerator: applePDFAnswerGenerator
            ),
            makeUUID: UUID.init,
            currentDate: Date.init
        )
    }

    // WHY: repository methods are boxed so the reducer never reaches persistence implementations directly.
    private static func makePDFLibraryClient(repository: PDFLibraryRepository) -> PDFLibraryClient {
        PDFLibraryClient(
            loadSavedPDFFiles: repository.loadSavedPDFFiles,
            persistPDFFiles: repository.persistPDFFiles
        )
    }

    // WHY: file import and deletion coordinate app-owned files and thumbnails behind one injected boundary.
    private static func makeStoredPDFFileClient(
        storageService: PDFFileStorageService,
        thumbnailService: PDFThumbnailService,
        thumbnailRepository: PDFThumbnailRepository
    ) -> StoredPDFFileClient {
        StoredPDFFileClient(
            migrateLegacyStoredFiles: storageService.migrateLegacyStoredFiles,
            importPDFFile: { sourceURL in
                makeImportedPDFFile(
                    sourceURL: sourceURL,
                    storageService: storageService,
                    thumbnailService: thumbnailService,
                    thumbnailRepository: thumbnailRepository
                )
            },
            resolveStoredFileURL: storageService.resolveStoredFileURL,
            deleteStoredPDFFile: { importedPDFFile in
                storageService.deleteStoredFile(storedFileName: importedPDFFile.storedFileName)
                thumbnailRepository.deleteThumbnail(for: importedPDFFile.identifier)
            },
            revealStoredPDFFile: { importedPDFFile in
                guard let fileURL: URL = storageService.resolveStoredFileURL(storedFileName: importedPDFFile.storedFileName) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
        )
    }

    // WHY: appearance persistence remains replaceable without exposing UserDefaults to state code.
    private static func makeAppearanceClient(repository: AppearanceRepository) -> AppearanceClient {
        AppearanceClient(
            loadAppearanceTheme: repository.loadAppearanceTheme,
            persistAppearanceTheme: repository.persistAppearanceTheme
        )
    }

    // WHY: answer-provider persistence is grouped by its repository contract rather than individual storage details.
    private static func makePDFAnswerConfigurationClient(
        repository: PDFAnswerConfigurationRepository
    ) -> PDFAnswerConfigurationClient {
        PDFAnswerConfigurationClient(
            loadPDFAnswerProvider: repository.loadPDFAnswerProvider,
            persistPDFAnswerProvider: repository.persistPDFAnswerProvider,
            loadCodexExecutablePath: repository.loadCodexExecutablePath,
            persistCodexExecutablePath: repository.persistCodexExecutablePath
        )
    }

    // WHY: extraction and generation implementations stay behind one inquiry capability used only by effects.
    private static func makePDFInquiryClient(
        pageContentExtractor: PDFPageContentExtractor,
        applePDFAnswerGenerator: any PDFAnswerGenerating
    ) -> PDFInquiryClient {
        PDFInquiryClient(
            checkAvailability: { provider, executablePath in
                makePDFAnswerGenerator(
                    provider: provider,
                    executablePath: executablePath,
                    applePDFAnswerGenerator: applePDFAnswerGenerator
                ).checkAvailability()
            },
            extractPageContents: { pageRange, documentURL in
                makePageContentExtractionResult(
                    pageRange: pageRange,
                    documentURL: documentURL,
                    pageContentExtractor: pageContentExtractor
                )
            },
            generateResponse: { provider, executablePath, question, pageContents in
                await makePDFGenerationResult(
                    provider: provider,
                    executablePath: executablePath,
                    question: question,
                    pageContents: pageContents,
                    applePDFAnswerGenerator: applePDFAnswerGenerator
                )
            }
        )
    }

    // WHY: security-scoped access and metadata derivation must complete before an imported record is published.
    private static func makeImportedPDFFile(
        sourceURL: URL,
        storageService: PDFFileStorageService,
        thumbnailService: PDFThumbnailService,
        thumbnailRepository: PDFThumbnailRepository
    ) -> ImportedPDFFile? {
        let isAccessGranted: Bool = sourceURL.startAccessingSecurityScopedResource()
        defer { sourceURL.stopAccessingSecurityScopedResource() }
        print("[StoredPDFFileClient] startAccessingSecurityScopedResource: \(isAccessGranted)")
        guard let storedFileName: String = storageService.copyPDFFileIntoStorage(from: sourceURL) else { return nil }
        let identifier: UUID = UUID()
        let storedFileURL: URL? = storageService.resolveStoredFileURL(storedFileName: storedFileName)
        return ImportedPDFFile(
            identifier: identifier,
            displayName: sourceURL.deletingPathExtension().lastPathComponent,
            storedFileName: storedFileName,
            thumbnailFileURLAbsoluteString: makeThumbnailURLString(
                storedFileURL: storedFileURL,
                identifier: identifier,
                thumbnailService: thumbnailService,
                thumbnailRepository: thumbnailRepository
            ),
            importedDate: Date(),
            totalPageCount: makePDFPageCount(storedFileURL: storedFileURL)
        )
    }

    // WHY: optional thumbnail generation must not turn an otherwise valid file import into a failure.
    private static func makeThumbnailURLString(
        storedFileURL: URL?,
        identifier: UUID,
        thumbnailService: PDFThumbnailService,
        thumbnailRepository: PDFThumbnailRepository
    ) -> String? {
        guard let storedFileURL else { return nil }
        let thumbnailImage: NSImage? = thumbnailService.generateFirstPageThumbnail(
            for: storedFileURL,
            thumbnailSize: CGSize(width: 160, height: 220)
        )
        return thumbnailImage.flatMap { thumbnailRepository.saveThumbnail($0, for: identifier) }?.absoluteString
    }

    // WHY: page count is derived once during import so library progress does not repeatedly open the PDF.
    private static func makePDFPageCount(storedFileURL: URL?) -> Int? {
        guard let storedFileURL else { return nil }
        return PDFDocument(url: storedFileURL)?.pageCount
    }

    // WHY: provider selection has one definition for both capability checks and response generation.
    private static func makePDFAnswerGenerator(
        provider: PDFAnswerProvider,
        executablePath: String,
        applePDFAnswerGenerator: any PDFAnswerGenerating
    ) -> any PDFAnswerGenerating {
        switch provider {
        case .appleIntelligence:
            return applePDFAnswerGenerator
        case .localCodex:
            return LocalCodexPDFAnswerGenerator(executablePath: executablePath)
        }
    }

    // WHY: extraction errors are translated at the data boundary into stable domain failures.
    private static func makePageContentExtractionResult(
        pageRange: PDFPageRange?,
        documentURL: URL?,
        pageContentExtractor: PDFPageContentExtractor
    ) -> Result<[PDFPageContent], PDFInquiryFailure> {
        guard let pageRange, let documentURL else { return .success([]) }
        do {
            return .success(try pageContentExtractor.extractPageContents(documentURL: documentURL, pageRange: pageRange))
        } catch PDFPageContentExtractor.ExtractionError.documentUnavailable {
            return .failure(.documentUnavailable)
        } catch PDFPageContentExtractor.ExtractionError.invalidPageRange {
            return .failure(.invalidPageRange)
        } catch {
            return .failure(.generationFailed)
        }
    }

    // WHY: provider-specific thrown errors become one stable failure contract for the reducer.
    private static func makePDFGenerationResult(
        provider: PDFAnswerProvider,
        executablePath: String,
        question: String,
        pageContents: [PDFPageContent],
        applePDFAnswerGenerator: any PDFAnswerGenerating
    ) async -> Result<PDFGeneratedResponse, PDFInquiryFailure> {
        do {
            let generator: any PDFAnswerGenerating = makePDFAnswerGenerator(
                provider: provider,
                executablePath: executablePath,
                applePDFAnswerGenerator: applePDFAnswerGenerator
            )
            return .success(try await generator.generateResponse(question: question, pageContents: pageContents))
        } catch {
            return .failure(.generationFailed)
        }
    }
}
