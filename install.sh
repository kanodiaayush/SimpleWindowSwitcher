#!/bin/bash

set -e

echo "🚀 Installing SimpleWindowSwitcher"
echo "=================================="
echo ""
echo "This installs the working version of SimpleWindowSwitcher."
echo ""

APP_BUNDLE="/Applications/SimpleWindowSwitcher.app"

# Build the working version (release mode for better performance)
echo "📦 Building release version..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

EXECUTABLE=".build/release/SimpleWindowSwitcher"

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Executable not found at $EXECUTABLE"
    exit 1
fi

echo "✅ Built working version successfully"

# Create app bundle (preserve existing if it exists to keep permissions)
echo "📁 Ensuring app bundle exists at $APP_BUNDLE..."
sudo mkdir -p "$APP_BUNDLE/Contents/MacOS"
sudo mkdir -p "$APP_BUNDLE/Contents/Resources"

# Stop any running instance first
if pgrep -f "SimpleWindowSwitcher" > /dev/null; then
    echo "🛑 Stopping running SimpleWindowSwitcher..."
    sudo pkill -f "SimpleWindowSwitcher" 2>/dev/null || true
    sleep 1
fi

# Update the executable (don't delete the whole bundle)
echo "📋 Updating executable..."
sudo cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher"
sudo chmod +x "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher"

# Try to preserve the bundle's creation date and identity
if [ -f "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher" ]; then
    echo "🔧 Preserving bundle identity..."
    # Reset bundle cache
    sudo /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
fi

# Create minimal Info.plist (matching what works)
echo "📝 Creating Info.plist..."
sudo tee "$APP_BUNDLE/Contents/Info.plist" > /dev/null << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SimpleWindowSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.SimpleWindowSwitcher</string>
    <key>CFBundleName</key>
    <string>SimpleWindowSwitcher</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSBackgroundOnly</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSAccessibilityUsageDescription</key>
    <string>This app needs accessibility access to switch between windows.</string>
</dict>
</plist>
EOF

# DO NOT code sign - keep the binary exactly as built
echo "🔐 Preserving original binary signature (no modifications)"

echo ""
echo "✅ Working SimpleWindowSwitcher installed successfully!"
echo ""
echo "📍 Installation location: $APP_BUNDLE"
echo ""
echo "🎯 Usage (IMPORTANT for first install):"
echo "   1. Launch: open '$APP_BUNDLE'"
echo "   2. If prompted: Enable permissions in System Preferences"
echo "   3. QUIT the app (Cmd+Q) and relaunch from Applications"
echo "   4. Use Cmd+Tab (all windows) and Cmd+\` (current app windows)"
echo ""
echo "⚠️  Note: macOS requires manual restart after granting permissions"
echo ""
echo "💡 This uses the EXACT same binary that works in development."
echo ""

# Launch immediately to test
read -p "🚀 Launch SimpleWindowSwitcher now to test? (Y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "🔄 Launching SimpleWindowSwitcher..."
    open "$APP_BUNDLE"
    echo "✅ Launched! Test with Cmd+Tab"
fi

echo ""
echo "🎉 Installation complete!"