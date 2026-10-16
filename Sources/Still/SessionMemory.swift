import Foundation
import WritingCore

final class SessionMemory {
    static let shared: SessionMemory = {
        SessionMemory(store: SessionStore(url: ApplicationStorage.directory.appendingPathComponent("LastSession.json")))
    }()

    private let store: SessionStore
    private var timer: Timer?
    private var tracking = false
    private(set) var lastSession: WritingSession?

    init(store: SessionStore) {
        self.store = store
        lastSession = store.load()
    }
    deinit { timer?.invalidate() }

    // Startup window/selection notifications must not overwrite the session we're about to restore.
    func startTracking() { tracking = true }

    func remember(filePath: String?, recoveryID: UUID, position: WritingPosition) {
        guard tracking else { return }
        let session = WritingSession(filePath: filePath, recoveryID: recoveryID, position: position)
        guard session != lastSession else { return }
        lastSession = session
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in self?.flush() }
    }

    func saved(recoveryID: UUID, to url: URL) {
        guard tracking, lastSession?.recoveryID == recoveryID else { return }
        lastSession?.filePath = url.path
        flush()
    }

    func flush() {
        timer?.invalidate(); timer = nil
        guard tracking, let lastSession else { return }
        // Losing a position must never interrupt writing or interfere with document saves.
        try? store.save(lastSession)
    }
}
