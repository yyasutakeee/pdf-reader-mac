import Foundation

struct AppEnvironment {
    var pdfLibraryClient: PDFLibraryClient
    var storedPDFFileClient: StoredPDFFileClient
    var appearanceClient: AppearanceClient
    var pdfAnswerConfigurationClient: PDFAnswerConfigurationClient
    var pdfInquiryClient: PDFInquiryClient
    var makeUUID: () -> UUID
    var currentDate: () -> Date
}
