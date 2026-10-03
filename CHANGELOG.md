# Changelog

All notable changes to Netherite are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

New entries go under **Unreleased**, in the section that fits (Added, Changed,
Deprecated, Removed, Fixed, Security). `fastlane release` turns them into a
version, and the release notes on TestFlight and GitHub come from here.

## [Unreleased]

## [0.1.0] - 2026-10-03

### Added
- Native SwiftUI app for macOS, iOS and iPadOS: a vault is a folder of plain Markdown files, compatible with Obsidian vaults, `[[wikilinks]]`, `.canvas` and `.base` files.
- Live Preview editor on TextKit 2 with tasks, callouts, tables, footnotes, math, Mermaid diagrams and inline image embeds, plus a rendered reading view.
- Backlinks, outgoing links, outline, tags and properties panels; rename-safe links.
- Full-text search with operators, global and local graph view, infinite canvas and Bases (table, cards, list and board views).
- Core plugins: daily notes, templates, unique notes, bookmarks, workspaces, random note, note composer, slides, audio recorder, web viewer, page preview and file recovery — each can be turned off per vault.
- Meeting notes, a built-in template gallery and databases built on Bases.
- Theme gallery (Netherite, Ocean, Forest, Ember, Rose, Graphite, System) in automatic, light and dark variants.
- Accessibility preferences: text size, editor font and spacing, Increase Contrast, color-vision palettes and Reduce Motion.
- Vault management, iCloud sync status with a Sync page, vault export and import.
- Static-site publishing to Cloudflare Pages, importers (Evernote, Notion, HTML/Apple Notes, Markdown) and the `netherite` command-line tool.
- Share-sheet web clipper, widgets, Control Center control, Shortcuts actions and Spotlight indexing.
- Onboarding tour, start page, a guide vault that teaches every feature, and feature tips.
- English and Spanish localization.

### Changed
- Redesigned settings: Netherite settings and each vault's settings are separate screens.

### Fixed
- Data loss when trashing notes without a system trash, during concurrent refreshes, when opening the daily note at launch and when moving folders with unsaved notes.
- iPhone navigation, toolbars and delete confirmations; keyboard shortcuts that collided with the system.
- VoiceOver labels, touch targets, Reduce Motion and color-vision issues across the app.

[Unreleased]: https://github.com/Im-Fran/Netherite/compare/0.1.0+6...HEAD
[0.1.0]: https://github.com/Im-Fran/Netherite/releases/tag/0.1.0+6
