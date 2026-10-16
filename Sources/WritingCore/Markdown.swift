import Foundation

/// Display annotations over the original UTF-16 text. Rendering never rewrites a document.
public struct MarkdownSpan: Equatable {
    public enum Kind: Equatable {
        case heading(Int), strong, emphasis, code, quote, list, link(String)
        case footnoteReference(String), footnoteDefinition(String), marker, emphasisMarker, headingMarker
    }
    public var range: NSRange
    public var kind: Kind
    public init(_ range: NSRange, _ kind: Kind) { self.range = range; self.kind = kind }
}

public enum Markdown {
    private static let expressions = NSCache<NSString, NSRegularExpression>()
    private static func matches(_ pattern: String, in text: NSString, range: NSRange? = nil) -> [NSTextCheckingResult] {
        let regex: NSRegularExpression
        if let cached = expressions.object(forKey: pattern as NSString) { regex = cached }
        else {
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return [] }
            expressions.setObject(compiled, forKey: pattern as NSString); regex = compiled
        }
        return regex.matches(in: text as String, range: range ?? NSRange(location: 0, length: text.length))
    }

    public static func spans(in string: String) -> [MarkdownSpan] {
        let text = string as NSString
        var spans: [MarkdownSpan] = []
        var protected: [NSRange] = []
        var fence: (Character, Int)?
        var position = 0
        func add(_ range: NSRange, _ kind: MarkdownSpan.Kind) {
            if range.length > 0 && range.location != NSNotFound { spans.append(MarkdownSpan(range, kind)) }
        }
        // Keep unsupported fenced code literal; prose inside it must never become headings or emphasis.
        while position < text.length {
            let line = text.lineRange(for: NSRange(location: position, length: 0))
            let content = (text.substring(with: line) as NSString)
            let trimmed = (content as String).trimmingCharacters(in: .newlines)
            let fenceMatch = matches(#"^ {0,3}(`{3,}|~{3,})(.*)$"#, in: trimmed as NSString).first
            if let current = fence {
                add(line, .code); protected.append(line)
                if let match = fenceMatch {
                    let marker = (trimmed as NSString).substring(with: match.range(at: 1))
                    let tail = (trimmed as NSString).substring(with: match.range(at: 2))
                    if marker.first == current.0 && marker.count >= current.1 && tail.trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                }
            } else if let match = fenceMatch {
                let marker = (trimmed as NSString).substring(with: match.range(at: 1))
                fence = (marker.first!, marker.count)
                add(line, .code); protected.append(line)
            } else {
                if let match = matches(#"^ {0,3}(#{1,6})[\t ]+(.+?)\s*$"#, in: content).first {
                    let level = match.range(at: 1).length
                    add(line, .heading(level))
                    add(NSRange(location: line.location, length: match.range(at: 2).location), .headingMarker)
                    if let closing = matches(#"[\t ]+#+[\t ]*$"#, in: trimmed as NSString).first {
                        add(NSRange(location: line.location + closing.range.location, length: closing.range.length), .headingMarker)
                    }
                }
                if let match = matches(#"^ {0,3}(>\s?)+"#, in: content).first {
                    add(line, .quote)
                    add(NSRange(location: line.location, length: match.range.length), .marker)
                }
                if matches(#"^\s*(?:[-+*]|\d+[.)])[\t ]+"#, in: content).first != nil { add(line, .list) }
                if let match = matches(#"^ {0,3}\[\^([^\]\s]+)\]:[\t ]*"#, in: content).first {
                    let id = content.substring(with: match.range(at: 1))
                    add(line, .footnoteDefinition(id))
                    add(NSRange(location: line.location, length: match.range(at: 1).location), .marker)
                    add(NSRange(location: line.location + NSMaxRange(match.range(at: 1)), length: 2), .marker)
                }
            }
            position = NSMaxRange(line)
        }
        func isProtected(_ range: NSRange) -> Bool { protected.contains { NSIntersectionRange($0, range).length > 0 } }
        // Backtick runs must match in length. Escaped delimiters stay ordinary text.
        for match in matches(#"(?<![\\`])(`+)(?!`)([^\n]*?[^`])\1(?!`)"#, in: text) where !isProtected(match.range) {
            add(match.range(at: 2), .code)
            add(match.range(at: 1), .marker)
            add(NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length), .marker)
            protected.append(match.range)
        }
        for match in matches(#"(?<!!)(?<!\\)\[([^\]\n]+)\]\(([^\s\n()]*(?:\([^\n()]*\)[^\s\n()]*)*)(?:\s+\"[^\"\n]*\")?\)"#, in: text) where !isProtected(match.range) {
            add(match.range(at: 1), .link(text.substring(with: match.range(at: 2))))
            add(NSRange(location: match.range.location, length: 1), .marker)
            let end = NSMaxRange(match.range(at: 1))
            add(NSRange(location: end, length: NSMaxRange(match.range) - end), .marker)
            // Link destinations are not prose, but their labels may contain emphasis.
            protected.append(NSRange(location: end, length: NSMaxRange(match.range) - end))
        }
        for match in matches(#"(?<!\\)\[\^([^\]\s]+)\](?!:)"#, in: text) where !isProtected(match.range) {
            add(match.range(at: 1), .footnoteReference(text.substring(with: match.range(at: 1))))
            add(NSRange(location: match.range.location, length: 2), .marker)
            add(NSRange(location: NSMaxRange(match.range) - 1, length: 1), .marker)
            protected.append(match.range)
        }
        // Process combined emphasis first so ***text*** has both traits.
        let emphasisPatterns: [(String, [MarkdownSpan.Kind], Int)] = [
            (#"(?<![\\*])\*{3}(?=\S)([^\n]*?\S)\*{3}(?!\*)"#, [.strong, .emphasis], 3),
            (#"(?<![\\*])\*{2}(?=\S)([^\n]*?\S)\*{2}(?!\*)"#, [.strong], 2),
            (#"(?<![\\\w_])__(?=\S)([^\n]*?\S)__(?!\w)"#, [.strong], 2),
            (#"(?<![\\*])\*(?=\S)([^*\n]*?\S)\*(?!\*)"#, [.emphasis], 1),
            (#"(?<![\\\w_])_(?=\S)([^_\n]*?\S)_(?!\w)"#, [.emphasis], 1)
        ]
        for (pattern, kinds, markerLength) in emphasisPatterns {
            for match in matches(pattern, in: text) where !isProtected(match.range) {
                for kind in kinds { add(match.range(at: 1), kind) }
                add(NSRange(location: match.range.location, length: markerLength), .emphasisMarker)
                add(NSRange(location: NSMaxRange(match.range) - markerLength, length: markerLength), .emphasisMarker)
            }
        }
        return spans
    }

    public static func activeParagraph(in string: String, selection: NSRange) -> NSRange {
        let text = string as NSString
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let start = min(selection.location, text.length)
        let count = min(selection.length, text.length - start)
        return text.paragraphRange(for: NSRange(location: start, length: count))
    }

    /// Return inserts for a list/quote continuation, or remove an empty item's prefix.
    public static func continuation(in string: String, selection: NSRange) -> (range: NSRange, text: String)? {
        let source = string as NSString
        guard selection.length == 0, selection.location <= source.length else { return nil }
        let line = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let before = source.substring(with: NSRange(location: line.location, length: selection.location - line.location)) as NSString
        let pattern = #"^(\s*)(?:([-+*]) |(\d+)([.)]) |(>) ?)(.*)$"#
        guard let match = matches(pattern, in: before).first else { return nil }
        let body = before.substring(with: match.range(at: 6))
        if body.trimmingCharacters(in: .whitespaces).isEmpty {
            return (NSRange(location: line.location, length: before.length), "")
        }
        let indent = before.substring(with: match.range(at: 1))
        let prefix: String
        if match.range(at: 2).location != NSNotFound { prefix = before.substring(with: match.range(at: 2)) + " " }
        else if match.range(at: 3).location != NSNotFound {
            guard let number = Int(before.substring(with: match.range(at: 3))), number < Int.max else { return nil }
            prefix = "\(number + 1)" + before.substring(with: match.range(at: 4)) + " "
        } else { prefix = "> " }
        return (selection, "\n" + indent + prefix)
    }

    public static func nextFootnoteID(in string: String) -> String {
        let text = string as NSString
        let ids = Set(matches(#"\[\^(\d+)\]"#, in: text).map { text.substring(with: $0.range(at: 1)) })
        var number = 1
        while ids.contains(String(number)) { number += 1 }
        return String(number)
    }

    public static func wordCount(in string: String) -> Int {
        var prose = string
        let markers = spans(in: string).filter { [.marker, .emphasisMarker, .headingMarker].contains($0.kind) }.map(\.range)
        // Merge overlapping ranges before replacing; combined emphasis can share delimiters.
        var removed = IndexSet()
        for range in markers { removed.insert(integersIn: range.location..<NSMaxRange(range)) }
        for range in removed.rangeView.reversed() {
            if let swiftRange = Range(NSRange(location: range.lowerBound, length: range.count), in: prose) { prose.removeSubrange(swiftRange) }
        }
        return matches(#"[\p{L}\p{N}]+(?:[’'\-][\p{L}\p{N}]+)*"#, in: prose as NSString).count
    }
}
