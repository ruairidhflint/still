import Foundation

public struct WritingPosition: Codable, Equatable {
    public var selection: NSRange
    public var scrollOffset: Double

    public init(selection: NSRange, scrollOffset: Double) {
        self.selection = selection
        self.scrollOffset = scrollOffset
    }

    /// A file may have changed elsewhere since it was last open. Keep the caret on a character boundary.
    public func selection(in text: String) -> NSRange {
        let source = text as NSString
        let start = min(max(0, selection.location), source.length)
        let length = min(max(0, selection.length), source.length - start)
        guard start < source.length else { return NSRange(location: source.length, length: 0) }
        if length == 0 {
            return NSRange(location: source.rangeOfComposedCharacterSequence(at: start).location, length: 0)
        }
        return source.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: length))
    }

    public func scrollOffset(maximum: Double) -> Double {
        guard scrollOffset.isFinite else { return 0 }
        return min(max(0, scrollOffset), max(0, maximum))
    }
}

/// Only navigation metadata is stored here. Unsaved text belongs to the independent recovery store.
public struct WritingSession: Codable, Equatable {
    public var filePath: String?
    public var recoveryID: UUID
    public var position: WritingPosition

    public init(filePath: String?, recoveryID: UUID, position: WritingPosition) {
        self.filePath = filePath
        self.recoveryID = recoveryID
        self.position = position
    }

    public func matches(_ draft: RecoveredDraft) -> Bool {
        recoveryID == draft.id || (filePath != nil && filePath == draft.originalPath)
    }
}

public struct SessionStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() -> WritingSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WritingSession.self, from: data)
    }

    public func save(_ session: WritingSession) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: url, options: .atomic)
    }
}
