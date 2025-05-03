# Pressure - macOS Compression App

A modern macOS application for compressing and decompressing files in multiple formats.

## Supported Formats

- **ZIP** - Standard zip archives
- **GZIP** - GNU zip compression
- **TAR** - Tape archive format
- **BZIP2** - Block-sorting file compressor
- **Z** - Unix compress format
- **RAR** - RAR archive format (decompression only, requires external library)

## Features

- Modern SwiftUI interface
- Support for multiple compression formats
- Batch file compression
- Progress tracking
- Drag and drop file selection
- Decompression support for all formats

## Requirements

- macOS 13.0 or later
- Xcode 14.0 or later
- Swift 5.9 or later
- [Tuist](https://tuist.io) - For project generation and dependency management

## Dependencies

The project uses the following Swift libraries (managed via Tuist):

- **ZIPFoundation** - ZIP archive support
- **SWCompression** - GZIP, TAR (reading), and BZIP2 support

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
2. Click "Select Files" to choose files to compress
3. Select your desired compression format
4. Click "Compress" and choose a save location
5. For decompression, click "Decompress" and select an archive file

## Project Structure

```
Pressure/
├── Project.swift              # Tuist project configuration
├── Workspace.swift             # Tuist workspace configuration
├── Sources/
│   └── Pressure/              # Main app source files
│       ├── PressureApp.swift  # App entry point
│       ├── ContentView.swift  # SwiftUI user interface
│       ├── CompressionManager.swift  # Compression logic
│       └── FileDialogHelper.swift    # File dialog helpers
├── Resources/
│   └── Info.plist            # App metadata
└── Tests/                     # Test targets
    ├── PressureTests/        # Unit tests
    └── PressureUITests/      # UI tests
```

## Architecture

- **PressureApp.swift** - Main app entry point
- **ContentView.swift** - SwiftUI user interface
- **CompressionManager.swift** - Handles all compression/decompression operations
- **FileDialogHelper.swift** - Async file dialog helpers

## Future Enhancements

- RAR compression support (requires libunrar)
- 7z format support
- Compression level selection
- Password protection for ZIP files
- Archive preview
- Batch operations

## License

MIT License
