# Changelog

All notable changes to Netherite are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

New entries go under **Unreleased**, in the section that fits (Added, Changed,
Deprecated, Removed, Fixed, Security). `fastlane release` turns them into a
version, and the release notes on TestFlight and GitHub come from here.

## [Unreleased]

### Changed
- Properties keep their YAML 1.2 meaning: `yes`/`no` stay text and `01234` is a decimal number.
- Following a link to another note from Reading view opens it for editing.
- Notes render only safe link schemes (http, https, mailto, obsidian, netherite) and an allowlist of HTML; links with other schemes show as plain text.
- `netherite publish` deploys from a temporary folder; `--out` is now only for `netherite export`.
- The Share extension and widgets explain when a vault stored only on this device can't be reached.
- File Recovery only takes snapshots while its plugin is on.

### Fixed
- Typing right after naming a new note goes into its body instead of being lost.
- Tips no longer appear while you type, so they can't swallow keystrokes.
- Fast typing no longer moves the cursor back a character, and Undo stays in step after properties or tasks change the note.
- The `[[` link suggestions appear at the cursor.
- Titles stay on one line, so a pasted line break can't end up in a file name.
- Jumping to a heading works in Reading view.
- A new canvas card takes your typing; empty cards are discarded, a canvas that fails to load is never overwritten, and its Undo steps don't leak into other notes.
- Window titles show canvases and bases without their extension, and mention previews show link text instead of `[[…]]`.
- Editing a property keeps every other property exactly as written.
- Renaming a note updates links in properties, escaped aliases in tables and links to itself; a stray backtick no longer hides links and tags; `# C#` headings and links to headings no longer create false tags.
- A note renamed, moved or deleted elsewhere updates in every window instead of reappearing under its old name.
- Recent edits are saved when you quit, and changes from iCloud keep arriving while another window is in the background.
- List properties accept commas; the file list rejects dropping a folder into itself; new vault names are validated and never reopen an existing vault.
- Recent notes follow moves and deletions; File Recovery snapshots follow the vault when it moves.
- Vault access is released when a vault closes, and Export Vault works for vaults opened from other folders.
- A vault moved to Recently Deleted is no longer used by the Share extension and widgets; widgets refresh after Shortcuts and shares, and their links open the right vault.
- Audio recordings continue through interruptions and in the background, and are kept when their sheet closes.
- The Workspaces sheet fits on iPhone, "Create Theme from Current…" never overwrites a theme, and Publish cleans up its temporary files.
- Embedding a block or heading, and some unusual characters, no longer crash rendering; notes with thousands of links render quickly.
- Bases: `toFixed` no longer crashes and saving keeps property settings and formulas; published sites keep notes named `index`, `404` or `graph`.
- Typing in a note created by a widget, Shortcut or share, or while a vault is still loading, is no longer reverted.
- Canvas cards keep every keystroke, and tips also wait while you name a note.
- Renaming a note to a name with quotes keeps the properties of notes that link to it valid.
- `[text](#heading)` links and images with formulas in their alt text render correctly.
- Notes with many links and tags, or broken HTML, no longer slow down editing.
- The Inspector keeps an unfinished list property with its own note, and full-screen presentations on iPhone and iPad no longer stop iCloud updates.
- A failed move to Recently Deleted keeps your latest edits, and a recording that can't be saved shows an error.
- Copies of a vault keep separate File Recovery history, and opening a vault no longer rewrites its settings files.
- The iPhone welcome tour responds to the first tap.
- Opening a note from a link or Spotlight with different capitals keeps your typing, Spotlight results work from the vault picker and for names with `|`, and a capitals-only rename outside the app warns before edits are lost.
- Moving a vault opened in place to Recently Deleted or iCloud Drive works again, and notes save their latest edits before going to the trash.
- A recording that can't be saved in the vault is kept in Application Support, and the error says where.
- Highlights and formulas that contain a link render again; link titles and reference definitions no longer create tags.
- Notes opened from recents, bookmarks or workspaces with different capitals keep your typing; bookmarks and workspaces follow renames and drop deleted notes.
- Move to iCloud Drive keeps the window on the moved vault and updates the widgets and Share extension.
- Search waits for you to stop typing and never shows results for an older query; regex search honours Match Case.
- The graph no longer restarts its layout on every keystroke.
- Notion and Evernote imports link to the right page or image when names repeat, and HTML imports keep literal text such as `<b>` or `# ` as text.
- Date templates and daily notes always use the Gregorian calendar and Western digits, matching Obsidian.
- Renaming a note keeps the titles of Markdown links to it.
- Editing a property no longer erases a note's other properties when its frontmatter isn't valid YAML; Netherite asks you to fix it first.
- Note names can't start with a dot, so new, renamed, imported and daily notes never end up hidden.
- Vault settings, bookmarks and themes changed on another device appear without reopening the vault, and saving them keeps those changes.
- Moving a vault to iCloud Drive no longer leaves a copy of new edits at the old location, and Settings keeps showing the moved vault.
- Reading view keeps your scroll position when a note changes, and outline, block and footnote jumps work there.
- Imports keep links working when folder names contain `#` or brackets, and HTML imports keep `---`, `~~~`, `%%` and `$` as text.
- Task search operators match the task state and tasks in numbered lists; highlights after link titles render, and tags inside link text stay plain text.
- Counts such as "1 day" and "1 attendee" use the singular in English and Spanish.
- Long property values and names keep the frontmatter valid, so the Inspector can always edit them.
- Evernote and HTML imports that start with a horizontal rule keep their text and metadata, and text split across HTML elements can't turn into comments or highlights.
- Moving a note keeps edits other devices made to notes that link to it, and saving keeps a file's creation date.
- Vault settings and bookmarks are kept when iCloud evicts their files, and a shared clip starting with `---` is saved as is.
- Ticking a task in a hover preview changes the right line, reading view hands heading jumps back to the editor, and a failed save while moving a vault to iCloud Drive is reported.
- Notes that are symbolic links save again, and moving a note no longer brings back notes deleted elsewhere.
- Highlights that wrap a wikilink or a formula render; imported `%` and `=` stay plain text unless they would form `%%` or `==`.
- The "Open Notes in Reading View" setting now works (new notes still open for editing), slide tasks are read-only, and merging notes keeps edits made on other devices.
- Edits that can't be saved after moving a vault to iCloud Drive are kept in File Recovery.
- Notes that are symbolic links pick up outside edits, and moving another note no longer overwrites them.
- With "Open Notes in Reading View", search results and backlinks still jump to the matching line; notes made without opening them (extracted selections, base entries) follow the setting.
- Merging notes moves the source's properties into the target's frontmatter instead of leaving a second block in the text.
- Imported HTML keeps a lone `=` line as text inside quotes and lists, and a tag right after inline math renders as a tag.
- Merging notes keeps every tag and alias and preserves nested, date and number properties as written; symlinked canvases pick up outside edits.
- Following a link that includes `.md` to a note that doesn't exist yet creates `Note.md`, not `Note.md.md`; merging a list into a number, date or checkbox property keeps the existing value.
- Links to a missing canvas or base create it; links to a missing attachment say it isn't in the vault.
- Editing or merging properties that use YAML anchors (`&name`, `*name`) keeps the frontmatter valid.

