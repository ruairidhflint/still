import AppKit

extension Notification.Name { static let writingAppearanceChanged = Notification.Name("StillAppearanceChanged") }
extension NSAttributedString.Key { static let hiddenMarkdown = NSAttributedString.Key("StillHiddenMarkdown") }

enum PaperTheme: String, CaseIterable { case light, dark, system }
enum WritingFont: String, CaseIterable { case serif, sans }

final class Appearance: NSObject {
    static let shared = Appearance()
    private let defaults = UserDefaults.standard
    var theme: PaperTheme {
        get { PaperTheme(rawValue: defaults.string(forKey: "paperTheme") ?? "light") ?? .light }
        set { defaults.set(newValue.rawValue, forKey: "paperTheme"); changed() }
    }
    var family: WritingFont {
        get { WritingFont(rawValue: defaults.string(forKey: "writingFont") ?? "serif") ?? .serif }
        set { defaults.set(newValue.rawValue, forKey: "writingFont"); changed() }
    }
    var size: CGFloat {
        get { let value = defaults.double(forKey: "writingSize"); return value == 0 ? 21 : max(14, min(32, value)) }
        set { defaults.set(max(14, min(32, newValue)), forKey: "writingSize"); changed() }
    }
    var dark: Bool {
        theme == .dark || (theme == .system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
    var paper: NSColor { dark ? NSColor(hex: 0x232320) : NSColor(hex: 0xF7F4ED) }
    var ink: NSColor { dark ? NSColor(hex: 0xE0DCD2) : NSColor(hex: 0x34342F) }
    var secondary: NSColor { dark ? NSColor(hex: 0x9D9D90) : NSColor(hex: 0x838376) }
    var accent: NSColor { dark ? NSColor(hex: 0xC4BD97) : NSColor(hex: 0x77734E) }
    var selection: NSColor { dark ? NSColor(hex: 0x474940) : NSColor(hex: 0xDFE0CF) }
    var native: NSAppearance? {
        switch theme { case .light: return NSAppearance(named: .aqua); case .dark: return NSAppearance(named: .darkAqua); case .system: return nil }
    }
    func font(size: CGFloat? = nil) -> NSFont {
        let size = size ?? self.size
        return family == .serif ? NSFont(name: "Charter", size: size) ?? NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size) : .systemFont(ofSize: size)
    }
    var paragraph: NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = size * 0.29
        paragraph.paragraphSpacing = 2
        paragraph.hyphenationFactor = 0
        return paragraph
    }
    var attributes: [NSAttributedString.Key: Any] { [.font: font(), .foregroundColor: ink, .paragraphStyle: paragraph] }
    private func changed() { NotificationCenter.default.post(name: .writingAppearanceChanged, object: nil) }
}

extension NSColor {
    convenience init(hex: Int) { self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
}
