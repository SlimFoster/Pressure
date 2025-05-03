# AGENTS.md - Project Knowledge Base

This document provides comprehensive information about the Pressure project for AI agents and developers.

## Project Overview

**Pressure** is a macOS compression application built with SwiftUI. It provides a graphical user interface for compressing and decompressing files in multiple formats including ZIP, GZIP, TAR, BZIP2, Z, and RAR (decompression only).

### Key Characteristics
- **Platform**: macOS 13.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Build System**: Tuist (project generation)
- **Architecture**: MVVM-like with SwiftUI

## Project Structure

```
Pressure/
├── Project.swift              # Tuist project configuration (SOURCE OF TRUTH)
├── Workspace.swift             # Tuist workspace configuration
│
├── Sources/
│   └── Pressure/              # Main app target source files
│       ├── Compression/       # Compression logic (organized by format)
│       │   ├── CompressionManager.swift    # Main coordinator
│       │   ├── CompressionFormat.swift     # Format enum
│       │   ├── CompressionError.swift      # Error types
│       │   └── Compressors/                 # Individual format implementations
│       │       ├── ZIPCompressor.swift
│       │       ├── GZIPCompressor.swift
│       │       ├── TARCompressor.swift
│       │       ├── BZIP2Compressor.swift
│       │       └── ZCompressor.swift
│       └── Views/              # UI components
│           ├── PressureApp.swift            # App entry point (@main, WindowGroup)
│           ├── ContentView.swift             # Main SwiftUI view
│           └── FileDialogHelper.swift       # Async wrappers for NSSavePanel/NSOpenPanel
│
├── Resources/
│   └── Info.plist            # App metadata (bundle ID, version, etc.)
│
├── Tests/
│   ├── PressureTests/         # Unit tests
│   │   └── Compression/       # Compression tests (mirrors source structure)
│   │       ├── TestHelpers.swift            # Shared test utilities
│   │       ├── CompressionFormatTests.swift
│   │       ├── CompressionErrorTests.swift
│   │       ├── CompressionManagerTests.swift
│   │       └── Compressors/                 # Individual compressor tests
│   │           ├── ZIPCompressorTests.swift
│   │           ├── GZIPCompressorTests.swift
│   │           ├── TARCompressorTests.swift
│   │           ├── BZIP2CompressorTests.swift
│   │           └── ZCompressorTests.swift
│   └── PressureUITests/       # UI tests
│       ├── PressureUITests.swift
│       └── PressureUITestsLaunchTests.swift
│
└── Documentation/
    ├── README.md              # User-facing documentation
    ├── SETUP.md                # Setup instructions
    └── AGENTS.md               # This file
```

## Build System: Tuist

**IMPORTANT**: This project uses **Tuist** for project generation. The Xcode project files (`.xcodeproj`, `.xcworkspace`) are **generated** and should **NOT** be committed to git.

### Key Commands
```bash
# Generate Xcode project from Project.swift
tuist generate

# Clean generated files
tuist clean

# Open generated workspace
open Pressure.xcworkspace
```

### Project Configuration
- **Source of Truth**: `Project.swift` and `Workspace.swift`
- **Generated Files**: Ignored by git (see `.gitignore`)
- **Targets**: 
  - `Pressure` (main app)
  - `PressureTests` (unit tests)
  - `PressureUITests` (UI tests)

### Schemes
The project has three separate schemes for independent execution:
- **Pressure** - Build and run the app only (no tests)
- **PressureTests** - Build and run unit tests only
- **PressureUITests** - Build and run UI tests only

This allows running tests independently from the app in Xcode.

### After Making Changes
1. Modify `Project.swift` if adding targets, dependencies, or settings
2. Run `tuist generate` to regenerate Xcode project
3. Never manually edit `.xcodeproj` files

## Key Components

### 1. PressureApp.swift
- **Purpose**: App entry point
- **Key Features**:
  - `@main` struct implementing `App` protocol
  - Defines `WindowGroup` with default size (800x600)
  - Creates `ContentView` as root view

### 2. ContentView.swift
- **Purpose**: Main user interface
- **Key Features**:
  - File selection UI with `fileImporter`
  - Format picker (segmented control)
  - Compress/Decompress buttons
  - Progress indicator
  - Status message display
- **State Management**:
  - `@StateObject` for `CompressionManager`
  - `@State` for UI state (selectedFiles, format, progress, etc.)
- **User Interactions**:
  - File selection via system file picker
  - Format selection via segmented control
  - Compression with save dialog
  - Decompression with file and directory pickers

### 3. Compression System
The compression system is organized into separate files for better maintainability:

