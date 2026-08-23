#!/bin/bash
# Workaround script for debugging Pressure app when Xcode debugger fails
# This script builds the app and launches it with lldb attached

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "Building Pressure app..."
xcodebuild -workspace Pressure.xcworkspace \
           -scheme Pressure \
           -configuration Debug \
           -derivedDataPath build \
           build

APP_PATH="build/Build/Products/Debug/Pressure.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Pressure"

if [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Error: App not found at $EXECUTABLE_PATH"
    echo "Build may have failed. Check the output above."
    exit 1
fi

echo ""
echo "App built successfully!"
echo ""
echo "To debug with lldb:"
echo "1. Run: lldb $EXECUTABLE_PATH"
echo "2. In lldb, type: run"
echo "3. Set breakpoints with: breakpoint set --name functionName"
echo "4. Continue with: continue"
echo ""
echo "Or attach to running process:"
echo "1. Launch the app: open $APP_PATH"
echo "2. Find the PID: ps aux | grep Pressure"
echo "3. Attach: lldb -p <PID>"
echo ""
echo "Press Enter to launch app with lldb now, or Ctrl+C to cancel..."
read

lldb "$EXECUTABLE_PATH"




