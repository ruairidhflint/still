import AppKit
import WritingCore

final class StillDocumentController: NSDocumentController {
    override var defaultType: String? { MarkdownDocument.markdownType }
    override func documentClass(forType typeName: String) -> AnyClass? { MarkdownDocument.self }
    override func typeForContents(of url: URL) throws -> String { MarkdownDocument.markdownType }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    let documents = StillDocumentController()
    private var recentMenu: NSMenu?
    private var started = false
    private var receivedOpenRequest = false
    private var pendingOpenRequests = 0
    private var completedStartup = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: icon)
        }
        NSWindow.allowsAutomaticWindowTabbing = false
        documents.autosavingDelay = 2
        buildMenu()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        started = true
        restoreLastSession()
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag && started { documents.newDocument(nil) }
        return true
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        receivedOpenRequest = true
        pendingOpenRequests += filenames.count
        for filename in filenames {
            documents.openDocument(withContentsOf: URL(fileURLWithPath: filename), display: true) { _, _, error in
                self.pendingOpenRequests -= 1
                if let error { NSApp.presentError(error) }
                if self.completedStartup && self.pendingOpenRequests == 0 && self.documents.documents.isEmpty {
                    self.documents.newDocument(nil)
                }
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool { false }
    func applicationWillResignActive(_ notification: Notification) {
        for document in documents.documents.compactMap({ $0 as? MarkdownDocument }) { document.persistRecovery() }
        SessionMemory.shared.flush()
    }
    func applicationWillTerminate(_ notification: Notification) {
        SessionMemory.shared.flush()
        // AppKit has resolved save/discard decisions by now. Untitled documents kept open on quit
        // retain recovery snapshots; named files are checked against disk before recovering.
        for document in documents.documents.compactMap({ $0 as? MarkdownDocument }) where document.fileURL == nil && !document.text.isEmpty {
            document.persistRecovery()
        }
    }
    private func restoreLastSession() {
        let session = SessionMemory.shared.lastSession
        let recovered = recoverDrafts(session: session)
        // Opening a file from Finder takes priority over the previous session.
        guard !receivedOpenRequest else { return finishStartup() }
        if let recovered {
            return finishStartup(restoring: recovered, position: session?.position)
        }
        guard let path = session?.filePath else { return finishStartup() }
        documents.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { document, _, _ in
            // A deleted, moved or unreadable last file simply leaves a fresh page.
            let editor = document?.windowControllers.first as? EditorWindowController
            self.finishStartup(restoring: editor, position: session?.position)
        }
    }

    private func finishStartup(restoring editor: EditorWindowController? = nil, position: WritingPosition? = nil) {
        completedStartup = true
        if documents.documents.isEmpty && pendingOpenRequests == 0 { documents.newDocument(nil) }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if !self.receivedOpenRequest, let editor, let position {
                editor.window?.makeKeyAndOrderFront(nil)
                editor.restorePosition(position)
            }
            SessionMemory.shared.startTracking()
            for document in self.documents.documents {
                (document.windowControllers.first as? EditorWindowController)?.rememberPosition()
            }
        }
    }

    private func recoverDrafts(session: WritingSession?) -> EditorWindowController? {
        var lastEditor: EditorWindowController?
        do {
            for draft in try MarkdownDocument.recoveryStore.drafts() {
                if let path = draft.originalPath,
                   let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                   let saved = try? TextFile(data: data), saved.text == draft.text {
                    try MarkdownDocument.recoveryStore.remove(draft.id)
                    continue
                }
                let document = try MarkdownDocument(type: MarkdownDocument.markdownType)
                document.restore(draft)
                documents.addDocument(document)
                document.makeWindowControllers()
                document.showWindows()
                document.windowControllers.first?.window?.titleVisibility = .visible
                if session?.matches(draft) == true {
                    lastEditor = document.windowControllers.first as? EditorWindowController
                }
            }
        } catch { NSApp.presentError(error) }
        return lastEditor
    }

    private func item(_ title: String, _ action: Selector?, _ key: String = "", modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target; item.tag = tag
        return item
    }
    private func buildMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            parent.submenu = menu; main.addItem(parent)
            return menu
        }
        let app = submenu("Still")
        app.addItem(item("About Still", #selector(showAbout(_:)), target: self))
        app.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services"); app.addItem(services); NSApp.servicesMenu = services.submenu
        app.addItem(.separator())
        app.addItem(item("Hide Still", #selector(NSApplication.hide(_:)), "h"))
        app.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]))
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        app.addItem(.separator())
        app.addItem(item("Quit Still", #selector(NSApplication.terminate(_:)), "q"))

        let file = submenu("File")
        file.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n", target: documents))
        file.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o", target: documents))
        let recent = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentMenu = NSMenu(title: "Open Recent"); recentMenu?.delegate = self; recent.submenu = recentMenu
        file.addItem(recent)
        file.addItem(.separator())
        file.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        file.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        file.addItem(item("Save As…", #selector(NSDocument.saveAs(_:)), "s", modifiers: [.command, .shift]))

        let edit = submenu("Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        edit.addItem(item("Redo", Selector(("redo:")), "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        edit.addItem(.separator())
        edit.addItem(item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        edit.addItem(item("Find Next", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        edit.addItem(item("Find Previous", #selector(NSTextView.performFindPanelAction(_:)), "g", modifiers: [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        edit.addItem(.separator())
        edit.addItem(item("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:))))

        let format = submenu("Format")
        format.addItem(item("Bold", #selector(WritingTextView.bold(_:)), "b"))
        format.addItem(item("Italic", #selector(WritingTextView.italic(_:)), "i"))
        format.addItem(.separator())
        for level in 1...3 { format.addItem(item("Heading \(level)", #selector(WritingTextView.heading(_:)), String(level), tag: level)) }
        format.addItem(item("Body", #selector(WritingTextView.heading(_:)), "0", tag: 0))
        format.addItem(.separator())
        format.addItem(item("Insert Link", #selector(WritingTextView.insertLink(_:)), "k"))
        format.addItem(item("Insert Footnote", #selector(WritingTextView.insertFootnote(_:)), "f", modifiers: [.command, .option]))

        let view = submenu("View")
        view.addItem(item("Warm Light", #selector(setTheme(_:)), target: self, tag: 0))
        view.addItem(item("Warm Dark", #selector(setTheme(_:)), target: self, tag: 1))
        view.addItem(item("Follow System", #selector(setTheme(_:)), target: self, tag: 2))
        view.addItem(.separator())
        view.addItem(item("Serif", #selector(setFont(_:)), target: self, tag: 0))
        view.addItem(item("Sans Serif", #selector(setFont(_:)), target: self, tag: 1))
        view.addItem(.separator())
        view.addItem(item("Larger Text", #selector(largerText(_:)), "+", target: self))
        view.addItem(item("Smaller Text", #selector(smallerText(_:)), "-", target: self))
        view.addItem(item("Default Text Size", #selector(resetText(_:)), "0", modifiers: [.command, .option], target: self))
        view.addItem(.separator())
        view.addItem(item("Show Markdown Syntax", #selector(WritingTextView.toggleSyntax(_:)), "m", modifiers: [.command, .shift]))
        view.addItem(item("Word Count…", #selector(WritingTextView.showWordCount(_:)), "w", modifiers: [.command, .option]))
        view.addItem(.separator())
        view.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", modifiers: [.command, .control]))

        let window = submenu("Window")
        window.addItem(item("Minimise", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        window.addItem(.separator())
        window.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for url in documents.recentDocumentURLs.prefix(12) {
            let entry = item(url.lastPathComponent, #selector(openRecent(_:)), target: self)
            entry.representedObject = url; entry.toolTip = url.path
            menu.addItem(entry)
        }
        if menu.items.isEmpty { menu.addItem(item("No Recent Documents", nil)) }
        else {
            menu.addItem(.separator())
            menu.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:)), target: documents))
        }
    }
    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        documents.openDocument(withContentsOf: url, display: true) { _, _, error in if let error { NSApp.presentError(error) } }
    }
    @objc private func showAbout(_ sender: Any?) {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [:]
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"), let image = NSImage(contentsOf: url) {
            options[.applicationIcon] = image
        }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
    @objc private func setTheme(_ sender: NSMenuItem) { Appearance.shared.theme = PaperTheme.allCases[sender.tag] }
    @objc private func setFont(_ sender: NSMenuItem) { Appearance.shared.family = WritingFont.allCases[sender.tag] }
    @objc private func largerText(_ sender: Any?) { Appearance.shared.size += 1 }
    @objc private func smallerText(_ sender: Any?) { Appearance.shared.size -= 1 }
    @objc private func resetText(_ sender: Any?) { Appearance.shared.size = 21 }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setTheme(_:)) { item.state = Appearance.shared.theme == PaperTheme.allCases[item.tag] ? .on : .off }
        if item.action == #selector(setFont(_:)) { item.state = Appearance.shared.family == WritingFont.allCases[item.tag] ? .on : .off }
        return true
    }
}