#### CompressionManager.swift
- **Purpose**: Main coordinator that delegates to format-specific compressors
- **Key Features**:
  - `@MainActor` class (all methods run on main thread)
  - Supports multiple formats: ZIP, GZIP, TAR, BZIP2, Z, RAR
  - Async/await API with progress callbacks
  - Delegates to format-specific compressor structs
- **Public API**:
  ```swift
  func compress(files: [URL], to: URL, format: CompressionFormat, progress: @escaping (Double) async -> Void) async throws -> URL
  func decompress(file: URL, to: URL, progress: @escaping (Double) async -> Void) async throws -> [URL]
  func detectFormat(from: URL) -> CompressionFormat
  ```

#### CompressionFormat.swift
- **Purpose**: Format enumeration
- **Cases**: `.zip`, `.gzip`, `.tar`, `.bzip2`, `.z`, `.rar`
- **Properties**: `fileType: UTType` for each format

#### CompressionError.swift
- **Purpose**: Error type definitions
- **Cases**: `.unsupportedFormat(String)`, `.compressionFailed(String)`, `.decompressionFailed(String)`, `.invalidInput(String)`
- **Features**: Implements `LocalizedError` with descriptive messages

#### Compressor Implementations
Each format has its own compressor struct in `Compression/Compressors/`:
- **ZIPCompressor** - Uses ZIPFoundation library
- **GZIPCompressor** - Uses SWCompression's GzipArchive
- **TARCompressor** - Uses SWCompression for reading, custom implementation for writing
- **BZIP2Compressor** - Uses SWCompression's BZip2
- **ZCompressor** - Uses Swift's Compression framework (LZ4)

All compressors are static structs with `compress()` and `decompress()` methods.

### 4. FileDialogHelper.swift
- **Purpose**: Async wrappers for AppKit file dialogs
- **Key Features**:
  - `NSSavePanel.showSavePanel()` - async save dialog
  - `NSOpenPanel.showOpenPanel()` - async open dialog
  - Uses `withCheckedContinuation` for async/await compatibility

## Testing

### Unit Tests (PressureTests)
- **Location**: `Tests/PressureTests/Compression/`
- **Organization**: Tests mirror the source structure with separate files for each component
- **Test Files**:
  - `TestHelpers.swift` - Shared utilities for creating test files, directories, etc.
  - `CompressionFormatTests.swift` - Format enum tests
  - `CompressionErrorTests.swift` - Error type tests
  - `CompressionManagerTests.swift` - Manager coordination, format detection, error handling
  - `Compressors/*Tests.swift` - Individual compressor tests (one per format)
- **Coverage** (50+ tests):
  - Format detection for all formats (including edge cases)
  - Compression/decompression for all formats with round-trip verification
  - Error handling (empty files, invalid paths, unsupported formats, corrupted archives)
  - Progress reporting (verifies start, end, and monotonic progression)
  - Edge cases (empty files, special characters, nested directories, multi-file archives)
  - Content integrity (verifies original content matches after round-trip)
  - File size verification
  - Multi-file compression (tar.gz, tar.bz2)

### UI Tests (PressureUITests)
- **Location**: `Tests/PressureUITests/`
- **Coverage**:
  - App launch
  - UI element presence
  - Button interactions
  - Format picker
  - File selection
  - Window management

### Running Tests
```bash
# From Xcode: Select scheme and press ⌘U
#   - PressureTests scheme: Run unit tests only
#   - PressureUITests scheme: Run UI tests only
#   - Pressure scheme: Build/run app (no tests)

# From command line:
# Unit tests only
xcodebuild test -workspace Pressure.xcworkspace -scheme PressureTests -destination 'platform=macOS'

# UI tests only
xcodebuild test -workspace Pressure.xcworkspace -scheme PressureUITests -destination 'platform=macOS'
```

## Code Conventions

### Swift Concurrency
- Uses async/await throughout
- `CompressionManager` is `@MainActor` (all methods on main thread)
- Progress callbacks are async: `(Double) async -> Void`
- File dialogs use async wrappers

### Error Handling
- Uses `throws` for error propagation
- Custom `CompressionError` enum
- Errors are localized with descriptive messages

### State Management
- SwiftUI `@State` and `@StateObject` for UI state
- `ObservableObject` for `CompressionManager`
- No external state management libraries

### File Organization
- **Source Code**:
  - `Compression/` - All compression logic organized by format
  - `Views/` - All UI components
  - Clear separation of concerns: each format has its own compressor
- **Tests**:
  - Mirror source structure: `Tests/PressureTests/Compression/` matches `Sources/Pressure/Compression/`
  - Separate test files for each component
  - Shared test helpers in `TestHelpers.swift`

