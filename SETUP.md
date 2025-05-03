# Setup Instructions for Pressure

## Prerequisites

- macOS 13.0 or later
- Xcode 14.0 or later
- Swift 5.9 or later
- [Tuist](https://tuist.io) - Install via `mise` or Homebrew:
  ```bash
  brew install tuist
  # or with mise (if you have it installed)
  mise install tuist
  ```

## Quick Start

### Method 1: Using Tuist (Recommended)

1. **Generate the Xcode project:**
   ```bash
   cd /Users/adamfoster/dev/Pressure
   tuist generate
   ```
   This creates `Pressure.xcworkspace` from `Project.swift` and `Workspace.swift`.

2. **Open the workspace:**
   ```bash
   open Pressure.xcworkspace
   ```
   Or double-click `Pressure.xcworkspace` in Finder.

3. **Build and run:**
   - Press ⌘R or click the Play button
   - The app should compile and launch

### Method 2: Manual Xcode Project (Not Recommended)

If you prefer not to use Tuist, you can create a manual Xcode project, but you'll need to manually configure all targets and settings. Using Tuist is strongly recommended as it keeps the project configuration in code.

## Troubleshooting

### Issue: "Cannot find type 'NSSavePanel' in scope"
**Solution:** Make sure `import AppKit` is present in files that use AppKit classes.

### Issue: "Value of type 'UTType' has no member 'identifier'"
**Solution:** This might occur in older Swift versions. Replace `.identifier` with `.rawValue` or update to Swift 5.9+.

### Issue: Compression commands not found
**Solution:** The app uses system commands (`zip`, `gzip`, `tar`, etc.) which should be available on macOS by default. If they're missing, install Xcode Command Line Tools:
```bash
xcode-select --install
```

### Issue: Build errors related to file types
**Solution:** Make sure all Swift files are added to the Xcode target. Check the "Target Membership" in the File Inspector (right panel) for each file.

## Project Structure

```
Pressure/
├── Project.swift               # Tuist project configuration
├── Workspace.swift              # Tuist workspace configuration
├── Sources/
│   └── Pressure/               # Main app source files
│       ├── PressureApp.swift  # App entry point
│       ├── ContentView.swift  # SwiftUI user interface
│       ├── CompressionManager.swift  # Compression logic
│       └── FileDialogHelper.swift    # File dialog helpers
├── Resources/
│   └── Info.plist              # App metadata
├── Tests/                       # Test targets
│   ├── PressureTests/          # Unit tests
│   └── PressureUITests/        # UI tests
├── README.md                    # Project documentation
└── .gitignore                  # Git ignore rules
```

## Working with Tuist

- **Regenerate project after changes:** Run `tuist generate` whenever you modify `Project.swift` or `Workspace.swift`
- **Clean generated files:** Run `tuist clean` to remove generated Xcode files
- **Edit project:** Modify `Project.swift` to change targets, settings, or dependencies
- **The generated `.xcodeproj` and `.xcworkspace` are ignored by git** - they're generated from the Swift files

## Next Steps

- Customize the app icon and bundle identifier
- Add compression level options
- Implement password protection for ZIP files
- Add support for RAR compression (requires libunrar)
- Add 7z format support
