# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pressure is a macOS compression app (SwiftUI + AppKit) supporting ZIP, GZIP, TAR, BZIP2, and Z compression/decompression, plus RAR decompression (not yet implemented — throws `unsupportedFormat`). Targets macOS 13.0+, Swift 5.9+.

## Build System: Tuist

The Xcode project (`Pressure.xcodeproj`, `Pressure.xcworkspace`) is **generated** by Tuist from `Project.swift` and `Workspace.swift` — those two files are the source of truth and must never be hand-edited via the `.xcodeproj`. `Project.swift` also globs sources automatically (`Sources/Pressure/**/*.swift`, `Tests/PressureTests/**/*.swift`, `Tests/PressureUITests/**/*.swift`), so adding a new file needs no project edit — just regenerate.

```bash
tuist generate          # regenerate Xcode project after touching Project.swift/Workspace.swift, or after adding/removing source files
tuist clean              # remove generated Xcode files
open Pressure.xcworkspace
```

Adding a package dependency: add it to `packages:` in `Project.swift`, add a `.package(product:type:)` entry to the relevant target's `dependencies:`, then `tuist generate`.

## Build & Test Commands

Three independent schemes exist so tests can run without building/running the app: `Pressure` (app only), `PressureTests` (unit tests only), `PressureUITests` (UI tests only).

```bash
# Build the app
xcodebuild -workspace Pressure.xcworkspace -scheme Pressure build

# Unit tests
xcodebuild test -workspace Pressure.xcworkspace -scheme PressureTests -destination 'platform=macOS'

# UI tests
xcodebuild test -workspace Pressure.xcworkspace -scheme PressureUITests -destination 'platform=macOS'

# Single test (xcodebuild -only-testing)
xcodebuild test -workspace Pressure.xcworkspace -scheme PressureTests -destination 'platform=macOS' -only-testing:PressureTests/ZIPCompressorTests/testCompressSingleFile
```

Or from Xcode: select the scheme and press ⌘U.

## Architecture

**Two-pane layout** (`ContentView.swift`, `HSplitView`): left pane is the file system browser, right pane is the archive being built/viewed. Both panes wrap `NSTableView` via `NSViewRepresentable` for native Finder-style appearance (sortable columns, native file icons via `NSWorkspace`, drag-and-drop) rather than using SwiftUI `List`/`Table`.

- `FileSystemNavigator.swift` / `FinderStyleNavigator.swift` — left pane: browses the real filesystem.
- `ArchiveNavigator.swift` / `FinderStyleArchiveNavigator.swift` — right pane: browses the in-progress archive. `ArchiveModel` (`ObservableObject`) tracks archive contents, source URLs, and navigation state.
- Files are dragged from the left pane to the right to stage them for compression; `SaveDialog.swift` then handles format + compression-level selection and writes out via `NSSavePanel`.
- `FileDialogHelper.swift` wraps `NSSavePanel`/`NSOpenPanel` (which are completion-handler based) in `withCheckedContinuation` for async/await use.

**Compression system** (`Sources/Pressure/Compression/`): `CompressionManager` (`@MainActor`, `ObservableObject`) is the single coordinator — `ContentView` never calls a format-specific compressor directly. It switches on `CompressionFormat` and delegates to one of the static compressor structs in `Compression/Compressors/`, each implementing `compress()`/`decompress()` with an async progress callback (`(Double) async -> Void`):

- `ZIPCompressor` — ZIPFoundation, handles both read and write.
- `GZIPCompressor` — SWCompression; multi-file input becomes tar.gz.
- `TARCompressor` — SWCompression for *reading* only; TAR *writing* is hand-rolled (header/padding/checksums) since SWCompression has no TAR encoder.
- `BZIP2Compressor` — SWCompression; multi-file input becomes tar.bz2.
- `ZCompressor` — Apple's `Compression` framework using LZ4 (not classic LZW), single file only.

Format detection (`CompressionManager.detectFormat`) is purely extension-based.

When adding a new compression format: add the case to `CompressionFormat` (incl. `fileType: UTType`), add a compressor struct in `Compression/Compressors/`, add a case to both switches in `CompressionManager`, add matching tests under `Tests/PressureTests/Compression/Compressors/`. The Save dialog's format picker updates automatically since it iterates `CompressionFormat.allCases`.

## Conventions

- `CompressionManager` and `ArchiveModel` are `@MainActor` — test classes touching them must also be `@MainActor`.
- Progress callbacks are `async` (`(Double) async -> Void`), not just synchronous closures.
- Errors are a single `CompressionError` enum (`unsupportedFormat`, `compressionFailed`, `decompressionFailed`, `invalidInput`) conforming to `LocalizedError`.
- No external state-management library — plain SwiftUI `@State`/`@StateObject`/`ObservableObject`.

## Debugging

If Xcode's debugger fails to attach with "Unable to obtain a task name port right" (common with ad-hoc/unsigned Debug builds), see `DEBUGGING_TROUBLESHOOTING.md` and `MANUAL_DEBUG_FIX.md`. Quick paths:
- Debug config disables code signing/hardened runtime (`CODE_SIGNING_REQUIRED=NO` in `Project.swift`); Release re-enables it with `Resources/Pressure.entitlements`.
- `./debug_workaround.sh` builds the app via `xcodebuild` and drops you into `lldb` against the built binary directly, bypassing Xcode's attach flow.
- In Xcode, setting the scheme's Run action to "Wait for executable to be launched" and manually opening the built `.app` often fixes the attach failure.

## Git Workflow

- Commit: `Project.swift`, `Workspace.swift`, everything under `Sources/`/`Tests/`, docs.
- Never commit: `*.xcodeproj/`, `*.xcworkspace/`, `Derived/`, `xcuserdata/`, `.tuist-bin/` (all generated, gitignored).
