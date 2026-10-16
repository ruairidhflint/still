import Foundation

enum ApplicationStorage {
    static var directory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Still"
        return support.appendingPathComponent(name, isDirectory: true)
    }
}
