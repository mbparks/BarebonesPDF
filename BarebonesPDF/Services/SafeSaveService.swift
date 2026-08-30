import Foundation
import PDFKit

enum SafeSaveError: LocalizedError {
    case couldNotEncode
    case replacementFailed(Error)

    var errorDescription: String? {
        switch self {
        case .couldNotEncode:
            return "The PDF could not be prepared. Nothing was written."
        case .replacementFailed:
            return "The PDF could not be saved. The original file was left unchanged."
        }
    }
}

enum SafeSaveService {
    /// Foundation's atomic write prepares a temporary sibling and replaces the destination
    /// only after the complete payload has been written. This also respects the sandbox
    /// extension granted for an NSSavePanel destination.
    /// SwiftUI's document system provides coordinated atomic writes for normal Save and Save As;
    /// this path is used by standalone exports.
    static func write(document: PDFDocument, to destination: URL) throws {
        guard let data = document.dataRepresentation() else { throw SafeSaveError.couldNotEncode }
        try write(data: data, to: destination)
    }

    static func write(data: Data, to destination: URL) throws {
        do {
            try data.write(to: destination, options: [.atomic])
        } catch {
            throw SafeSaveError.replacementFailed(error)
        }
    }
}
