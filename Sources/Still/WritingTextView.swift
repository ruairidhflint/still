import AppKit
import WritingCore

final class WritingTextView: NSTextView {
    var onEdit: (() -> Void)?
    var onSelection: (() -> Void)?
    var syntaxVisible = false

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let column = min(680, max(240, newSize.width - 64))
        let horizontal = max(24, (newSize.width - column) / 2)
        let inset = NSSize(width: horizontal, height: 78)
        if textContainerInset != inset { textContainerInset = inset }
        if textContainer?.containerSize.width != column { textContainer?.containerSize = NSSize(width: column, height: .greatestFiniteMagnitude) }
        updateInsertionPointStateAndRestartTimer(true)
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

    override func insertNewline(_ sender: Any?) {
        if !hasMarkedText(), let edit = Markdown.continuation(in: string, selection: selectedRange()) {
            replace(edit.range, with: edit.text, selection: NSRange(location: edit.range.location + (edit.text as NSString).length, length: 0), name: "Typing")
        } else { super.insertNewline(sender) }
    }

    func replace(_ range: NSRange, with replacement: String, selection: NSRange, name: String) {
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
        undoManager?.setActionName(name)
        scrollRangeToVisible(selection)
    }

    private func wrap(_ marker: String, name: String) {
        let source = string as NSString
        let selected = selectedRange()
        let length = (marker as NSString).length
        let body = source.substring(with: selected)
        if selected.location >= length && NSMaxRange(selected) + length <= source.length,
           source.substring(with: NSRange(location: selected.location - length, length: length)) == marker,
           source.substring(with: NSRange(location: NSMaxRange(selected), length: length)) == marker {
            replace(NSRange(location: selected.location - length, length: selected.length + 2 * length), with: body,
                    selection: NSRange(location: selected.location - length, length: selected.length), name: name)
        } else if selected.length >= length * 2 && body.hasPrefix(marker) && body.hasSuffix(marker) {
            let unwrapped = String(body.dropFirst(marker.count).dropLast(marker.count))
            replace(selected, with: unwrapped, selection: NSRange(location: selected.location, length: (unwrapped as NSString).length), name: name)
        } else {
            replace(selected, with: marker + body + marker,
                    selection: NSRange(location: selected.location + length, length: selected.length), name: name)
        }
    }

    @objc func bold(_ sender: Any?) { wrap("**", name: "Bold") }
    @objc func italic(_ sender: Any?) { wrap("*", name: "Italic") }
    @objc func insertLink(_ sender: Any?) {
        let selected = selectedRange()
        let label = (string as NSString).substring(with: selected)
        let replacement = "[\(label)](https://)"
        let destination = selected.location + (label as NSString).length + 3
        replace(selected, with: replacement, selection: NSRange(location: destination, length: 8), name: "Insert Link")
    }
    @objc func insertFootnote(_ sender: Any?) {
        let source = string as NSString
        let selected = selectedRange()
        let id = Markdown.nextFootnoteID(in: string)
        let reference = "[^\(id)]"
        let insertion = NSMaxRange(selected)
        let withReference = source.replacingCharacters(in: NSRange(location: insertion, length: 0), with: reference)
        let separator = withReference.hasSuffix("\n\n") ? "" : (withReference.hasSuffix("\n") ? "\n" : "\n\n")
        let result = withReference + separator + "[^\(id)]: "
        // A single edit keeps insertion of the reference and definition in one undo step.
        replace(NSRange(location: 0, length: source.length), with: result, selection: NSRange(location: (result as NSString).length, length: 0), name: "Insert Footnote")
    }
    @objc func heading(_ sender: NSMenuItem) {
        let source = string as NSString
        let line = source.lineRange(for: NSRange(location: selectedRange().location, length: 0))
        let content = source.substring(with: line)
        let stripped = content.replacingOccurrences(of: #"^ {0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
        let prefix = sender.tag == 0 ? "" : String(repeating: "#", count: sender.tag) + " "
        let replacement = prefix + stripped
        replace(line, with: replacement, selection: NSRange(location: line.location + (prefix as NSString).length, length: 0), name: "Heading")
    }
    @objc func toggleSyntax(_ sender: Any?) { syntaxVisible.toggle(); onSelection?() }
    @objc func showWordCount(_ sender: Any?) {
        let selection = selectedRange()
        let content = selection.length == 0 ? string : (string as NSString).substring(with: selection)
        let alert = NSAlert()
        alert.messageText = "\(Markdown.wordCount(in: content).formatted()) words"
        alert.informativeText = "\(content.count.formatted()) characters" + (selection.length == 0 ? " in this document." : " in the selection.")
        alert.addButton(withTitle: "Done")
        if let window { alert.beginSheetModal(for: window) }
    }
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSyntax(_:)) { menuItem.state = syntaxVisible ? .on : .off; return true }
        if [#selector(bold(_:)), #selector(italic(_:)), #selector(insertLink(_:)), #selector(insertFootnote(_:)), #selector(heading(_:)), #selector(showWordCount(_:))].contains(menuItem.action) { return true }
        return super.validateMenuItem(menuItem)
    }
}
