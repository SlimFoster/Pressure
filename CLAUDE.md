# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pressure is a macOS compression app (SwiftUI + AppKit) supporting ZIP, GZIP, TAR, BZIP2, and Z compression/decompression, plus RAR decompression (not yet implemented — throws `unsupportedFormat`). ZIP supports real AES-256 password encryption (WinZip AE-2) and real splitting into numbered volumes; TAR/GZIP/BZIP2/Z support generic byte-chunked splitting. Targets macOS 14.0+, Swift 5.9+.

## Build System: Tuist

The Xcode project (`Pressure.xcodeproj`, `Pressure.xcworkspace`) is **generated** by Tuist from `Project.swift` and `Workspace.swift` — those two files are the source of truth and must never be hand-edited via the `.xcodeproj`. `Project.swift` also globs sources automatically (`Sources/Pressure/**/*.swift`, `Tests/PressureTests/**/*.swift`, `Tests/PressureUITests/**/*.swift`), so adding a new file needs no project edit — just regenerate.

```bash
tuist generate --no-open  # regenerate Xcode project after touching Project.swift/Workspace.swift, or after adding/removing source files
tuist clean                # remove generated Xcode files
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

**Simple / Power mode** (`ContentView.swift`): the app has two modes, toggled via `ModeToggleBar` (`HeaderBar.swift`) and persisted with `@AppStorage("appMode")` (`AppMode.swift`). `ContentView` just switches between the two — `CompressionManager` and `ArchiveModel` are owned at this level so an open Power-mode session survives toggling to Simple and back.

- **Simple mode** (`Views/Simple/SimpleModeView.swift`) — a single drop zone + format picker + "or choose files..." link. No options beyond format; Save goes straight to `NSSavePanel` and compresses directly. No archive-editing session involved.
- **Power mode** (`Views/Power/`) — an archive-*editing* session, not a "stage files then export" flow:
  - `PowerModeView.swift` — header (archive name/stats) + `PowerToolbar` (Extract All / Add Files / Delete / Rename / search) + `HSplitView { ArchiveSidebarView; ArchiveContentsTable }`, with `ArchiveInspectorPanel` attached via SwiftUI's native `.inspector()` modifier.
  - `ArchiveSidebarView.swift` — `NSOutlineView`-based folder tree of the open archive (not the filesystem — Power mode has no filesystem browser pane at all).
  - `ArchiveContentsTable.swift` — `NSTableView`-based listing (Name/Kind/Size/Packed/Ratio/Modified) of the current folder.
  - `ArchiveInspectorPanel.swift` — archive stats, Format/Compression picker, and the real Encrypt and Split controls (see below).
  - `PasswordPromptSheet.swift` — shown when opening an archive that turns out to be encrypted.
- `ArchiveModel` (`ArchiveModel.swift`, `@MainActor`, `ObservableObject`) is the live-editing session: `items`/`currentPath`/`currentItems`/`archiveURL`/`password`/`splitVolumeSize` are all `@Published` — **if you add a new piece of session state, it must be `@Published` too**, or Power mode's reactive UI (e.g. the empty-state-vs-loaded branch) will silently stop updating. Add/Delete/Rename call `commit()`, which rewrites the archive on disk immediately (a full rebuild from `items` each time, not incremental `ZIPFoundation.update` — simpler, format-agnostic, works identically whether encryption/splitting are on). Entries from an opened archive are extracted lazily via `extractedURL(for:)`, only when their bytes are actually needed — opening an archive lists its contents from metadata alone, no eager extraction.
- `FileDialogHelper.swift` wraps `NSSavePanel`/`NSOpenPanel` (completion-handler based) in `withCheckedContinuation` for async/await use.

**Compression system** (`Sources/Pressure/Compression/`): `CompressionManager` (`@MainActor`, `ObservableObject`) is the single coordinator — views never call a format-specific compressor directly. It switches on `CompressionFormat` and delegates to one of the static compressor structs in `Compression/Compressors/`, each implementing `compress()`/`decompress()` with an async progress callback (`(Double) async -> Void`):

- `ZIPCompressor` — ZIPFoundation, handles both read and write; also exposes `listEntries(at:)` (metadata straight from the central directory, no extraction) and `extractEntry(path:from:to:)` (single-entry extraction) used by `ArchiveModel`'s lazy-loading.
- `GZIPCompressor` — SWCompression; multi-file input becomes tar.gz.
- `TARCompressor` — SWCompression for *reading* only; TAR *writing* is hand-rolled (header/padding/checksums) since SWCompression has no TAR encoder.
- `BZIP2Compressor` — SWCompression; multi-file input becomes tar.bz2.
- `ZCompressor` — Apple's `Compression` framework using LZ4 (not classic LZW), single file only.

Format detection (`CompressionManager.detectFormat`) is purely extension-based.

**ZIP encryption** (`Compression/Compressors/ZIP/`) — real WinZip AE-2 AES-256, hand-rolled since neither ZIPFoundation nor SWCompression support it (ZIPFoundation can't even read encrypted entries). `AESEncryption.swift` wraps CommonCrypto for PBKDF2 key derivation and AES-CTR; note WinZip's counter is **little-endian starting at 1**, unlike CommonCrypto's/OpenSSL's native big-endian `kCCModeCTR` — the code deliberately generates the keystream manually via per-block AES-ECB + XOR rather than trusting the built-in CTR mode. `ZIPBinaryStructures.swift` has the shared little-endian read/write helpers, DOS date/time conversion, and the `0x9901` AE-x extra field. `EncryptedZIPWriter.swift`/`EncryptedZIPReader.swift` build/parse the archive. `CompressionManager.compress(fileMappings:...password:...)` routes to this path only when a password is given; otherwise `ZIPCompressor` (ZIPFoundation) is used unchanged.

**Splitting** (`CompressionManager.compressSplit`/`rejoinSplit`) — three tiers:
- **ZIP**: `SplitZIPWriter.swift`/`SplitZIPArchive.swift` — real APPNOTE-style disk-spanning (`.z01`/`.z02`/…/`.zip` naming, `0x08074b50` spanning signature), verified empirically against Info-Zip's `zip -s` reference output. Scoped deliberately: guarantees a byte-perfect round trip through Pressure's own `rejoin`, but doesn't implement true per-disk-local addressing for every central-directory entry (see the doc comment in `SplitZIPWriter.swift`) — a different tool reading the raw volumes directly, without rejoining first, isn't guaranteed to work.
- **TAR/GZIP/BZIP2/Z**: `GenericSplitCompressor.swift` — plain byte-chunked splitting (`.001`, `.002`, …), universally `cat`-joinable. TAR uses this too rather than GNU tar's multi-volume format — a deliberate scope call (that format is poorly documented and there's no GNU tar available locally to verify against), not an oversight.
- `ArchiveModel.splitVolumeSize` integrates splitting into the live-editing session: when set, `commit()` writes an internal unsplit working copy (used for browsing/lazy-extraction — split volumes on disk aren't directly readable) and splits *that* into the real volumes at `archiveURL`.

When adding a new compression format: add the case to `CompressionFormat` (incl. `fileType: UTType`), add a compressor struct in `Compression/Compressors/`, add a case to both switches in `CompressionManager`, add matching tests under `Tests/PressureTests/Compression/Compressors/`. The format picker updates automatically since it iterates `CompressionFormat.allCases`.

## Conventions

- `CompressionManager` and `ArchiveModel` are `@MainActor` — test classes touching them must also be `@MainActor`.
- Every piece of `ArchiveModel` session state that a view branches on reactively must be `@Published` — a plain `var` silently breaks SwiftUI's re-render (bit us once with `archiveURL`).
- Progress callbacks are `async` (`(Double) async -> Void`), not just synchronous closures.
- Errors are a single `CompressionError` enum (`unsupportedFormat`, `compressionFailed`, `decompressionFailed`, `invalidInput`, `incorrectPassword`, `corruptedEncryptedArchive`) conforming to `LocalizedError`.
- No external state-management library — plain SwiftUI `@State`/`@StateObject`/`ObservableObject`.
- When hand-rolling a binary format (TAR headers, ZIP structures, AES/PBKDF2 primitives), verify against a real reference implementation or tool empirically rather than from memory/spec paraphrase alone — spec text is easy to misread, and a subtly wrong byte offset or endianness assumption fails silently rather than erroring loudly.

## Debugging

If Xcode's debugger fails to attach with "Unable to obtain a task name port right" (common with ad-hoc/unsigned Debug builds), see `DEBUGGING_TROUBLESHOOTING.md` and `MANUAL_DEBUG_FIX.md`. Quick paths:
- Debug config disables code signing/hardened runtime (`CODE_SIGNING_REQUIRED=NO` in `Project.swift`); Release re-enables it with `Resources/Pressure.entitlements`.
- `./debug_workaround.sh` builds the app via `xcodebuild` and drops you into `lldb` against the built binary directly, bypassing Xcode's attach flow.
- In Xcode, setting the scheme's Run action to "Wait for executable to be launched" and manually opening the built `.app` often fixes the attach failure.

## Git Workflow

- Commit: `Project.swift`, `Workspace.swift`, everything under `Sources/`/`Tests/`, docs.
- Never commit: `*.xcodeproj/`, `*.xcworkspace/`, `Derived/`, `xcuserdata/`, `.tuist-bin/` (all generated, gitignored).
