import Foundation

public struct TextFile {
    public var text: String
    public var hasUTF8BOM: Bool
    public init(text: String = "", hasUTF8BOM: Bool = false) {
        self.text = text; self.hasUTF8BOM = hasUTF8BOM
    }
    public init(data: Data) throws {
        hasUTF8BOM = data.starts(with: [0xef, 0xbb, 0xbf])
        let body = hasUTF8BOM ? data.dropFirst(3) : data[...]
        guard let value = String(data: body, encoding: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadInapplicableStringEncoding.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "This file isn’t UTF-8 text.",
                                     NSLocalizedRecoverySuggestionErrorKey: "Save a UTF-8 copy before opening it in Still. The original file has not been changed."])
        }
        text = value
    }
    public var data: Data {
        var result = Data()
        if hasUTF8BOM { result.append(contentsOf: [0xef, 0xbb, 0xbf]) }
        result.append(contentsOf: text.utf8)
        return result
    }
}