### Security
- Imported ZIPs, links, Shortcuts and the `nth://` scheme can no longer read or write outside the vault, and ZIP bombs are rejected.
- Rendered notes and published sites are protected against script injection with an HTML allowlist and a Content Security Policy.
- Web pages opened in the web viewer can no longer read vault files.
- `netherite://` links only open vaults you have already opened.
- Published sites pin their scripts by hash, and notes can't load scripts from the vault.
- Published sites no longer include `%%comments%%` in their search index.

## [0.1.1+13] - 2026-10-11

### Added
- Direct-download macOS build (notarized `Netherite.dmg`) that updates itself from GitHub releases: **Check for Updates…** in the app menu and an **Updates** tab in Settings.
- **Template Gallery** in Settings › Templates: browse ready-made templates published on the Netherite website and install them into your templates folder.

### Changed
- The GitHub release carries the Developer ID build as `Netherite.dmg` and `Netherite.zip` under `v<version>`, instead of a zip of the App Store build.
- Links in the reader are always underlined, so they stand out without relying on color.
- Custom theme backgrounds get text colors that stay readable on them, and theme colors keep their contrast over the app's own background.
- Larger tap targets for task checkboxes on touch screens, Recent Notes widget rows and the Bases clear-search button.
- Settings labels use title case consistently, and icons and tiles scale with Dynamic Type.
- Mermaid diagrams follow the system appearance when it changes.
- A new note opens with its title selected, so you can name it right away; Return moves to the body.
- Bases show localized column names (Modified, Created, Size…) and readable dates instead of raw keys and ISO timestamps.
- Graph view hides labels that would overlap, keeping the most connected notes labeled.
- Canvases and bases show without their file extension in the file list, like notes.
- The guide mentions touch alternatives to keyboard shortcuts, and the canvas tip says "double-tap" on iPhone and iPad.
- The command palette and quick switcher have their own titles on iPhone instead of repeating the search prompt.

