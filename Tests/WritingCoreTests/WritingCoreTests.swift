import XCTest
@testable import WritingCore

final class WritingCoreTests: XCTestCase {
    func ranges(_ text: String, kind: MarkdownSpan.Kind) -> [String] {
        Markdown.spans(in: text).filter { $0.kind == kind }.map { (text as NSString).substring(with: $0.range) }
    }
    func testWritingBasicsAndUnicodeRanges() {
        let text = "# A quiet morning 🌿\n\nSome **bold** and *gentle* thoughts with café and 日本語.\n\n> A quotation\n\n- An idea\n"
        XCTAssertEqual(ranges(text, kind: .heading(1)), ["# A quiet morning 🌿\n"])
        XCTAssertEqual(ranges(text, kind: .strong), ["bold"])
        XCTAssertEqual(ranges(text, kind: .emphasis), ["gentle"])
        XCTAssertEqual(ranges(text, kind: .quote), ["> A quotation\n"])
        XCTAssertEqual(ranges(text, kind: .list), ["- An idea\n"])
        for span in Markdown.spans(in: text) { XCTAssertNotNil(Range(span.range, in: text)) }
    }
    func testFootnotesAndLinks() {
        let text = "An idea[^note] and [a reference](https://example.com/a_(b)).\n\n[^note]: The source."
        XCTAssertEqual(ranges(text, kind: .footnoteReference("note")), ["note"])
        XCTAssertEqual(ranges(text, kind: .footnoteDefinition("note")), ["[^note]: The source."])
        XCTAssertEqual(ranges(text, kind: .link("https://example.com/a_(b)")), ["a reference"])
        XCTAssertEqual(Markdown.nextFootnoteID(in: "[^1] [^3] [^word]"), "2")
    }
    func testCodeAndEscapedSyntaxStayLiteral() {
        let text = "```markdown\n# not a heading\n**not bold**\n```\n\n`**literal**` and \\*literal\\* and snake_case_word"
        XCTAssertTrue(ranges(text, kind: .heading(1)).isEmpty)
        XCTAssertTrue(ranges(text, kind: .strong).isEmpty)
        XCTAssertTrue(ranges(text, kind: .emphasis).isEmpty)
        XCTAssertTrue(ranges(text, kind: .code).contains("**literal**"))
    }
    func testUnfinishedMarkdownIsStillText() {
        XCTAssertTrue(ranges("**unclosed bold", kind: .strong).isEmpty)
        XCTAssertTrue(ranges("[unclosed link](", kind: .link("")).isEmpty)
        XCTAssertTrue(ranges("#not-a-heading", kind: .heading(1)).isEmpty)
    }
    func testActiveParagraphAtEndAndAcrossSelection() {
        let text = "First 🌿\n\nLast"
        XCTAssertEqual((text as NSString).substring(with: Markdown.activeParagraph(in: text, selection: NSRange(location: (text as NSString).length, length: 0))), "Last")
        XCTAssertEqual(Markdown.activeParagraph(in: "", selection: NSRange(location: 0, length: 0)), NSRange(location: 0, length: 0))
        XCTAssertEqual(Markdown.activeParagraph(in: text, selection: NSRange(location: 0, length: (text as NSString).length)).length, (text as NSString).length)
    }
    func testContinueAndExitLists() {
        XCTAssertEqual(Markdown.continuation(in: "- One", selection: NSRange(location: 5, length: 0))?.text, "\n- ")
        XCTAssertEqual(Markdown.continuation(in: "  9. Nine", selection: NSRange(location: 9, length: 0))?.text, "\n  10. ")
        XCTAssertEqual(Markdown.continuation(in: "> Quote", selection: NSRange(location: 7, length: 0))?.text, "\n> ")
        let exit = Markdown.continuation(in: "- One\n- ", selection: NSRange(location: 8, length: 0))
        XCTAssertEqual(exit?.range, NSRange(location: 6, length: 2))
        XCTAssertEqual(exit?.text, "")
        XCTAssertNil(Markdown.continuation(in: "Prose", selection: NSRange(location: 5, length: 0)))
    }
    func testTextFileRoundTripPreservesBOMNewlinesAndUnicode() throws {
        for text in ["", "café 🌿 日本語\r\n\r\n[^1]: Note\r\n", "# Heading\n\nA sentence."] {
            for bom in [false, true] {
                let original = TextFile(text: text, hasUTF8BOM: bom)
                let decoded = try TextFile(data: original.data)
                XCTAssertEqual(decoded.text, text)
                XCTAssertEqual(decoded.data, original.data)
            }
        }
        XCTAssertThrowsError(try TextFile(data: Data([0xff, 0xfe, 0xff])))
    }
    func testAtomicRecoveryAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("still-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecoveryStore(directory: directory)
        let id = UUID()
        try store.save(RecoveredDraft(id: id, text: "First draft 🌿", originalPath: "/tmp/example.md"))
        try store.save(RecoveredDraft(id: id, text: "Second draft 🌿", originalPath: "/tmp/example.md"))
        let recovered = try store.drafts()
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(recovered.first?.text, "Second draft 🌿")
        XCTAssertEqual(recovered.first?.originalPath, "/tmp/example.md")
        try store.remove(id)
        XCTAssertTrue(try store.drafts().isEmpty)
    }
    func testWordCountIgnoresLinkDestinationsAndMarkup() {
        XCTAssertEqual(Markdown.wordCount(in: "# One **two** [three](https://example.com/a-long-path)"), 3)
        XCTAssertEqual(Markdown.wordCount(in: "Don't stop writing."), 3)
        XCTAssertEqual(Markdown.wordCount(in: "***One*** **two**"), 2)
    }
    func testSessionRoundTripAndInvalidState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("still-session-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("LastSession.json"))
        XCTAssertNil(store.load())
        let session = WritingSession(filePath: "/tmp/A draft 🌿.md", recoveryID: UUID(),
                                     position: WritingPosition(selection: NSRange(location: 120, length: 9), scrollOffset: 815.5))
        try store.save(session)
        XCTAssertEqual(store.load(), session)
        let unsaved = WritingSession(filePath: nil, recoveryID: UUID(), position: session.position)
        try store.save(unsaved)
        XCTAssertEqual(store.load(), unsaved)
        try Data("incomplete JSON".utf8).write(to: store.url)
        XCTAssertNil(store.load())
    }
    func testRestoredPositionClampsToChangedTextAndUnicodeBoundaries() {
        let outside = WritingPosition(selection: NSRange(location: Int.max, length: Int.max), scrollOffset: 5000)
        XCTAssertEqual(outside.selection(in: "Short"), NSRange(location: 5, length: 0))
        XCTAssertEqual(outside.selection(in: ""), NSRange(location: 0, length: 0))
        XCTAssertEqual(outside.scrollOffset(maximum: 200), 200)
        XCTAssertEqual(outside.scrollOffset(maximum: -20), 0)
        let insideEmoji = WritingPosition(selection: NSRange(location: 2, length: 0), scrollOffset: -.infinity)
        XCTAssertEqual(insideEmoji.selection(in: "A🌿B"), NSRange(location: 1, length: 0))
        XCTAssertEqual(insideEmoji.scrollOffset(maximum: 200), 0)
        let partialEmoji = WritingPosition(selection: NSRange(location: 2, length: 1), scrollOffset: 0)
        XCTAssertEqual(partialEmoji.selection(in: "A🌿B"), NSRange(location: 1, length: 2))
    }
    func testSessionFindsRecoveryBeforeReopeningOriginal() {
        let id = UUID()
        let position = WritingPosition(selection: NSRange(location: 0, length: 0), scrollOffset: 0)
        let unsaved = WritingSession(filePath: nil, recoveryID: id, position: position)
        XCTAssertTrue(unsaved.matches(RecoveredDraft(id: id, text: "Draft")))
        XCTAssertFalse(unsaved.matches(RecoveredDraft(id: UUID(), text: "Unrelated")))
        let saved = WritingSession(filePath: "/tmp/draft.md", recoveryID: id, position: position)
        XCTAssertTrue(saved.matches(RecoveredDraft(id: UUID(), text: "Newer changes", originalPath: "/tmp/draft.md")))
        XCTAssertFalse(saved.matches(RecoveredDraft(id: UUID(), text: "Unrelated", originalPath: "/tmp/other.md")))
    }
    func testLongManuscriptAndMalformedSyntax() {
        let paragraph = "A paragraph with **bold prose**, *emphasis*, and [a source](https://example.com).\n\n"
        let manuscript = String(repeating: paragraph, count: 2000)
        let started = Date()
        let spans = Markdown.spans(in: manuscript)
        XCTAssertGreaterThan(spans.count, 10000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        let malformed = String(repeating: "*_[", count: 5000)
        for span in Markdown.spans(in: malformed) { XCTAssertLessThanOrEqual(NSMaxRange(span.range), (malformed as NSString).length) }
    }
}
