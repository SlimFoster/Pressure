# Debugging Troubleshooting Guide

If you're still getting the "Unable to obtain a task name port right" error, try these steps in order:

## Step 1: Clean Everything
1. **Quit Xcode completely** (⌘Q)
2. **Quit any running instances of Pressure app** (check Activity Monitor if needed)
3. **Clean build folder**: 
   ```bash
   cd /Users/adamfoster/dev/Pressure
   rm -rf build/ Derived/
   ```
4. **Regenerate project**:
   ```bash
   tuist generate
   ```

## Step 2: Verify Xcode Settings
1. Open `Pressure.xcworkspace` in Xcode
2. Select the **Pressure** scheme (not a test scheme)
3. Go to **Product → Scheme → Edit Scheme...**
4. Select **Run** in the left sidebar
5. Under **Info** tab, ensure:
   - Build Configuration is set to **Debug**
   - Executable is set to **Pressure.app**
6. Under **Options** tab, ensure:
   - **Debug executable** is checked ✓

## Step 3: Check Code Signing
1. Select the **Pressure** target in the project navigator
2. Go to **Signing & Capabilities** tab
3. For **Debug** configuration, verify:
   - Code Signing Identity: **- (Ad Hoc)**
   - Entitlements File: **Resources/Pressure.entitlements**
   - Hardened Runtime: **Disabled** (unchecked)

## Step 4: Verify Entitlements
1. Open `Resources/Pressure.entitlements` in Xcode
2. Ensure it contains:
   ```xml
   <key>com.apple.security.get-task-allow</key>
   <true/>
   ```

## Step 5: Try Manual Debugging
1. Build the app (⌘B)
2. **Don't run yet**
3. In Xcode, go to **Debug → Attach to Process...**
4. Select **Pressure** from the list
5. If the app isn't running, start it manually from Finder (open the built app)
6. Then try attaching

## Step 6: Check System Permissions
1. Open **System Settings → Privacy & Security**
2. Check if Xcode needs any permissions
3. If you see any prompts, grant them

## Step 7: Alternative - Use LLDB Directly
If Xcode debugging still fails, you can debug using command line:
```bash
# Build the app
xcodebuild -workspace Pressure.xcworkspace -scheme Pressure -configuration Debug

# Find the built app
# Then attach with lldb:
lldb /path/to/Pressure.app/Contents/MacOS/Pressure
```

## Step 8: Check Console Logs
1. Open **Console.app** (Applications → Utilities)
2. Filter for "Pressure" or "task name port"
3. Look for additional error messages that might give more context

## If Still Not Working
The issue might be macOS-specific. Try:
- Restart your Mac
- Update Xcode to the latest version
- Check if you have any security software that might be interfering
- Try creating a new user account and testing there