### Fixed
- Inline code with a single character, such as `` `/` ``, renders correctly in Live Preview.
- The canvas toolbar no longer stretches into a large circle on iPhone, which made split canvases unusable.
- A `$…$` equation alone on its line renders in Live Preview, not only in Reading view.
- Tapping anywhere on a tag row or search result opens it, not just its text; search results no longer look disabled or flash "No results" while searching.
- Task checkboxes in Reading view line up with their text on touch screens.
- The "Show the Guide and Welcome Tour" setting describes what it shows, not what it hides.
- Search terms with a quote in the middle, such as `don"t`, stay one word instead of starting a phrase.
- Deleting all snapshots now reports a failure instead of silently doing nothing.
- VoiceOver announces long-running vault operations and which split pane is focused, and skips drag-only canvas handles.

## [0.1.0+10] - 2026-10-03

### Fixed
- The macOS app attached to the GitHub Release is signed with Developer ID and notarized, so it opens without Gatekeeper warnings.

## [0.1.0+9] - 2026-10-03

### Fixed
- The macOS app is signed with the hardened runtime, so it can be notarized and attached to the GitHub Release.

## [0.1.0+8] - 2026-10-03

### Fixed
- The notarized macOS app is attached to the GitHub Release again; the Developer ID export no longer fails after the TestFlight upload.

## [0.1.0+7] - 2026-10-03

### Added
- The macOS app is notarized with Developer ID and attached to each GitHub Release as a zip, so it can be installed without TestFlight.
- Release notes on TestFlight and GitHub now come from this changelog.

## [0.1.0+6] - 2026-10-03

### Added
- Theme gallery: Netherite, Ocean, Forest, Ember, Rose, Graphite and System tones, each in Automatic, Light and Dark; every built-in accent and link meets WCAG AA contrast.
- Netherite › Accessibility: text size (including accessibility sizes), editor font, size and line spacing, Increase Contrast, color-vision palettes and Reduce Motion.
- Sync page in vault settings with the files uploading, downloading or waiting, overall progress and time left; the sidebar footer only appears while syncing.
- Core plugins can be turned off per vault from Settings › Plugins; turned-off plugins leave the command palette, menus and the More menu.
- Meeting notes with title, date, attendees and an optional audio recording, in a configurable folder.
- Built-in template gallery (meeting, daily journal, weekly review, project, book notes, to-do list, decision record) and "New note from template".
- Databases built on Bases, plus quick search, New Entry, Add Property and a Board view with drag and drop in Bases.

### Changed
- Netherite settings and each vault's settings are now separate screens.

### Fixed
- VoiceOver labels for canvas colors, errors and decorative symbols; 44 pt touch targets.
- Reduce Motion is honored by every remaining animation, including the reader's heading flash and the syncing pulse.
- Snapshot list on iOS no longer swallows taps; wide symbols fit their settings tile.

## [0.1.0+5] - 2026-10-03

### Added
- Vault management: every vault shows its size, file count and iCloud sync status; vaults can be moved to Recently Deleted and restored for 90 days.
- Folders opened from outside can be opened in place or copied into iCloud Drive so they sync.
- "Synced with iCloud" status footer under the sidebar.
- Export a note, file, folder (as a zip) or the whole vault, and import files and folders into a vault.
- File recovery browses snapshots with previews and can copy or restore them, saving the current version first.
- Settings app entries for the vault opened on launch, the welcome tour, tips and storage.

### Changed
- Redesigned settings: General, Vaults, Recently Deleted, Help and About, with each vault's settings split into pages (Editor, Files and links, Appearance, Daily notes, Templates, File recovery).

