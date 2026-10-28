import XCTest
import AppKit
import WritingCore
@testable import Still

private final class RecordingLayoutManager: NSLayoutManager {
    var invalidatedGlyphRanges: [NSRange] = []

    override func invalidateGlyphs(forCharacterRange range: NSRange, changeInLength delta: Int, actualCharacterRange: NSRangePointer?) {
        invalidatedGlyphRanges.append(range)
        super.invalidateGlyphs(forCharacterRange: range, changeInLength: delta, actualCharacterRange: actualCharacterRange)
    }
}

@MainActor
final class EditorTests: XCTestCase {
    private static let documents = StillDocumentController()
    private func editor(_ text: String = "") throws -> (MarkdownDocument, EditorWindowController) {
        _ = NSApplication.shared
        let controller = Self.documents
        let document = try MarkdownDocument(type: MarkdownDocument.markdownType)
        controller.addDocument(document)
        try document.read(from: Data(text.utf8), ofType: MarkdownDocument.markdownType)
        document.makeWindowControllers()
        return (document, document.windowControllers[0] as! EditorWindowController)
    }
    func testStylingPreservesSourceAndRevealsOnlyActiveQuoteSyntax() throws {
        let source = "# A heading\n\n> A quotation\n\nSome **bold** text.\n\nLast paragraph."
        let (document, editor) = try editor(source)
        let view = editor.textView
        view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        editor.restyle()
        XCTAssertEqual(view.string, source)
        XCTAssertEqual(try document.data(ofType: MarkdownDocument.markdownType), Data(source.utf8))
        XCTAssertEqual(view.textStorage?.attribute(.hiddenMarkdown, at: 0, effectiveRange: nil) as? Bool, true)
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        XCTAssertEqual(view.layoutManager?.propertyForGlyph(at: 0), .null)
        let quote = (source as NSString).range(of: "> A quotation")
        XCTAssertEqual(view.textStorage?.attribute(.hiddenMarkdown, at: quote.location, effectiveRange: nil) as? Bool, true)
        view.setSelectedRange(NSRange(location: quote.location + 4, length: 0))
        editor.restyle()
        XCTAssertNil(view.textStorage?.attribute(.hiddenMarkdown, at: quote.location, effectiveRange: nil))
        document.close()
    }
    func testHeadingsStayRenderedWhenSelectedAndCanReturnToBody() throws {
        let (document, editor) = try editor("A heading\n\nBody text.")
        defer { document.close() }
        let view = editor.textView
        let command = NSMenuItem()
        for level in 1...3 {
            command.tag = level
            view.heading(command)
            editor.restyle()
            let prefix = String(repeating: "#", count: level) + " "
            XCTAssertEqual(document.text, prefix + "A heading\n\nBody text.")
            for selection in [NSRange(location: level + 3, length: 0), NSRange(location: 0, length: level)] {
                view.setSelectedRange(selection)
                editor.restyle()
                XCTAssertEqual(view.textStorage?.attribute(.hiddenMarkdown, at: 0, effectiveRange: nil) as? Bool, true)
                view.layoutManager?.ensureLayout(for: view.textContainer!)
                XCTAssertEqual(view.layoutManager?.propertyForGlyph(at: 0), .null)
            }
            view.toggleSyntax(nil)
            XCTAssertNil(view.textStorage?.attribute(.hiddenMarkdown, at: 0, effectiveRange: nil))
            view.toggleSyntax(nil)
        }
        command.tag = 0
        view.heading(command)
        XCTAssertEqual(document.text, "A heading\n\nBody text.")
    }
    func testTypingAndUndoUpdateDocument() throws {
        let (document, editor) = try editor()
        let view = editor.textView
        document.undoManager?.groupsByEvent = false
        document.undoManager?.beginUndoGrouping()
        view.insertText("A sentence 🌿", replacementRange: NSRange(location: 0, length: 0))
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(document.text, "A sentence 🌿")
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        XCTAssertTrue(document.isDocumentEdited)
        document.undoManager?.undo()
        XCTAssertEqual(document.text, "")
        document.undoManager?.redo()
        XCTAssertEqual(document.text, "A sentence 🌿")
        document.close()
    }
    func testBoldAndFootnoteAreUndoableSourceEdits() throws {
        let (document, editor) = try editor("A thought")
        let view = editor.textView
        view.setSelectedRange(NSRange(location: 2, length: 7))
        document.undoManager?.beginUndoGrouping()
        view.bold(nil)
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(document.text, "A **thought**")
        document.undoManager?.undo()
        XCTAssertEqual(document.text, "A thought")
        view.setSelectedRange(NSRange(location: 9, length: 0))
        document.undoManager?.beginUndoGrouping()
        view.insertFootnote(nil)
        document.undoManager?.endUndoGrouping()
        XCTAssertEqual(document.text, "A thought[^1]\n\n[^1]: ")
        document.undoManager?.undo()
        XCTAssertEqual(document.text, "A thought")
        document.close()
    }
    func testNativeSaveAndReopen() throws {
        // NSDocument's coordinated save uses macOS services unavailable to a sandboxed CLI runner.
        // The actual .app save/autosave/reopen flow is also verified through its native UI.
        guard ProcessInfo.processInfo.environment["STILL_RUN_SYSTEM_TESTS"] == "1" else {
            throw XCTSkip("Run STILL_RUN_SYSTEM_TESTS=1 zsh scripts/test.sh with normal macOS application services.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("still-save-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Writing.md")
        let (document, editor) = try editor()
        editor.textView.insertText("# A title\n\nA draft with café 🌿 and a footnote[^1].\n\n[^1]: A source.", replacementRange: NSRange(location: 0, length: 0))
        let expected = document.text
        let saved = expectation(description: "Native document saved")
        document.save(to: url, ofType: MarkdownDocument.markdownType, for: .saveAsOperation) { error in
            XCTAssertNil(error); saved.fulfill()
        }
        wait(for: [saved], timeout: 10)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), expected)
        let reopened = try MarkdownDocument(type: MarkdownDocument.markdownType)
        try reopened.read(from: Data(contentsOf: url), ofType: MarkdownDocument.markdownType)
        XCTAssertEqual(reopened.text, expected)
        document.close(); reopened.close()
    }
    func testBoldAndItalicShortcutsHideMarkersInActiveParagraph() throws {
        for marker in ["**", "*"] {
            let (document, editor) = try editor("A quiet thought")
            let view = editor.textView
            view.setSelectedRange(NSRange(location: 2, length: 5))
            if marker == "**" { view.bold(nil) } else { view.italic(nil) }
            editor.restyle()
            XCTAssertEqual(document.text, "A \(marker)quiet\(marker) thought")
            XCTAssertEqual((view.string as NSString).substring(with: view.selectedRange()), "quiet")
            let markerOffsets = [2, 2 + marker.count + 5]
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            for offset in markerOffsets {
                XCTAssertEqual(view.textStorage?.attribute(.hiddenMarkdown, at: offset, effectiveRange: nil) as? Bool, true)
                let glyph = view.layoutManager!.glyphIndexForCharacter(at: offset)
                XCTAssertEqual(view.layoutManager?.propertyForGlyph(at: glyph), .null)
            }
            // Collapsing the selection and continuing in the same paragraph keeps the clean display.
            let selected = view.selectedRange()
            view.setSelectedRange(NSRange(location: selected.location + 2, length: 0))
            editor.restyle()
            XCTAssertEqual(view.textStorage?.attribute(.hiddenMarkdown, at: 2, effectiveRange: nil) as? Bool, true)
            view.toggleSyntax(nil)
            XCTAssertNil(view.textStorage?.attribute(.hiddenMarkdown, at: 2, effectiveRange: nil))
            view.toggleSyntax(nil)
            view.setSelectedRange(selected)
            if marker == "**" { view.bold(nil) } else { view.italic(nil) }
            XCTAssertEqual(document.text, "A quiet thought")
            document.close()
        }
    }
    func testTypingBelowItalicsKeepsEarlierGlyphsAndLinePositions() throws {
        let source = "If you have ever been unfortunate enough to need to be prescribed exposure therapy, you'll *fortunately* know that it can be exceedingly effective. In a roundabout way, I am prescribing myself exposure to thinking. What does that mean?"
        let (document, editor) = try editor(source)
        defer { document.close() }
        let view = editor.textView
        let storage = try XCTUnwrap(view.textStorage)
        let container = try XCTUnwrap(view.textContainer)
        let layout = RecordingLayoutManager()
        container.replaceLayoutManager(layout)
        // The layout manager's delegate is weak; keep the styler alive for this test.
        let styler = MarkdownStyler()
        layout.delegate = styler
        view.setSelectedRange(NSRange(location: storage.length, length: 0))
        styler.apply(to: view, showSyntax: false)
        layout.ensureLayout(for: container)
        let emphasis = (source as NSString).range(of: "fortunately")
        let glyph = layout.glyphIndexForCharacter(at: emphasis.location)
        let baseline = layout.location(forGlyphAt: glyph)
        let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let original = storage.attributedSubstring(from: NSRange(location: 0, length: storage.length))

        // Cover both a later wrapped line in the same paragraph and a new paragraph.
        for text in [" More words on a later line.", "\n\nAnother paragraph with **bold** and café 🌿."] {
            for character in text {
                view.insertText(String(character), replacementRange: view.selectedRange())
                layout.invalidatedGlyphRanges.removeAll()
                styler.apply(to: view, showSyntax: false)
                XCTAssertFalse(layout.invalidatedGlyphRanges.contains { NSIntersectionRange($0, emphasis).length > 0 },
                               "Typing later in the document must not regenerate unchanged italic glyphs")
                XCTAssertTrue(storage.attributedSubstring(from: NSRange(location: 0, length: original.length)).isEqual(to: original))
                layout.ensureLayout(for: container)
                XCTAssertEqual(layout.location(forGlyphAt: glyph), baseline)
                XCTAssertEqual(layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil), line)
            }
        }
        layout.invalidatedGlyphRanges.removeAll()
        styler.apply(to: view, showSyntax: false)
        XCTAssertTrue(layout.invalidatedGlyphRanges.isEmpty, "An unchanged document needs no glyph invalidation")
        XCTAssertEqual(document.text, view.string)
    }

    func testCompletingAndRemovingEmphasisUpdatesFormattingAndHiddenGlyphs() throws {
        let (document, editor) = try editor("A *quiet")
        defer { document.close() }
        let view = editor.textView
        let storage = try XCTUnwrap(view.textStorage)
        let layout = try XCTUnwrap(view.layoutManager)
        let container = try XCTUnwrap(view.textContainer)
        func checkEmphasis(_ formatted: Bool, syntaxVisible: Bool = false) throws {
            editor.restyle()
            layout.ensureLayout(for: container)
            let font = try XCTUnwrap(storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
            XCTAssertEqual(NSFontManager.shared.traits(of: font).contains(.italicFontMask), formatted)
            for offset in formatted ? [2, storage.length - 1] : [2] {
                let hidden = formatted && !syntaxVisible
                XCTAssertEqual(storage.attribute(.hiddenMarkdown, at: offset, effectiveRange: nil) as? Bool == true, hidden)
                XCTAssertEqual(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: offset)).contains(.null), hidden)
            }
        }
        try checkEmphasis(false)
        view.setSelectedRange(NSRange(location: storage.length, length: 0))
        view.insertText("*", replacementRange: view.selectedRange())
        try checkEmphasis(true)
        view.toggleSyntax(nil)
        try checkEmphasis(true, syntaxVisible: true)
        view.toggleSyntax(nil)
        try checkEmphasis(true)
        view.deleteBackward(nil)
        try checkEmphasis(false)
        XCTAssertEqual(document.text, "A *quiet")
    }
    func testRestoreSelectionAndScrollAfterLayout() throws {
        let text = (1...80).map { "## Paragraph \($0)\n\nSome **thoughts** about writing 🌿, with enough text to fill a few lines.\n\n" }.joined()
        let (document, editor) = try editor(text)
        defer { document.close() }
        let selection = (text as NSString).range(of: "Some **thoughts**", options: [], range: NSRange(location: 1800, length: 500))
        XCTAssertNotEqual(selection.location, NSNotFound)
        let expected = WritingPosition(selection: selection, scrollOffset: 1200)
        editor.restorePosition(expected)
        XCTAssertEqual(editor.writingPosition.selection, expected.selection)
        XCTAssertEqual(editor.writingPosition.scrollOffset, expected.scrollOffset, accuracy: 1)
        XCTAssertEqual(document.text, text)
        XCTAssertFalse(document.isDocumentEdited)
        editor.loadText("Shorter 🌿")
        editor.restorePosition(expected)
        XCTAssertEqual(editor.writingPosition.selection, NSRange(location: ("Shorter 🌿" as NSString).length, length: 0))
        XCTAssertEqual(editor.writingPosition.scrollOffset, 0)
    }
    func testWritingColumnStaysCenteredAfterResizeAndSessionRestore() throws {
        let (document, editor) = try editor("# A heading\n\n" + String(repeating: "A paragraph of writing with enough words to wrap onto another line.\n\n", count: 30))
        defer { document.close() }
        let view = editor.textView
        let window = try XCTUnwrap(editor.window)
        let clip = try XCTUnwrap(view.enclosingScrollView?.contentView)
        func checkMargins(_ label: String) throws {
            let origin = view.convert(view.textContainerOrigin, to: clip)
            let columnWidth = try XCTUnwrap(view.textContainer?.containerSize.width)
            let left = origin.x - clip.bounds.minX
            let right = clip.bounds.maxX - origin.x - columnWidth
            XCTAssertEqual(left, right, accuracy: 1,
                           "\(label): clip \(clip.bounds), text view \(view.frame), inset \(view.textContainerInset), column \(columnWidth)")
            XCTAssertLessThanOrEqual(columnWidth, 680)
        }
        try checkMargins("Initial window")
        for width: CGFloat in [1000, 1512, 700, 1800, 420] {
            window.setContentSize(NSSize(width: width, height: 780))
            window.contentView?.layoutSubtreeIfNeeded()
            try checkMargins("After resizing to \(width)")
            editor.restorePosition(WritingPosition(selection: NSRange(location: 20, length: 0), scrollOffset: 200))
            try checkMargins("After restoring at \(width)")
        }
        editor.loadText("# A title\n\nA short draft.")
        window.setContentSize(NSSize(width: 1512, height: 933))
        window.contentView?.layoutSubtreeIfNeeded()
        try checkMargins("Short draft after resizing")
        editor.restorePosition(WritingPosition(selection: NSRange(location: 0, length: 1), scrollOffset: 0))
        try checkMargins("Short draft after restoring")
    }
    func testSessionDoesNotOverwriteStartupAndTracksSaveAs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("still-session-editor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionStore(url: directory.appendingPathComponent("LastSession.json"))
        let id = UUID()
        let previous = WritingSession(filePath: "/tmp/Original.md", recoveryID: id,
                                      position: WritingPosition(selection: NSRange(location: 500, length: 0), scrollOffset: 900))
        try store.save(previous)
        let memory = SessionMemory(store: store)
        let beginning = WritingPosition(selection: NSRange(location: 0, length: 0), scrollOffset: 0)
        memory.remember(filePath: nil, recoveryID: UUID(), position: beginning)
        memory.flush()
        XCTAssertEqual(store.load(), previous)
        memory.startTracking()
        let moved = URL(fileURLWithPath: "/tmp/Renamed.md")
        memory.saved(recoveryID: UUID(), to: moved)
        XCTAssertEqual(store.load(), previous)
        memory.saved(recoveryID: id, to: moved)
        XCTAssertEqual(store.load()?.filePath, moved.path)
        XCTAssertEqual(store.load()?.position, previous.position)
        let nextID = UUID()
        memory.remember(filePath: nil, recoveryID: nextID, position: beginning)
        memory.flush()
        XCTAssertEqual(store.load()?.recoveryID, nextID)
        XCTAssertNil(store.load()?.filePath)
    }
}
