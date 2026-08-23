# Pressure - macOS Compression App

A modern macOS application for compressing and decompressing files in multiple formats, with a Simple mode for quick one-off compression and a Power mode for full archive editing.

## Supported Formats

- **ZIP** - Standard zip archives, with real AES-256 password encryption (WinZip AE-2) and real disk-spanning splits
- **GZIP** - GNU zip compression
- **TAR** - Tape archive format
- **BZIP2** - Block-sorting file compressor
- **Z** - Unix compress format (uses LZ4 via Apple's Compression framework, not classic LZW)
- **RAR** - RAR archive format (not yet implemented — throws `unsupportedFormat`; would require an external library such as libunrar)

TAR, GZIP, BZIP2, and Z also support splitting into numbered volumes via generic byte-chunking (universally `cat`-joinable), rather than a format-native spanning scheme.

## Features

- **Simple mode** - a single drop zone for quick, one-off compression: drop files (or pick via a link), choose a format, save
- **Power mode** - a full archive-editing session: open or create an archive, then browse it via a Finder-style sidebar/table, add/delete/rename files, and Extract All — changes save immediately, no separate "export" step
- Real AES-256 password encryption for ZIP archives, compatible with Finder, 7-Zip, and other standard tools
- Real splitting into numbered volumes for every supported format
- Progress tracking
- Drag and drop file selection
- Decompression support for all implemented formats

## Requirements

- macOS 14.0 or later
- Xcode 14.0 or later
- Swift 5.9 or later
- [Tuist](https://tuist.io) - For project generation and dependency management

## Dependencies

The project uses the following Swift libraries (managed via Tuist):

- **ZIPFoundation** - ZIP archive creation and extraction (used when the archive isn't encrypted or split)
- **SWCompression** - GZIP, TAR (reading only), and BZIP2 compression/decompression

ZIP encryption and splitting are hand-rolled (see `Sources/Pressure/Compression/Compressors/ZIP/`) rather than pulled from a library, since neither of the above supports them. Encryption uses CommonCrypto (ships with the SDK) — no extra dependency needed.

Dependencies are automatically resolved when you run `tuist generate`.

## Setup Instructions

### Prerequisites

- macOS 14.0 or later
- Xcode 14.0 or later
- Swift 5.9 or later
- [Tuist](https://tuist.io) (install via `mise` or Homebrew: `brew install tuist`)

### Quick Start

1. **Generate the Xcode project:**
   ```bash
   tuist generate
   ```

2. **Open the workspace:**
   ```bash
   open Pressure.xcworkspace
   ```

3. **Build and run:**
   - Press ⌘R or click the Play button
   - The app should compile and launch

### Project Structure

The project uses [Tuist](https://tuist.io) for project generation:
- `Project.swift` - Defines the project structure and targets
- `Workspace.swift` - Defines the workspace configuration
- Run `tuist generate` to regenerate the Xcode project after changes

## Usage

**Simple mode**: drop files onto the window (or use "or choose files..."), pick a format, and save — straight to a save panel, no extra steps.

**Power mode**: open an existing archive or start a new one (drop files onto the empty state, or "New Archive…"). Browse its folder structure via the left sidebar, view/sort contents in the table, and use the toolbar to Extract All, Add Files, Delete, or Rename — every change writes to disk immediately. The right-hand inspector shows archive stats and lets you change Format/Compression, turn on password encryption, or split into volumes; both apply immediately.

## Project Structure

```
Pressure/
├── Project.swift               # Tuist project configuration
├── Workspace.swift              # Tuist workspace configuration
├── Sources/
│   └── Pressure/
│       ├── Compression/
│       │   ├── CompressionManager.swift    # Coordinator: delegates to format-specific compressors
│       │   ├── CompressionFormat.swift     # Format enum
│       │   ├── CompressionError.swift      # Error types
│       │   └── Compressors/
│       │       ├── ZIPCompressor.swift
│       │       ├── GZIPCompressor.swift
│       │       ├── TARCompressor.swift
│       │       ├── BZIP2Compressor.swift
│       │       ├── ZCompressor.swift
│       │       ├── GenericSplitCompressor.swift   # Byte-chunked splitting for TAR/GZIP/BZIP2/Z
│       │       └── ZIP/                            # Hand-rolled AES-256 encryption + disk-spanning
│       └── Views/
│           ├── PressureApp.swift        # App entry point (@main) + Settings scene
│           ├── ContentView.swift        # Switches between Simple and Power mode
│           ├── AppMode.swift            # Mode/appearance enums, @AppStorage-backed
│           ├── HeaderBar.swift          # Mode toggle, appearance, settings button
│           ├── SettingsView.swift
│           ├── ArchiveModel.swift       # Live archive-editing session (@MainActor ObservableObject)
│           ├── FileDialogHelper.swift   # Async wrappers for NSSavePanel/NSOpenPanel
│           ├── Simple/
│           │   └── SimpleModeView.swift # Drop zone + format picker + direct save
│           └── Power/
│               ├── PowerModeView.swift
│               ├── PowerToolbar.swift
│               ├── ArchiveSidebarView.swift
│               ├── ArchiveContentsTable.swift
│               ├── ArchiveInspectorPanel.swift
│               └── PasswordPromptSheet.swift
├── Resources/
│   ├── Info.plist              # App metadata
│   └── Pressure.entitlements   # Release code-signing entitlements
└── Tests/
    ├── PressureTests/          # Unit tests (mirrors Sources/Pressure/Compression, plus Views/)
    └── PressureUITests/        # UI tests
```

## Architecture

- **PressureApp.swift** - App entry point; also declares the Settings scene
- **ContentView.swift** - Switches between `SimpleModeView` and `PowerModeView`
- **CompressionManager** - `@MainActor` coordinator that delegates to a per-format compressor struct in `Compression/Compressors/`
- **ArchiveModel** - `@MainActor` live-editing session for Power mode: tracks archive contents, handles lazy extraction, and commits Add/Delete/Rename to disk immediately
- **FileDialogHelper.swift** - Async wrappers around AppKit's completion-handler-based `NSSavePanel`/`NSOpenPanel`

## Future Enhancements

- RAR compression/decompression support (requires libunrar)
- 7z format support
- Archive preview
- Batch operations

## License

MIT License
