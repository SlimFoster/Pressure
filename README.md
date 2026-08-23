# Pressure - macOS Compression App

A modern macOS application for compressing and decompressing files in multiple formats.

## Supported Formats

- **ZIP** - Standard zip archives
- **GZIP** - GNU zip compression
- **TAR** - Tape archive format
- **BZIP2** - Block-sorting file compressor
- **Z** - Unix compress format (uses LZ4 via Apple's Compression framework, not classic LZW)
- **RAR** - RAR archive format (not yet implemented — throws `unsupportedFormat`; would require an external library such as libunrar)

## Features

- Modern SwiftUI interface with a Finder-style two-pane layout
- Support for multiple compression formats
- Batch file compression
- Progress tracking
- Drag and drop file selection
- Decompression support for all implemented formats

## Requirements

- macOS 13.0 or later
- Xcode 14.0 or later
- Swift 5.9 or later
- [Tuist](https://tuist.io) - For project generation and dependency management

## Dependencies

The project uses the following Swift libraries (managed via Tuist):

- **ZIPFoundation** - ZIP archive creation and extraction
- **SWCompression** - GZIP, TAR (reading only), and BZIP2 compression/decompression

Dependencies are automatically resolved when you run `tuist generate`.

## Setup Instructions

### Prerequisites

- macOS 13.0 or later
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

1. Launch the app
2. Browse files in the left pane and drag them into the archive pane on the right
3. Click Save (or Save As) to open the Save dialog, choose a format and compression level, and write the archive
4. To decompress, open an existing archive and browse or extract its contents

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
│       │       └── ZCompressor.swift
│       └── Views/
│           ├── PressureApp.swift                 # App entry point (@main)
│           ├── ContentView.swift                 # Two-pane layout
│           ├── FileSystemNavigator.swift          # Left pane: file system browser
│           ├── FinderStyleNavigator.swift        # Finder-style file system implementation
│           ├── ArchiveNavigator.swift             # Right pane: archive browser (+ ArchiveModel)
│           ├── FinderStyleArchiveNavigator.swift # Finder-style archive implementation
│           ├── SaveDialog.swift                   # Format + compression level selection
│           └── FileDialogHelper.swift             # Async wrappers for NSSavePanel/NSOpenPanel
├── Resources/
│   ├── Info.plist              # App metadata
│   └── Pressure.entitlements   # Release code-signing entitlements
└── Tests/
    ├── PressureTests/          # Unit tests (mirrors Sources/Pressure/Compression)
    └── PressureUITests/        # UI tests
```

## Architecture

- **PressureApp.swift** - Main app entry point
- **ContentView.swift** - Two-pane SwiftUI layout (file system pane + archive pane)
- **CompressionManager** - `@MainActor` coordinator that delegates to a per-format compressor struct in `Compression/Compressors/`
- **FileDialogHelper.swift** - Async wrappers around AppKit's completion-handler-based `NSSavePanel`/`NSOpenPanel`

## Future Enhancements

- RAR compression/decompression support (requires libunrar)
- 7z format support
- Password protection for ZIP files
- Archive preview
- Batch operations

## License

MIT License
