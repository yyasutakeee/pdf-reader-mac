import Foundation

enum PDFAnswerProvider: String, CaseIterable, Equatable, Sendable {
    case appleIntelligence
    case localCodex
}

struct PDFPageRange: Equatable, Sendable {
    let lowerPageIndex: Int
    let upperPageIndex: Int

    var pageIndices: ClosedRange<Int> {
        lowerPageIndex...upperPageIndex
    }

    var pageNumberDescription: String {
        guard lowerPageIndex != upperPageIndex else { return "p.\(lowerPageIndex + 1)" }
        return "p.\(lowerPageIndex + 1)–\(upperPageIndex + 1)"
    }
}

struct PDFPageContent: Equatable, Sendable {
    let pageIndex: Int
    let text: String
}

struct PDFGeneratedResponse: Equatable, Sendable {
    let answer: String
    let citedPageIndices: [Int]
}

protocol PDFAnswerGenerating {
    func checkAvailability() -> PDFInquiryAvailability
    func generateResponse(question: String, pageContents: [PDFPageContent]) async throws -> PDFGeneratedResponse
}

struct PDFInquiryEntry: Identifiable, Equatable, Sendable {
    enum Author: Equatable, Sendable {
        case person
        case model
    }

    let id: UUID
    let author: Author
    let text: String
    let pageRange: PDFPageRange?
    let citedPageIndices: [Int]
}

enum PDFInquiryAvailability: Equatable, Sendable {
    case available
    case codexExecutableMissing
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedLanguage
    case unavailable
}

enum PDFInquiryFailure: Equatable, Sendable {
    case documentUnavailable
    case invalidPageRange
    case noReadableText
    case generationFailed
}

enum PDFInquiryPhase: Equatable, Sendable {
    case idle
    case extracting(PDFPageRange?)
    case generating(PDFPageRange?)
    case failed(PDFInquiryFailure)
}
