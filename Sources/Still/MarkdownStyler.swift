import AppKit
import WritingCore

/// TextKit handles all input, selection, accessibility and undo. This only annotates its text.
final class MarkdownStyler: NSObject, NSLayoutManagerDelegate {
    private var cachedText = ""
    private var cachedSpans: [MarkdownSpan] = []
    private(set) var applying = false

    func apply(to view: NSTextView, showSyntax: Bool) {
        guard !applying, !view.hasMarkedText(), let storage = view.textStorage else { return }
        applying = true
        defer { applying = false }
        let appearance = Appearance.shared
        let text = view.string
        if text != cachedText { cachedText = text; cachedSpans = Markdown.spans(in: text) }
        let active = Markdown.activeParagraph(in: text, selection: view.selectedRange())
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.setAttributes(appearance.attributes, range: all)
        for span in cachedSpans where NSMaxRange(span.range) <= storage.length {
            switch span.kind {
            case .heading(let level):
                let sizes: [CGFloat] = [1.72, 1.36, 1.14, 1.04, 1, 1]
                let font = NSFontManager.shared.convert(appearance.font(size: appearance.size * sizes[level - 1]), toHaveTrait: .boldFontMask)
                storage.addAttribute(.font, value: font, range: span.range)
                let paragraph = appearance.paragraph.mutableCopy() as! NSMutableParagraphStyle
                paragraph.paragraphSpacing = 5
                storage.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
            case .strong, .emphasis:
                let trait: NSFontTraitMask = span.kind == .strong ? .boldFontMask : .italicFontMask
                storage.enumerateAttribute(.font, in: span.range) { value, range, _ in
                    if let font = value as? NSFont { storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: range) }
                }
            case .code:
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: appearance.size * 0.85, weight: .regular), .foregroundColor: appearance.secondary], range: span.range)
            case .quote:
                storage.addAttributes([.foregroundColor: appearance.secondary, .font: NSFontManager.shared.convert(appearance.font(), toHaveTrait: .italicFontMask)], range: span.range)
                let paragraph = appearance.paragraph.mutableCopy() as! NSMutableParagraphStyle
                paragraph.headIndent = 22; paragraph.firstLineHeadIndent = 22
                storage.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
            case .list:
                let paragraph = appearance.paragraph.mutableCopy() as! NSMutableParagraphStyle
                paragraph.headIndent = appearance.size
                storage.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
            case .link:
                storage.addAttributes([.foregroundColor: appearance.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: appearance.accent.withAlphaComponent(0.4)], range: span.range)
            case .footnoteReference:
                if !showSyntax && NSIntersectionRange(active, span.range).length == 0 {
                    storage.addAttributes([.font: appearance.font(size: appearance.size * 0.67), .baselineOffset: appearance.size * 0.32, .foregroundColor: appearance.accent], range: span.range)
                }
            case .footnoteDefinition:
                storage.addAttributes([.font: appearance.font(size: appearance.size * 0.85), .foregroundColor: appearance.secondary], range: span.range)
            case .marker, .emphasisMarker:
                // Completed bold/italic stays rendered while editing, including after Cmd+B/Cmd+I.
                // Explicit source mode still exposes every delimiter for direct Markdown edits.
                if showSyntax || (span.kind == .marker && NSIntersectionRange(active, span.range).length > 0) {
                    storage.addAttribute(.foregroundColor, value: appearance.secondary, range: span.range)
                } else {
                    storage.addAttributes([.hiddenMarkdown: true, .foregroundColor: NSColor.clear], range: span.range)
                }
            }
        }
        storage.endEditing()
        view.typingAttributes = appearance.attributes
        // Custom display attributes do not automatically invalidate generated glyphs.
        view.layoutManager?.invalidateGlyphs(forCharacterRange: all, changeInLength: 0, actualCharacterRange: nil)
        view.needsDisplay = true
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes indexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
        guard let storage = layoutManager.textStorage else { return 0 }
        var properties = Array(UnsafeBufferPointer(start: props, count: range.length))
        var changed = false
        for offset in 0..<range.length where indexes[offset] < storage.length {
            if storage.attribute(.hiddenMarkdown, at: indexes[offset], effectiveRange: nil) as? Bool == true {
                properties[offset] = .null; changed = true
            }
        }
        guard changed else { return 0 }
        properties.withUnsafeBufferPointer {
            layoutManager.setGlyphs(glyphs, properties: $0.baseAddress!, characterIndexes: indexes, font: font, forGlyphRange: range)
        }
        return range.length
    }
}
