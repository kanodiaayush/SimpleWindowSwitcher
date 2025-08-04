#!/bin/bash

echo "🔧 SimpleWindowSwitcher Permission Setup Helper"
echo ""

APP_PATH="/Applications/SimpleWindowSwitcher.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ SimpleWindowSwitcher not found at $APP_PATH"
    echo "   Please run ./install.sh first"
    exit 1
fi

echo "📋 This script helps with persistent accessibility permissions."
echo ""
echo "🎯 Follow these steps:"
echo "   1. Open System Preferences > Security & Privacy > Privacy > Accessibility"
echo "   2. Click the lock icon and enter your password"
echo "   3. Remove any existing 'SimpleWindowSwitcher' entries"
echo "   4. Click the '+' button"
echo "   5. Navigate to and select: $APP_PATH"
echo "   6. Ensure it's checked/enabled"
echo ""
echo "💡 Pro Tips:"
echo "   • Use the SAME app bundle each time (don't rebuild unnecessarily)"
echo "   • If permissions reset, the app may have been rebuilt with different signature"
echo "   • The app now has code signing to help maintain identity"
echo ""

# Check if accessibility is already granted
echo "🔍 Checking current accessibility permissions..."

# Try to get current accessibility status
if /usr/bin/sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT service,client,allowed,prompt_count FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%SimpleWindowSwitcher%';" 2>/dev/null | grep -q "SimpleWindowSwitcher"; then
    echo "✅ Found SimpleWindowSwitcher in accessibility database"
    
    # Check if it's enabled
    if /usr/bin/sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "SELECT allowed FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%SimpleWindowSwitcher%';" 2>/dev/null | grep -q "1"; then
        echo "✅ Accessibility permissions appear to be granted!"
    else
        echo "⚠️  Accessibility permissions found but may be disabled"
    fi
else
    echo "❌ SimpleWindowSwitcher not found in accessibility database"
    echo "   Please add it manually using the steps above"
fi

echo ""
echo "🚀 To open System Preferences > Accessibility:"
read -p "Press Enter to open Accessibility preferences, or Ctrl+C to exit..."

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "✅ Done! Make sure SimpleWindowSwitcher is enabled in the accessibility list."