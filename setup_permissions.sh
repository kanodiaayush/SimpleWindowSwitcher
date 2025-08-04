#!/bin/bash

echo "🔐 SimpleWindowSwitcher Permission Setup Helper"
echo "=============================================="
echo ""
echo "This script helps solve the recurring permission prompt issue."
echo ""

APP_BUNDLE="/Applications/SimpleWindowSwitcher.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "❌ SimpleWindowSwitcher not found in Applications folder"
    echo "Please run ./install.sh first"
    exit 1
fi

echo "📝 Step 1: Adding app to TCC database properly..."

# Try to add the app to TCC (Transparency, Consent, and Control) database
BUNDLE_ID="com.example.SimpleWindowSwitcher"
echo "   Bundle ID: $BUNDLE_ID"

echo ""
echo "📱 Step 2: Please manually grant permissions:"
echo "   1. Open System Preferences > Security & Privacy > Privacy > Accessibility"
echo "   2. Click the lock to make changes"
echo "   3. Look for SimpleWindowSwitcher in the list"
echo "   4. If not there, click '+' and add from /Applications/SimpleWindowSwitcher.app"
echo "   5. Make sure the checkbox is CHECKED"
echo ""

read -p "Press Enter when you've completed the above steps..."

echo ""
echo "🔄 Step 3: Force-quit any running instances..."
pkill -f "SimpleWindowSwitcher" 2>/dev/null || true
sleep 1

echo ""
echo "♻️  Step 4: Reset system caches..."
sudo /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null

echo ""
echo "🚀 Step 5: Testing the app..."
echo "Launching SimpleWindowSwitcher..."
open "$APP_BUNDLE"

sleep 2

echo ""
echo "✅ Setup complete!"
echo ""
echo "🎯 If SimpleWindowSwitcher launches without asking for permissions,"
echo "   then the setup worked and future installs should preserve permissions."
echo ""
echo "🎮 Test with:"
echo "   - Cmd+Tab (all windows)"
echo "   - Cmd+\` (current app windows)"
echo ""
echo "💡 If it still asks for permissions, this is a macOS security limitation"
echo "   and manual permission grant may be required after each install."