# SimpleWindowSwitcher

An advanced window switcher for macOS that provides both global and app-specific window navigation with visual overlays.

## Features

- **🖥️ Global Window Switching (Cmd+Tab)**: Visual overlay showing ALL windows from all apps
- **🔄 App-Specific Switching (Cmd+`)**: Visual overlay showing only current app's windows
- **🎯 Alt+Tab Behavior**: Immediately highlights last used window (no extra Tab needed)
- **⚡ MRU Ordering**: Most Recently Used windows appear first for intelligent switching
- **🎨 Visual Interface**: Beautiful native-style overlays with app icons and previews
- **⌨️ Full Navigation**: Arrow keys, Tab/Shift+Tab, Escape to cancel
- **🪶 Lightweight**: ~1150 lines of Swift, no external dependencies, 153KB executable
- **🚀 Fast**: Optimized window discovery with caching and concurrent processing
- **🔒 Smart Permissions**: Automatic permission detection with persistent setup (grant once, works forever)

## Installation & Usage

### Quick Start (Recommended)

```bash
git clone <this-repo>
cd SimpleWindowSwitcher
./run.sh
```

### Setting Up Accessibility Permissions

1. When you first run `./run.sh`, it will build and start the app
2. **Grant accessibility permissions** when prompted:
   - Open **System Preferences > Privacy & Security > Accessibility**
   - Click the **"+" button** 
   - Navigate to your SimpleWindowSwitcher project folder
   - Select **`.build/release/SimpleWindowSwitcher`** (the built binary)
   - **OR** copy this full path: `/path/to/your/SimpleWindowSwitcher/.build/release/SimpleWindowSwitcher`
   - **Enable the checkbox** next to SimpleWindowSwitcher
3. Return to the terminal - the app should now work immediately!

### Managing the App

- **To stop**: Press `Ctrl+C` in the terminal or close the terminal session
- **To restart**: Run `./run.sh` again
- **To force quit**: `pkill -f SimpleWindowSwitcher`
- **Permissions**: Only need to grant once - they persist for the build location

> 💡 **Why use ./run.sh instead of installing?** The development binary maintains accessibility permissions more reliably and provides debug output for troubleshooting.

## Usage

### Global Window Switching (Cmd+Tab)
- Shows **ALL windows** from all applications
- **Immediately highlights** the last used window
- Navigate with **arrow keys** or **Tab/Shift+Tab**
- **Release Cmd** to activate selected window

### App-Specific Switching (Cmd+`)
- Shows **only windows** from the current application  
- Same visual interface as Cmd+Tab
- Perfect for cycling through multiple browser tabs, Finder windows, etc.
- Navigate with **arrow keys** or **repeated Cmd+`**

### Navigation Controls
- **Arrow Keys**: Navigate in any direction
- **Tab/Shift+Tab**: Forward/backward navigation
- **Escape**: Cancel without switching
- **Cmd+Shift+Tab**: Reverse global navigation
- **Cmd+Shift+`**: Reverse app navigation

## Requirements

- **macOS 10.15+**
- **Accessibility permissions** (automatically guided setup - no technical knowledge needed)
- **Xcode Command Line Tools** (for building from source)

## Architecture

- **Window Discovery**: Accessibility APIs + brute force enumeration for comprehensive coverage
- **Performance**: Cached running apps, lazy icon loading, concurrent window processing  
- **UI**: Native NSWindow overlays with visual effects and animations
- **Hotkeys**: Global event monitoring with proper key capture and native Cmd+Tab override
- **Memory**: Efficient MRU tracking with automatic cleanup

## Development

```bash
# Development mode (run without installing)
./run.sh

# Build only
swift build -c release
```

## Size Comparison

- **SimpleWindowSwitcher**: 153KB executable
- **alt-tab-macos**: 495MB+ with dependencies

**Over 3,200x smaller** while providing advanced features! 