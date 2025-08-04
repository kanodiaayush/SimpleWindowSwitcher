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

# Remove any existing installation
if [ -d "$APP_BUNDLE" ]; then
    echo "🗑️  Removing existing installation..."
    sudo rm -rf "$APP_BUNDLE"
fi

# Create app bundle
echo "📁 Creating app bundle at $APP_BUNDLE..."
sudo mkdir -p "$APP_BUNDLE/Contents/MacOS"
sudo mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the EXACT working executable
echo "📋 Installing the working executable..."
sudo cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher"
sudo chmod +x "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher"

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
    <string>com.akanodia.SimpleWindowSwitcher.working</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>SimpleWindowSwitcher</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>SimpleWindowSwitcher needs accessibility access to enumerate and switch between windows from all applications.</string>
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
echo "🎯 To test:"
echo "   1. Launch: open '$APP_BUNDLE'"
echo "   2. Grant accessibility permissions if prompted"
echo "   3. Test with Cmd+Tab - should work exactly like ./run.sh!"
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