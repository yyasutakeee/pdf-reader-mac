import Foundation

struct PDFFileStorageService {
    private let pdfSubdirectoryName = "PDFs"

    private var applicationSupportFolderURL: URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
    }

    // WHY: an app-owned subdirectory keeps library files out of the shared Application Support root,
    // where an unrelated cleanup tool can delete a bare "PDFs" folder it cannot attribute to this app.
    private var storageFolderURL: URL? {
        guard let applicationSupportFolderURL else { return nil }
        return applicationSupportFolderURL
            .appendingPathComponent(applicationStorageFolderName)
            .appendingPathComponent(pdfSubdirectoryName)
    }

    // WHY: files imported before the app-owned layout live one level higher and must still be found.
    private var legacyStorageFolderURL: URL? {
        applicationSupportFolderURL?.appendingPathComponent(pdfSubdirectoryName)
    }

    // WHY: the bundle identifier scopes storage to this app even when several apps share the domain folder.
    private var applicationStorageFolderName: String {
        Bundle.main.bundleIdentifier ?? "PDFReader"
    }

    // WHY: imported security-scoped files must be copied into app-owned storage for later access.
    func copyPDFFileIntoStorage(from sourceFileURL: URL) -> String? {
        guard let folderURL = storageFolderURL else {
            print("[PDFFileStorageService] could not resolve storage folder")
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let storedFileName = UUID().uuidString + ".pdf"
            let destinationFileURL = folderURL.appendingPathComponent(storedFileName)
            try FileManager.default.copyItem(at: sourceFileURL, to: destinationFileURL)
            print("[PDFFileStorageService] copied to: \(destinationFileURL)")
            return storedFileName
        } catch {
            print("[PDFFileStorageService] copy failed: \(error)")
            return nil
        }
    }

    // WHY: persisted metadata stores a portable filename rather than an environment-specific absolute URL.
    func resolveStoredFileURL(storedFileName: String) -> URL? {
        guard let fileURL: URL = storageFolderURL?.appendingPathComponent(storedFileName) else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL
    }

    // WHY: removing library metadata must also release the app-owned PDF file.
    func deleteStoredFile(storedFileName: String) {
        guard let fileURL = resolveStoredFileURL(storedFileName: storedFileName) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // WHY: an existing library keeps opening its documents only if the old location is moved on first launch.
    func migrateLegacyStoredFiles() {
        guard let legacyFolderURL = legacyStorageFolderURL, let folderURL = storageFolderURL else { return }
        guard FileManager.default.fileExists(atPath: legacyFolderURL.path) else { return }
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            for legacyFileName in try FileManager.default.contentsOfDirectory(atPath: legacyFolderURL.path) {
                moveLegacyStoredFile(named: legacyFileName, from: legacyFolderURL, to: folderURL)
            }
            removeLegacyStorageFolderIfEmpty(legacyFolderURL)
        } catch {
            print("[PDFFileStorageService] legacy migration failed: \(error)")
        }
    }

    // WHY: a name already present in the new location is the authoritative copy and must not be overwritten.
    private func moveLegacyStoredFile(named fileName: String, from legacyFolderURL: URL, to folderURL: URL) {
        let destinationFileURL: URL = folderURL.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: destinationFileURL.path) else { return }
        do {
            try FileManager.default.moveItem(at: legacyFolderURL.appendingPathComponent(fileName), to: destinationFileURL)
            print("[PDFFileStorageService] migrated: \(destinationFileURL)")
        } catch {
            print("[PDFFileStorageService] migration of \(fileName) failed: \(error)")
        }
    }

    // WHY: the old folder is removed only once nothing is left, so a failed move never loses a document.
    private func removeLegacyStorageFolderIfEmpty(_ legacyFolderURL: URL) {
        guard let remainingFileNames = try? FileManager.default.contentsOfDirectory(atPath: legacyFolderURL.path) else { return }
        guard remainingFileNames.isEmpty else { return }
        try? FileManager.default.removeItem(at: legacyFolderURL)
    }
}