## Dependencies

### External Dependencies (via Tuist/SPM)
- **ZIPFoundation** (https://github.com/weichsel/ZIPFoundation) - ZIP archive creation and extraction
  - Used for: ZIP compression and decompression
  - Version: 0.9.0+
- **SWCompression** (https://github.com/tsolomko/SWCompression) - Compression and archive formats
  - Used for: GZIP, TAR (reading), BZIP2 compression/decompression
  - Version: 4.8.0+
  - Note: TAR creation is implemented manually (SWCompression doesn't support TAR writing)

### Swift Frameworks
- **SwiftUI** - UI framework
- **AppKit** - File dialogs, NSFileCoordinator
- **Foundation** - URL, FileManager
- **Compression** - Compression algorithms (used for Z format - LZ4)
- **UniformTypeIdentifiers** - File type identification

### Build Tools
- **Tuist** - Project generation and dependency management (required)
- **Xcode** - IDE and build tool
- **Swift Package Manager** - Dependency resolution (via Tuist)

## Common Tasks

### Adding a New Compression Format

1. **Add format to enum** (`Compression/CompressionFormat.swift`):
   ```swift
   enum CompressionFormat: String, CaseIterable {
       // ... existing cases
       case newFormat
   }
   ```

2. **Add fileType** in `CompressionFormat.swift`:
   ```swift
   case .newFormat:
       return UTType(filenameExtension: "ext") ?? .data
   ```

3. **Create compressor** (`Compression/Compressors/NewFormatCompressor.swift`):
   ```swift
   struct NewFormatCompressor {
       static func compress(...) async throws -> URL { ... }
       static func decompress(...) async throws -> [URL] { ... }
   }
   ```

4. **Update CompressionManager** to delegate to new compressor:
   ```swift
   case .newFormat:
       return try await NewFormatCompressor.compress(...)
   ```

5. **Add tests**:
   - Create `Tests/PressureTests/Compression/Compressors/NewFormatCompressorTests.swift`
   - Add format detection test in `CompressionManagerTests.swift`

6. **Update UI** - Format picker will automatically include it (uses `CompressionFormat.allCases`)

### Adding a New Source File

1. **Place file in correct location**:
   - App code: `Sources/Pressure/`
   - Tests: `Tests/PressureTests/` or `Tests/PressureUITests/`

2. **No need to modify Project.swift** - Tuist globs all `.swift` files automatically:
   - `Sources/Pressure/**/*.swift` for app
   - `Tests/PressureTests/**/*.swift` for unit tests

3. **Regenerate project**: `tuist generate`

### Modifying Project Settings

1. **Edit `Project.swift`**:
   - Add dependencies
   - Modify build settings
   - Add new targets
   - Change deployment target

2. **Regenerate**: `tuist generate`

3. **Never edit** `.xcodeproj` files directly

### Adding Dependencies

The project uses Tuist's package management. To add a new dependency:

1. **Edit `Project.swift`** - Add package to `packages` array:
   ```swift
   packages: [
       .remote(url: "https://github.com/...", requirement: .upToNextMajor(from: "1.0.0")),
   ],
   ```

2. **Add to target dependencies**:
   ```swift
   dependencies: [
       .target(name: "Pressure"),
       .package(product: "PackageName", type: .runtime),
   ]
   ```

3. **Regenerate**: `tuist generate` (this will resolve and download dependencies)

4. **Import in code**: `import PackageName`

## Important Notes

### MainActor Isolation
- `CompressionManager` is `@MainActor` - all methods must be called from main thread
- Tests use `@MainActor` class to handle this
- UI updates happen on main thread automatically with SwiftUI

### Library-Based Compression
The project uses Swift libraries instead of system commands for better reliability and cross-platform compatibility:

- **ZIP**: Uses ZIPFoundation library for both creation and extraction
  - Implementation: `ZIPCompressor.swift`
  - Supports multiple files and nested directories
  
- **GZIP**: Uses SWCompression's GzipArchive for compression/decompression
  - Implementation: `GZIPCompressor.swift`
  - Single files: Direct GZIP compression
  - Multiple files: Creates tar.gz (TAR + GZIP)
  
- **TAR**: 
  - Implementation: `TARCompressor.swift`
  - Reading: Uses SWCompression's TarContainer
  - Writing: Custom TAR format implementation (SWCompression doesn't support TAR creation)
  - Includes manual TAR header creation with proper padding and checksums
  
- **BZIP2**: Uses SWCompression's BZip2 for compression/decompression
  - Implementation: `BZIP2Compressor.swift`
  - Single files: Direct BZIP2 compression
  - Multiple files: Creates tar.bz2 (TAR + BZIP2)
  
- **Z**: Uses Swift's Compression framework with LZ4 algorithm
  - Implementation: `ZCompressor.swift`
  - Note: Uses LZ4 instead of LZW (original Z format) as LZW is not available in Compression framework
  - Only supports single file compression

All operations run in background tasks (`Task.detached` or `DispatchQueue.global`), results return via async/await.

### File Dialog Handling
- System file dialogs are synchronous, wrapped in async helpers
- Uses `begin(completionHandler:)` with continuations
- Must be called from main thread

### Progress Reporting
- Progress callbacks are async: `(Double) async -> Void`
- Currently basic implementation (may not report accurate progress for all formats)
- UI updates via `@MainActor.run`

### RAR Support
- RAR is listed but **not implemented** (throws `unsupportedFormat` error)
- Would require external library (libunrar)
- Currently only format detection works

## Git Workflow

### Ignored Files
- `*.xcodeproj/` - Generated Xcode project
- `*.xcworkspace/` - Generated workspace
- `.tuist-bin/` - Tuist binaries
- `Derived/` - Build artifacts
- `xcuserdata/` - User-specific Xcode settings

### Committed Files
- `Project.swift` - **MUST BE COMMITTED** (source of truth)
- `Workspace.swift` - **MUST BE COMMITTED**
- All source files in `Sources/`
- All test files in `Tests/`
- Documentation files

### After Cloning
1. Install Tuist: `brew install tuist` or `mise install tuist`
2. Generate project: `tuist generate`
3. Open workspace: `open Pressure.xcworkspace`

## Troubleshooting

### Build Errors
- **"Cannot find module"**: Run `tuist generate` to regenerate project
- **"Main actor isolation"**: Ensure `@MainActor` is used correctly
- **"Command not found"**: Ensure Xcode Command Line Tools installed: `xcode-select --install`

### Test Failures
- **Main actor errors**: Tests must be `@MainActor` class
- **File not found**: Check test file paths in `CompressionManagerTests`

### Project Generation Issues
- **Tuist not found**: Install via `brew install tuist` or `mise install tuist`
- **Syntax errors in Project.swift**: Check Tuist documentation for correct syntax

## Future Enhancements (Not Yet Implemented)

- RAR compression support (requires libunrar)
- 7z format support
- Compression level selection
- Password protection for ZIP files
- Archive preview
- Batch operations
- More accurate progress reporting
- Drag and drop file support

## Quick Reference

### File Locations
- **App Entry**: `Sources/Pressure/Views/PressureApp.swift`
- **Main UI**: `Sources/Pressure/Views/ContentView.swift`
- **Core Logic**: `Sources/Pressure/Compression/CompressionManager.swift`
- **Format Compressors**: `Sources/Pressure/Compression/Compressors/`
- **Helpers**: `Sources/Pressure/Views/FileDialogHelper.swift`
- **Project Config**: `Project.swift` (root)
- **Resources**: `Resources/Info.plist`
- **Test Helpers**: `Tests/PressureTests/Compression/TestHelpers.swift`

### Key Commands
```bash
tuist generate          # Generate Xcode project
open Pressure.xcworkspace  # Open in Xcode
xcodebuild -workspace Pressure.xcworkspace -scheme Pressure build  # Build from CLI
```

### Key Classes/Structs
- `PressureApp` - App entry point
- `ContentView` - Main UI view
- `CompressionManager` - Compression coordinator (@MainActor, ObservableObject)
- `CompressionFormat` - Format enum
- `CompressionError` - Error enum
- `ZIPCompressor`, `GZIPCompressor`, `TARCompressor`, `BZIP2Compressor`, `ZCompressor` - Format-specific compressors
- `FileDialogHelper` - File dialog extensions
- `CompressionTestHelpers` - Shared test utilities

---

**Last Updated**: December 2024
**Maintained By**: Project maintainers
**For Questions**: Refer to Tuist documentation, SwiftUI documentation, or project README

## Recent Changes

### Test Organization (December 2024)
- Tests reorganized to mirror source structure
- Separate test files for each compressor
- Added `CompressionErrorTests.swift` for error type coverage
- Enhanced test helpers with utilities for edge case testing
- Improved test coverage to 50+ tests with round-trip verification

### Code Organization (December 2024)
- Compression logic separated into individual compressor files
- Views separated into `Views/` directory
- Compression code organized in `Compression/` with `Compressors/` subdirectory
- Better separation of concerns and maintainability

### Scheme Organization (December 2024)
- Created separate schemes for app, unit tests, and UI tests
- Allows independent execution of tests without building/running app
