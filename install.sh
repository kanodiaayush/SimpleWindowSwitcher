#!/bin/bash

set -e

echo "🚀 Installing SimpleWindowSwitcher..."
echo ""

# Build the release version
echo "📦 Building release version..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Get the built executable
EXECUTABLE=".build/release/SimpleWindowSwitcher"

if [ ! -f "$EXECUTABLE" ]; then
    echo "❌ Executable not found at $EXECUTABLE"
    exit 1
fi

# Create Applications directory if it doesn't exist
INSTALL_DIR="$HOME/Applications"
if [ ! -d "$INSTALL_DIR" ]; then
    echo "📁 Creating $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
fi

# Create app bundle structure
APP_BUNDLE="$INSTALL_DIR/SimpleWindowSwitcher.app"
echo "📁 Creating app bundle at $APP_BUNDLE..."

# Remove existing app if present
if [ -d "$APP_BUNDLE" ]; then
    echo "🗑️  Removing existing installation..."
    rm -rf "$APP_BUNDLE"
fi

# Create app bundle directories
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
echo "📋 Installing executable..."
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher"
chmod +x "$APP_BUNDLE/Contents/MacOS/SimpleWindowSwitcher"

# Create Info.plist
echo "📝 Creating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SimpleWindowSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.SimpleWindowSwitcher</string>
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
</dict>
</plist>
EOF

echo ""
echo "✅ SimpleWindowSwitcher installed successfully!"
echo ""
echo "📍 Installation location: $APP_BUNDLE"
echo ""
echo "🎯 To use:"
echo "   1. Open Launchpad or Applications folder"
echo "   2. Launch 'SimpleWindowSwitcher'"
echo "   3. Grant accessibility permissions when prompted"
echo "   4. Use Cmd+Tab to switch windows with MRU ordering!"
echo ""
echo "🔧 Features:"
echo "   • Cmd+Tab: Open window switcher"
echo "   • Arrow keys: Navigate (←→ sequential, ↑↓ grid-based)"
echo "   • ESC: Cancel switching"
echo "   • Cmd+Q: Quit application"
echo "   • Most Recently Used ordering"
echo "   • Fast cached performance"
echo ""

# Ask about auto-start
echo "❓ Would you like SimpleWindowSwitcher to start automatically at login? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    echo "⚙️  Setting up auto-start..."
    
    # Add to login items using osascript
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_BUNDLE\", hidden:false}"
    
    if [ $? -eq 0 ]; then
        echo "✅ Auto-start configured! SimpleWindowSwitcher will launch at login."
    else
        echo "⚠️  Could not configure auto-start. You can manually add it to Login Items in System Preferences > Users & Groups."
    fi
else
    echo "ℹ️  You can manually add SimpleWindowSwitcher to Login Items later in System Preferences."
fi

echo ""
echo "🎉 Installation complete! Enjoy your new window switcher!"
echo ""
echo "💡 Tip: Run the app once to grant accessibility permissions, then it's ready to use!"