import Foundation
import Darwin

/// Also used by G0's explicit synthetic text handoff. No automatic cleanup.
public struct TextDocumentStore: TextDocumentStoring {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func createDocument(text: String) throws -> URL {
        let manager = FileManager.default
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        let destination = directory.appendingPathComponent("\(UUID().uuidString).txt")
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
            guard descriptor >= 0 else { throw ScanFailure.fileWriteFailed }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? handle.close(); try? manager.removeItem(at: temporary) }
            try handle.write(contentsOf: Data(text.utf8))
            try handle.synchronize()
            try handle.close()
            try manager.moveItem(at: temporary, to: destination)
            return destination
        } catch { throw ScanFailure.fileWriteFailed }
    }
}
