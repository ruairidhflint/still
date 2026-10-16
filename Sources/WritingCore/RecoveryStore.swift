import Foundation

public struct RecoveredDraft: Codable {
    public var id: UUID
    public var text: String
    public var originalPath: String?
    public var updatedAt: Date
    public init(id: UUID, text: String, originalPath: String? = nil, updatedAt: Date = Date()) {
        self.id = id; self.text = text; self.originalPath = originalPath; self.updatedAt = updatedAt
    }
}

/// Separate from the original file: failed saves and unexpected termination leave a recoverable copy.
public struct RecoveryStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func save(_ draft: RecoveredDraft) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url(for: draft.id), options: .atomic)
    }
    public func remove(_ id: UUID) throws {
        let file = url(for: id)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    public func drafts() throws -> [RecoveredDraft] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(RecoveredDraft.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updatedAt < $1.updatedAt }
    }
    private func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
}
