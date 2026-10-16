import AppKit
import WritingCore

final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSWindowDelegate {
    let textView: WritingTextView
    private let scrollView = NSScrollView()
    private let styler = MarkdownStyler()
    private var appearanceObserver: NSObjectProtocol?
    private var activeParagraph = NSRange(location: NSNotFound, length: 0)
    private var loading = false
    private var restylePending = false

    init(document: MarkdownDocument) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 680, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        textView = WritingTextView(frame: NSRect(x: 0, y: 0, width: 1000, height: 760), textContainer: container)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = self
        window.minSize = NSSize(width: 420, height: 340)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior = [.fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("WritingWindow")
        window.center()
        window.contentView = scrollView
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.contentInsets = NSEdgeInsetsZero
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.setAccessibilityLabel("Writing")
        textView.setAccessibilityHelp("Markdown editor. Formatting syntax appears in the paragraph you are editing.")
        layout.delegate = styler
        textView.onSelection = { [weak self] in self?.restyle() }
        appearanceObserver = NotificationCenter.default.addObserver(forName: .writingAppearanceChanged, object: nil, queue: .main) { [weak self] _ in self?.applyAppearance() }
        loadText(document.text)
        applyAppearance()
        window.makeFirstResponder(textView)
    }
    required init?(coder: NSCoder) { fatalError("Still uses programmatic windows") }
    deinit { if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) } }
    func loadText(_ text: String) {
        loading = true
        let selected = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(location: min(selected.location, (text as NSString).length), length: 0))
        restyle()
        loading = false
    }
    func applyAppearance() {
        let appearance = Appearance.shared
        window?.appearance = appearance.native
        window?.backgroundColor = appearance.paper
        scrollView.backgroundColor = appearance.paper
        textView.backgroundColor = appearance.paper
        textView.insertionPointColor = appearance.ink
        textView.selectedTextAttributes = [.backgroundColor: appearance.selection, .foregroundColor: appearance.ink]
        textView.defaultParagraphStyle = appearance.paragraph
        restyle()
    }
    func restyle() {
        styler.apply(to: textView, showSyntax: textView.syntaxVisible)
        activeParagraph = Markdown.activeParagraph(in: textView.string, selection: textView.selectedRange())
    }
    func textDidChange(_ notification: Notification) {
        guard !loading, !styler.applying else { return }
        (document as? MarkdownDocument)?.edited(textView.string)
        // Wait until TextKit completes input/undo before changing display attributes.
        scheduleRestyle()
    }
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !loading, !styler.applying else { return }
        if Markdown.activeParagraph(in: textView.string, selection: textView.selectedRange()) != activeParagraph { scheduleRestyle() }
    }
    private func scheduleRestyle() {
        guard !restylePending else { return }
        restylePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restylePending = false
            self.restyle()
        }
    }
    func undoManager(for view: NSTextView) -> UndoManager? { document?.undoManager }
    func windowDidResignKey(_ notification: Notification) { (document as? MarkdownDocument)?.persistRecovery() }
    func windowDidBecomeKey(_ notification: Notification) { applyAppearance() }
}
