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
        // Compose the result away from TextKit. Resetting live fonts and hidden markers on
        // every keystroke regenerates unchanged lines, which can make mixed-font lines jitter.
        let styled = NSMutableAttributedString(string: text, attributes: appearance.attributes)
        for span in cachedSpans where NSMaxRange(span.range) <= storage.length {
            switch span.kind {
            case .heading(let level):
                let sizes: [CGFloat] = [1.72, 1.36, 1.14, 1.04, 1, 1]
                let font = NSFontManager.shared.convert(appearance.font(size: appearance.size * sizes[level - 1]), toHaveTrait: .boldFontMask)
                styled.addAttribute(.font, value: font, range: span.range)
                let paragraph = appearance.paragraph.mutableCopy() as! NSMutableParagraphStyle
                paragraph.paragraphSpacing = 5
                styled.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
            case .strong, .emphasis:
                let trait: NSFontTraitMask = span.kind == .strong ? .boldFontMask : .italicFontMask
                styled.enumerateAttribute(.font, in: span.range) { value, range, _ in
                    if let font = value as? NSFont { styled.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: range) }
                }
            case .code:
                styled.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: appearance.size * 0.85, weight: .regular), .foregroundColor: appearance.secondary], range: span.range)
            case .quote:
                styled.addAttributes([.foregroundColor: appearance.secondary, .font: NSFontManager.shared.convert(appearance.font(), toHaveTrait: .italicFontMask)], range: span.range)
                let paragraph = appearance.paragraph.mutableCopy() as! NSMutableParagraphStyle
                paragraph.headIndent = 22; paragraph.firstLineHeadIndent = 22
                styled.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
            case .list:
                let paragraph = appearance.paragraph.mutableCopy() as! NSMutableParagraphStyle
                paragraph.headIndent = appearance.size
                styled.addAttribute(.paragraphStyle, value: paragraph, range: span.range)
            case .link:
                styled.addAttributes([.foregroundColor: appearance.accent, .underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: appearance.accent.withAlphaComponent(0.4)], range: span.range)
            case .footnoteReference:
                if !showSyntax && NSIntersectionRange(active, span.range).length == 0 {
                    styled.addAttributes([.font: appearance.font(size: appearance.size * 0.67), .baselineOffset: appearance.size * 0.32, .foregroundColor: appearance.accent], range: span.range)
                }
            case .footnoteDefinition:
                styled.addAttributes([.font: appearance.font(size: appearance.size * 0.85), .foregroundColor: appearance.secondary], range: span.range)
            case .marker, .emphasisMarker, .headingMarker:
                // Completed headings and emphasis stay rendered while editing, including after shortcuts.
                // Explicit source mode still exposes every delimiter for direct Markdown edits.
                if showSyntax || (span.kind == .marker && NSIntersectionRange(active, span.range).length > 0) {
                    styled.addAttribute(.foregroundColor, value: appearance.secondary, range: span.range)
                } else {
                    styled.addAttributes([.hiddenMarkdown: true, .foregroundColor: NSColor.clear], range: span.range)
                }
            }
        }
        var updates: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        var changedMarkers: [NSRange] = []
        styled.enumerateAttributes(in: all) { attributes, range, _ in
            storage.enumerateAttributes(in: range) { current, currentRange, _ in
                guard !(attributes as NSDictionary).isEqual(to: current) else { return }
                updates.append((currentRange, attributes))
                if (attributes[.hiddenMarkdown] as? Bool == true) != (current[.hiddenMarkdown] as? Bool == true) {
                    changedMarkers.append(currentRange)
                }
            }
        }
        if !updates.isEmpty {
            storage.beginEditing()
            for update in updates { storage.setAttributes(update.attributes, range: update.range) }
            // TextKit does not know that our custom attribute changes glyph visibility.
            // Invalidate only changed markers, before the batched edits trigger layout.
            for range in changedMarkers {
                view.layoutManager?.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
                view.layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            }
            storage.endEditing()
        }
        view.typingAttributes = appearance.attributes
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