## [0.1.0+4] - 2026-10-02

### Added
- On iPhone, the More menu opens with Back, Forward and Toggle Inspector buttons, and panes stack top to bottom.
- Open Local Graph can open in a new pane or in the full window.
- Vault menu (Settings, Switch Vault…) in the iPhone sidebar.

### Changed
- Keyboard shortcuts that collided with the system or the canvas: daily note is ⇧⌘D, graph view ⌃⌘G and insert template ⇧⌘T.

### Fixed
- Data loss when trashing notes without a system trash (notes now go to a vault `.trash/` folder), during concurrent refreshes, when opening the daily note at launch and when moving folders with unsaved notes.
- Canvases are saved when the app goes to the background; vaults inside the iOS app container survive reinstalls and updates.
- Notes opened from search, bookmarks, tags or links now show on iPhone; tapping a link opens the note under the finger.
- One confirmation for every Move to Trash action; confirmations, progress and error states in the audio recorder, web viewer, workspaces and publishing.
- The small Recent Notes widget opens the note it shows; the share extension saves into its Clippings folder and can save a link-only note.
- Search accepts smart quotes and no longer auto-capitalizes operators.
- Crash when a tinted control rendered theme colors off the main thread.
- macOS sidebar ghost rows after creating or deleting a note, and graph framing while the layout settles.
- Dynamic Type, VoiceOver and contrast in the editor and reader; missing Spanish strings and consistent terminology.

## [0.1.0+3] - 2026-10-01

### Fixed
- Builds carry the right version and build number, so TestFlight accepts the iOS upload.

## [0.1.0+2] - 2026-10-01

### Fixed
- The macOS build is packaged as an installer so it can be uploaded to TestFlight.

## [0.1.0+1] - 2026-10-01

### Added
- Native SwiftUI app for macOS, iOS and iPadOS: a vault is a folder of plain Markdown files, compatible with Obsidian vaults, `[[wikilinks]]`, `.canvas` and `.base` files.
- Live Preview editor on TextKit 2 with tasks, callouts, tables, footnotes, math, Mermaid diagrams and inline image embeds, plus a rendered reading view.
- Backlinks, outgoing links, outline, tags and properties panels; rename-safe links.
- Full-text search with operators, global and local graph view, infinite canvas and Bases (table, cards and list views).
- Core plugins: daily notes, templates, unique notes, bookmarks, workspaces, random note, note composer, slides, audio recorder, web viewer, page preview and file recovery.
- Static-site publishing to Cloudflare Pages, importers (Evernote, Notion, HTML/Apple Notes, Markdown) and the `netherite` command-line tool.
- Share-sheet web clipper, widgets, Control Center control, Shortcuts actions and Spotlight indexing.
- Onboarding tour, start page, a guide vault that teaches every feature, and feature tips.
- English and Spanish localization.

[Unreleased]: https://github.com/Im-Fran/Netherite/compare/v0.1.1+13...HEAD
[0.1.1+13]: https://github.com/Im-Fran/Netherite/compare/0.1.0+10...v0.1.1+13
[0.1.0+10]: https://github.com/Im-Fran/Netherite/compare/0.1.0+9...0.1.0+10
[0.1.0+9]: https://github.com/Im-Fran/Netherite/compare/0.1.0+8...0.1.0+9
[0.1.0+8]: https://github.com/Im-Fran/Netherite/compare/0.1.0+7...0.1.0+8
[0.1.0+7]: https://github.com/Im-Fran/Netherite/compare/0.1.0+6...0.1.0+7
[0.1.0+6]: https://github.com/Im-Fran/Netherite/compare/0.1.0+5...0.1.0+6
[0.1.0+5]: https://github.com/Im-Fran/Netherite/compare/0.1.0+4...0.1.0+5
[0.1.0+4]: https://github.com/Im-Fran/Netherite/compare/0.1.0+3...0.1.0+4
[0.1.0+3]: https://github.com/Im-Fran/Netherite/compare/0.1.0+2...0.1.0+3
[0.1.0+2]: https://github.com/Im-Fran/Netherite/compare/0.1.0+1...0.1.0+2
[0.1.0+1]: https://github.com/Im-Fran/Netherite/releases/tag/0.1.0+1
