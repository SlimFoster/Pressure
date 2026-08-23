# Manual Debugging Fix Guide

Since the automatic configuration isn't working, here's how to manually fix the debugging issue in Xcode:

## Method 1: Manual Scheme Configuration (Try This First)

1. **Open Xcode** and open `Pressure.xcworkspace`

2. **Edit the Scheme:**
   - Click on the scheme selector (next to the Run button)
   - Select **Edit Scheme...**
   - Select **Run** in the left sidebar

3. **Configure the Run Action:**
   - **Info Tab:**
     - Build Configuration: **Debug**
     - Executable: **Pressure.app** (should be auto-selected)
     - **Launch:** Select **Wait for executable to be launched** (this is key!)
   
   - **Options Tab:**
     - ✓ **Debug executable** (should be checked)
     - **Debugger:** **LLDB**
     - **Build Configuration:** **Debug**

4. **Save** the scheme

5. **Now try debugging:**
   - Build the app (⌘B)
   - Set your breakpoints
   - Press **⌘R** to run
   - **Manually launch the app** from Finder (open the built app in `build/Debug/Pressure.app`)
   - Xcode should automatically attach the debugger

## Method 2: Use "Attach to Process"

1. **Build the app** (⌘B) - **don't run it yet**

2. **Manually launch the app:**
   ```bash
   open build/Debug/Pressure.app
   ```
   Or find it in Finder and double-click

3. **In Xcode:**
   - Go to **Debug → Attach to Process...**
   - Select **Pressure** from the list
   - The debugger should attach

4. **Set breakpoints** - they should work now

## Method 3: Use the Debug Workaround Script

Run the provided script:
```bash
./debug_workaround.sh
```

This will build the app and give you instructions for using lldb directly.

## Method 4: Use Print Statements (Temporary Workaround)

If debugging still doesn't work, you can use print statements and logging:

```swift
// Add this at the top of files you want to debug
#if DEBUG
import os.log
private let logger = Logger(subsystem: "com.pressure.Pressure", category: "Debug")
#endif

// Then use it:
#if DEBUG
logger.debug("Debug message: \(variable)")
print("Debug: \(variable)")
#endif
```

View logs in Console.app or Xcode's console.

## Method 5: Check System-Level Issues

1. **Check macOS version:**
   ```bash
   sw_vers
   ```
   Some macOS versions have stricter debugging restrictions.

2. **Check Xcode version:**
   ```bash
   xcodebuild -version
   ```

3. **Verify Xcode permissions:**
   - System Settings → Privacy & Security → Full Disk Access
   - Make sure Xcode is listed and enabled

4. **Check if SIP is interfering:**
   ```bash
   csrutil status
   ```
   If it's enabled, that's normal, but it might explain the restrictions.

## Method 6: Create a New User Account

Sometimes macOS security policies are user-specific. Try:
1. Create a new admin user account
2. Log in as that user
3. Try debugging there

## Method 7: Disable System Integrity Protection (Not Recommended)

⚠️ **Warning:** Only do this if absolutely necessary and you understand the security implications.

```bash
# Boot into Recovery Mode (hold ⌘R during startup)
# Open Terminal
csrutil disable
# Reboot
```

**Remember to re-enable it later:**
```bash
csrutil enable
```

## What's Likely Happening

The error "Unable to obtain a task name port right" suggests macOS is blocking the debugger from attaching. This can happen when:
- The app is sandboxed (even if not explicitly)
- System Integrity Protection is blocking it
- Xcode doesn't have proper permissions
- There's a mismatch between how the app is signed and how the debugger expects to attach

The "Wait for executable to be launched" option (Method 1) often works because it changes the attachment timing, which can bypass some of these restrictions.

## Still Not Working?

If none of these work, the issue might be:
1. A bug in your specific macOS/Xcode version combination
2. A system-level security policy that can't be overridden
3. A corrupted Xcode installation

Consider:
- Updating Xcode to the latest version
- Updating macOS
- Reinstalling Xcode
- Reporting the issue to Apple Developer Forums




