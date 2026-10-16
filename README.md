# Still

A small native Mac app for quiet Markdown writing. Run `zsh scripts/run.sh` to build and open **dist/Still.app**. You can drag it into Applications if you want to keep it there.

The window is a centred page. Markdown formats as you write. Appearance and other controls live in the Mac menu bar.

Completed headings, bold and italic text keep their markers hidden while you edit, including after formatting shortcuts. Other syntax, such as link destinations, appears in the active paragraph. **View → Show Markdown Syntax** reveals all markers when you want to edit the raw Markdown.

- Warm light, warm dark, or system appearance.
- Charter serif or the system sans serif, with adjustable text size.
- Headings, bold, italics, lists, blockquotes, links and footnotes.
- Ordinary UTF-8 `.md` files, native Open/Save, autosave, undo/redo and Find.
- Local draft recovery after an unexpected exit. Recovered changes open as a separate document so they cannot overwrite a newer original.
- Reopens the last document at the same selection and scroll position. Opening a file from Finder takes priority; missing files leave a fresh page.
- Native spelling underlines and correction suggestions, on by default. The choice is remembered across windows and launches.

| Action | Shortcut |
| --- | --- |
| Fullscreen | Control–Command–F |
| New / Open / Save | Command–N / O / S |
| Save As | Shift–Command–S |
| Bold / Italic | Command–B / I |
| Heading 1–3 / Body | Command–1–3 / 0 |
| Insert link | Command–K |
| Insert footnote | Option–Command–F |
| Find | Command–F |
| Show Markdown syntax | Shift–Command–M |
| Word count (or selection count) | Option–Command–W |

Use `[^1]` for a footnote reference and `[^1]: Note text` for its definition. The footnote shortcut inserts both and moves the caret to the definition. Enter continues a list or quotation; Enter again on an empty item ends it. Toggle spelling underlines with **Edit → Check Spelling While Typing**; right-click an underlined word for suggestions. Automatic correction stays off.

Still is intentionally a small Markdown subset, not a complete CommonMark renderer. Tables, images, embedded HTML and other advanced syntax remain as source text. It saves the original text rather than converting formatted text back to Markdown. There are no accounts, network calls or runtime dependencies.

## Build

Requires macOS 13 or later and Swift 6 / Xcode command line tools. The supplied build targets this Mac's architecture (Apple silicon).

```sh
zsh scripts/build.sh
zsh scripts/run.sh
zsh scripts/test.sh
```

The executable is bundled and locally signed as `dist/Still.app`. It is a local build, not a notarised distribution for other Macs.

Swift/AppKit provides the document lifecycle and native TextKit editing. `WritingCore` handles source annotations, UTF-8 encoding and atomic recovery snapshots. Recovery files live in `~/Library/Application Support/Still/Recovery` until the associated document is saved or explicitly closed. The last file, selection and scroll offset are stored locally in `~/Library/Application Support/Still/LastSession.json`; this metadata never contains document text or resurrects discarded drafts.

## Verification

The automated suite covers source preservation, Unicode/BOM/newline round-trips, footnotes, literal code, list continuation, malformed Markdown, a long manuscript, recovery and session storage, restoring selections and scrolling, native text styling and undo/redo. One coordinated-save test is opt-in because macOS application services are unavailable in the restricted CLI runner:

```sh
STILL_RUN_SYSTEM_TESTS=1 zsh scripts/test.sh
```

The actual app was also checked through its native UI: Save, autosave after editing, reopen, Find, both fonts and themes, fullscreen, and recovery of an unsaved Unicode draft after Force Quit.
