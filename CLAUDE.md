# Netherite

Native, local-first Obsidian alternative for macOS 26 and iOS/iPadOS 26 (SwiftUI, Swift 6). A vault is a folder of plain Markdown files.

## Layout

- `Netherite/` — SwiftUI app (App state, Features, Intents, Resources). The target uses default MainActor isolation.
- `Packages/NetheriteCore/` — UI-free core library (vault, OFM parser, index, search, render, canvas, bases, import, publish), the `netherite` CLI and the test suite.
- `ShareExtension/`, `Widgets/` — app extensions.
- `project.yml` — XcodeGen definition; `Netherite.xcodeproj` is generated, never edit or commit it.

## Commands

```bash
xcodegen generate                                   # after adding/removing files or editing project.yml
xcodebuild -project Netherite.xcodeproj -scheme Netherite -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Netherite.xcodeproj -scheme Netherite -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
cd Packages/NetheriteCore && swift test             # core tests (Swift Testing)
```

## Conventions

- Build for macOS **and** iOS and run `swift test` before committing; commit with Conventional Commits.
- UI follows Apple's HIG; user-facing strings go through the String Catalogs (`en` source, `es` translated).
- Keep pure logic in `NetheriteCore` with a test; keep views thin.
- Record user-visible changes under `## [Unreleased]` in `CHANGELOG.md` (Keep a Changelog sections, English). A Stop hook (`.claude/hooks/changelog-check.sh`) reminds you.

## What graphify is and how we use it

[graphify](https://github.com/safishamsi/graphify) turns this repository into a knowledge graph: every Swift type, function, file and documented concept becomes a node, linked by calls, references and inferred relationships, then clustered into communities (e.g. "Vault Index & Link Graph", "Canvas Surface & Model"). We use it to navigate the codebase cheaply — a scoped subgraph answers "what touches X?" with a fraction of the tokens of reading or grepping sources.

- The graph lives in `graphify-out/` and is **not committed** (it is regenerated locally): `graph.json` (data), `GRAPH_REPORT.md` (god nodes, communities, surprising connections), `graph.html` (interactive view).
- Build it once with `/graphify .` in Claude Code. Code is extracted from the AST (no LLM); docs and images need a semantic pass.
- Exclude vendored/minified files from the corpus (`Resources/Web/*.min.js`, duplicated app-icon PNGs): they are third-party noise that would dominate the graph.
- The core abstractions it surfaces are `WindowState`, `VaultModel`, `Vault`, `CanvasModel` and `VaultIndex` — start there when tracing a feature.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
