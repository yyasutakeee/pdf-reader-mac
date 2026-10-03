import Foundation

struct PDFLibraryClient {
    var loadSavedPDFFiles: () -> [ImportedPDFFile]
    var persistPDFFiles: ([ImportedPDFFile]) -> Void
}

struct StoredPDFFileClient {
    var migrateLegacyStoredFiles: () -> Void
    var importPDFFile: (URL) -> ImportedPDFFile?
    var resolveStoredFileURL: (String) -> URL?
    var deleteStoredPDFFile: (ImportedPDFFile) -> Void
    var revealStoredPDFFile: (ImportedPDFFile) -> Void
}

struct AppearanceClient {
    var loadAppearanceTheme: () -> AppearanceTheme
    var persistAppearanceTheme: (AppearanceTheme) -> Void
}

struct PDFAnswerConfigurationClient {
    var loadPDFAnswerProvider: () -> PDFAnswerProvider
    var persistPDFAnswerProvider: (PDFAnswerProvider) -> Void
    var loadCodexExecutablePath: () -> String
    var persistCodexExecutablePath: (String) -> Void
}

struct PDFInquiryClient {
    var checkAvailability: (PDFAnswerProvider, String) -> PDFInquiryAvailability
    var extractPageContents: (PDFPageRange?, URL?) -> Result<[PDFPageContent], PDFInquiryFailure>
    var generateResponse: (PDFAnswerProvider, String, String, [PDFPageContent]) async -> Result<PDFGeneratedResponse, PDFInquiryFailure>
}
