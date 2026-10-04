# Changelog

All notable changes to Netherite are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

New entries go under **Unreleased**, in the section that fits (Added, Changed,
Deprecated, Removed, Fixed, Security). `fastlane release` turns them into a
version, and the release notes on TestFlight and GitHub come from here.

## [Unreleased]

### Added
- Direct-download macOS build (notarized `Netherite.dmg`) that updates itself from GitHub releases: **Check for Updates…** in the app menu and an **Updates** tab in Settings.

### Changed
- The GitHub release carries the Developer ID build as `Netherite.dmg` and `Netherite.zip` under `v<version>`, instead of a zip of the App Store build.
- Links in the reader are always underlined, so they stand out without relying on color.
- Custom theme backgrounds get text colors that stay readable on them, and theme colors keep their contrast over the app's own background.
- Larger tap targets for task checkboxes on touch screens, Recent Notes widget rows and the Bases clear-search button.
- Settings labels use title case consistently, and icons and tiles scale with Dynamic Type.
- Mermaid diagrams follow the system appearance when it changes.

### Fixed
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

[Unreleased]: https://github.com/Im-Fran/Netherite/compare/0.1.0+10...HEAD
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
