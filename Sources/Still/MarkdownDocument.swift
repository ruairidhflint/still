import AppKit
import WritingCore

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    static let markdownType = "net.daringfireball.markdown"
    static var recoveryStore: RecoveryStore {
        RecoveryStore(directory: ApplicationStorage.directory.appendingPathComponent("Recovery", isDirectory: true))
    }
    private var file = TextFile()
    var text: String { file.text }
    var recoveryID = UUID()
    var recoveredName: String?
    private var recoveryTimer: Timer?
    private var autosaveTimer: Timer?
    private var reportedRecoveryError = false

    override class var autosavesInPlace: Bool { true }
    override class var readableTypes: [String] { [markdownType, "public.plain-text"] }
    override class var writableTypes: [String] { [markdownType] }
    override class func isNativeType(_ type: String) -> Bool { readableTypes.contains(type) }
    // Named files use AppKit autosave; untitled work uses the explicit recovery store.
    override class var autosavesDrafts: Bool { false }
    override var displayName: String! {
        get { recoveredName ?? super.displayName }
        set { super.displayName = newValue }
    }

    override func makeWindowControllers() { addWindowController(EditorWindowController(document: self)) }
    override func data(ofType typeName: String) throws -> Data { file.data }
    override func read(from data: Data, ofType typeName: String) throws {
        file = try TextFile(data: data)
        for controller in windowControllers.compactMap({ $0 as? EditorWindowController }) { controller.loadText(file.text) }
    }
    func restore(_ draft: RecoveredDraft) {
        recoveryID = draft.id
        file = TextFile(text: draft.text)
        if let path = draft.originalPath { recoveredName = "Recovered — " + URL(fileURLWithPath: path).lastPathComponent }
        else { recoveredName = "Recovered Draft" }
        updateChangeCount(.changeDone)
    }

    func edited(_ text: String) {
        guard text != file.text else { return }
        file.text = text
        // NSDocument observes its undo manager to track dirty state, including undo back to saved.
        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in self?.persistRecovery() }
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self, self.hasUnautosavedChanges else { return }
            self.autosave(withImplicitCancellability: false) { error in
                if let error { self.presentError(error) }
            }
        }
    }
    func persistRecovery() {
        guard !file.text.isEmpty else {
            // A completely emptied saved document is still a meaningful edit.
            if fileURL == nil { try? Self.recoveryStore.remove(recoveryID); return }
            return saveRecovery()
        }
        saveRecovery()
    }
    private func saveRecovery() {
        do {
            try Self.recoveryStore.save(RecoveredDraft(id: recoveryID, text: file.text, originalPath: fileURL?.path))
        } catch {
            if !reportedRecoveryError { reportedRecoveryError = true; presentError(error) }
        }
    }

    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        let savedText = file.text
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if let self, error == nil,
               saveOperation == .saveOperation || saveOperation == .saveAsOperation || saveOperation == .autosaveInPlaceOperation {
                // Untitled native draft files do not replace our independent recovery snapshot.
                if self.file.text == savedText && self.fileURL != nil && !self.isDraft { try? Self.recoveryStore.remove(self.recoveryID) }
                if saveOperation == .saveAsOperation || saveOperation == .saveOperation { self.recoveredName = nil }
                if let url = self.fileURL { SessionMemory.shared.saved(recoveryID: self.recoveryID, to: url) }
            }
            completionHandler(error)
        }
    }
    override func close() {
        recoveryTimer?.invalidate(); autosaveTimer?.invalidate()
        // close() runs after AppKit's save/discard decision. A failed/cancelled save never reaches here.
        try? Self.recoveryStore.remove(recoveryID)
        super.close()
    }
}
