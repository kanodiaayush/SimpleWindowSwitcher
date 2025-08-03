import AppKit
import Carbon
import CoreGraphics
import ApplicationServices

// MARK: - Private SkyLight APIs for disabling native Cmd+Tab

enum CGSSymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
    case commandKeyAboveTab = 6
}

@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
func CGSSetSymbolicHotKeyEnabled(_ hotKey: CGSSymbolicHotKey.RawValue, _ isEnabled: Bool) -> Int32

func setNativeCommandTabEnabled(_ isEnabled: Bool, _ hotkeys: [CGSSymbolicHotKey] = CGSSymbolicHotKey.allCases) {
    for hotkey in hotkeys {
        CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, isEnabled)
    }
}

// MARK: - Window Information

struct WindowInfo {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let ownerPID: pid_t
    let bounds: CGRect
    let icon: NSImage?
    let isActive: Bool
    
    var displayTitle: String {
        if title.isEmpty {
            return ownerName
        }
        return "\(ownerName) - \(title)"
    }
}

// MARK: - Window Manager

class WindowManager {
    static func getAllWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] else {
            return []
        }
        
        var windows: [WindowInfo] = []
        // Get currently active window ID for sorting
        let activeWindowID = getCurrentActiveWindowID()
        
        for windowDict in windowList {
            guard let windowID = windowDict[kCGWindowNumber] as? CGWindowID,
                  let ownerPID = windowDict[kCGWindowOwnerPID] as? pid_t,
                  let ownerName = windowDict[kCGWindowOwnerName] as? String,
                  let boundsDict = windowDict[kCGWindowBounds] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            let title = windowDict[kCGWindowName] as? String ?? ""
            
            // More permissive window filtering
            if bounds.width > 20 && bounds.height > 20 && 
               !ownerName.contains("Window Server") && 
               ownerName != "Dock" &&
               ownerName != "SystemUIServer" &&
               ownerName != "ControlCenter" &&
               ownerName != "NotificationCenter" &&
               ownerName != "SimpleWindowSwitcher" {
                
                // Get app icon
                let app = NSRunningApplication(processIdentifier: ownerPID)
                let icon = app?.icon
                
                // Check if this is the active window
                let isActive = windowID == activeWindowID
                
                let windowInfo = WindowInfo(
                    id: windowID,
                    title: title,
                    ownerName: ownerName,
                    ownerPID: ownerPID,
                    bounds: bounds,
                    icon: icon,
                    isActive: isActive
                )
                windows.append(windowInfo)
            }
        }
        
        // Sort windows: non-active windows first, then active window
        // This way the active window doesn't appear first in the switcher
        return windows.sorted { window1, window2 in
            if window1.isActive != window2.isActive {
                return !window1.isActive // Non-active windows first
            }
            return window1.ownerName < window2.ownerName // Alphabetical for same active state
        }
    }
    
    static func getCurrentActiveWindowID() -> CGWindowID? {
        // Get the currently focused window ID
        if let windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as? [[CFString: Any]] {
            for windowDict in windowList {
                if let windowID = windowDict[kCGWindowNumber] as? CGWindowID,
                   let layer = windowDict[kCGWindowLayer] as? Int,
                   layer == 0 { // Front window typically has layer 0
                    return windowID
                }
            }
        }
        return nil
    }
    
    static func activateWindow(_ windowInfo: WindowInfo) {
        print("→ Activating: \(windowInfo.displayTitle)")
        
        guard let app = NSRunningApplication(processIdentifier: windowInfo.ownerPID) else {
            print("✗ Could not find application with PID: \(windowInfo.ownerPID)")
            return
        }
        
        guard !app.isTerminated else {
            print("✗ Application is terminated: \(windowInfo.displayTitle)")
            return
        }
        
        let success = app.activate(options: [.activateIgnoringOtherApps])
        print("✓ Activation result: \(success)")
    }
}

// MARK: - Native-Style Overlay Window

class NativeStyleOverlay: NSWindow {
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var iconViews: [NSView] = []
    private let iconContainer = NSView()
    private let titleLabel = NSTextField()
    
    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 600, height: 150), 
                   styleMask: [.borderless], 
                   backing: .buffered, 
                   defer: false)
        
        setupWindow()
    }
    
    private func setupWindow() {
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        
        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 300
            let y = screenFrame.midY - 75
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Create main background view
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.frame = NSRect(x: 0, y: 0, width: 600, height: 150)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12
        
        // Setup icon container
        iconContainer.frame = NSRect(x: 20, y: 50, width: 560, height: 80)
        
        // Setup title label
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 20, width: 560, height: 25)
        
        backgroundView.addSubview(iconContainer)
        backgroundView.addSubview(titleLabel)
        contentView?.addSubview(backgroundView)
    }
    
    func updateWithWindows(_ windowList: [WindowInfo], selectedIndex: Int) {
        self.windows = windowList
        self.selectedIndex = selectedIndex
        
        // Clear existing icons
        iconViews.forEach { $0.removeFromSuperview() }
        iconViews.removeAll()
        
        let maxIcons = min(windows.count, 8) // Limit for visual clarity
        let iconSize: CGFloat = 70
        let spacing: CGFloat = 15
        let totalWidth = CGFloat(maxIcons) * iconSize + CGFloat(max(0, maxIcons - 1)) * spacing
        let startX = (iconContainer.bounds.width - totalWidth) / 2
        
        for i in 0..<maxIcons {
            let window = windows[i]
            
            // Create icon container
            let container = NSView()
            container.frame = NSRect(
                x: startX + CGFloat(i) * (iconSize + spacing),
                y: 5,
                width: iconSize,
                height: iconSize
            )
            container.wantsLayer = true
            container.layer?.cornerRadius = 8
            
            // Create icon image view
            let imageView = NSImageView()
            imageView.frame = NSRect(x: 5, y: 5, width: iconSize - 10, height: iconSize - 10)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            
            if let icon = window.icon {
                imageView.image = icon
            } else {
                // Create default app icon
                imageView.image = NSImage(named: NSImage.applicationIconName)
            }
            
            container.addSubview(imageView)
            iconContainer.addSubview(container)
            iconViews.append(container)
            
            // Apply selection styling
            if i == selectedIndex {
                container.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                container.layer?.borderWidth = 3
                container.layer?.borderColor = NSColor.controlAccentColor.cgColor
                
                // Add subtle glow effect
                container.layer?.shadowColor = NSColor.controlAccentColor.cgColor
                container.layer?.shadowOffset = CGSize.zero
                container.layer?.shadowRadius = 10
                container.layer?.shadowOpacity = 0.5
            } else {
                container.layer?.backgroundColor = NSColor.clear.cgColor
                container.layer?.borderWidth = 0
                container.layer?.shadowOpacity = 0
            }
        }
        
        // Update title
        if selectedIndex < windows.count {
            let selectedWindow = windows[selectedIndex]
            titleLabel.stringValue = selectedWindow.displayTitle
        }
        
        // Adjust window width based on content
        let newWidth = max(400, totalWidth + 40)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let newFrame = NSRect(
            x: screenFrame.midX - newWidth / 2,
            y: screenFrame.midY - 75,
            width: newWidth,
            height: 150
        )
        setFrame(newFrame, display: true)
        
        // Update background view size
        if let backgroundView = contentView?.subviews.first {
            backgroundView.frame = NSRect(x: 0, y: 0, width: newWidth, height: 150)
        }
        
        // Update container positions
        iconContainer.frame = NSRect(x: 20, y: 50, width: newWidth - 40, height: 80)
        titleLabel.frame = NSRect(x: 20, y: 20, width: newWidth - 40, height: 25)
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
    }
    
    func hide() {
        orderOut(nil)
    }
}

// MARK: - Enhanced Window Switcher

class SimpleWindowSwitcher: NSObject, NSApplicationDelegate {
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isShowingSwitcher = false
    private var cmdPressed = false
    private var overlayWindow: NativeStyleOverlay?
    private var globalMonitor: Any?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 SimpleWindowSwitcher started")
        
        // Check for accessibility permissions
        if !AXIsProcessTrusted() {
            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "This app needs accessibility permissions to switch windows. Please grant permission in System Preferences > Security & Privacy > Privacy > Accessibility."
            alert.runModal()
            
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
        
        // Create overlay window once at startup
        overlayWindow = NativeStyleOverlay(
            contentRect: NSRect.zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        // Disable native Cmd+Tab
        setNativeCommandTabEnabled(false)
        print("🚫 Native Cmd+Tab disabled")
        
        // Simple global key monitoring
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleGlobalEvent(event)
        }
        
        print("⌨️  Press Cmd+Tab to activate native-style window switcher")
        print("✨ Native macOS interface with app icons")
    }
    
    private func handleGlobalEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            
            // Check for Cmd+Tab
            if keyCode == 48 && modifiers.contains(.command) { // Tab key with Cmd
                if isShowingSwitcher {
                    selectNext()
                } else {
                    showWindowSwitcher()
                }
            }
        } else if event.type == .flagsChanged {
            let wasCmdPressed = cmdPressed
            cmdPressed = event.modifierFlags.contains(.command)
            
            // Cmd key was released
            if wasCmdPressed && !cmdPressed && isShowingSwitcher {
                activateSelectedWindow()
                hideSwitcher()
            }
        }
    }
    
    private func showWindowSwitcher() {
        print("\n" + String(repeating: "=", count: 50))
        print("✨ Starting native-style window switcher")
        
        windows = WindowManager.getAllWindows()
        selectedIndex = 0
        isShowingSwitcher = true
        cmdPressed = true
        
        if windows.isEmpty {
            print("❌ No windows found")
            isShowingSwitcher = false
            return
        }
        
        print("📊 Found \(windows.count) windows")
        updateDisplay()
        overlayWindow?.show()
    }
    
    private func selectNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
        updateDisplay()
    }
    
    private func updateDisplay() {
        guard selectedIndex < windows.count else { return }
        
        let selectedWindow = windows[selectedIndex]
        overlayWindow?.updateWithWindows(windows, selectedIndex: selectedIndex)
        print("👉 (\(selectedIndex + 1)/\(windows.count)) \(selectedWindow.displayTitle)")
    }
    
    private func activateSelectedWindow() {
        guard selectedIndex < windows.count else { return }
        let selectedWindow = windows[selectedIndex]
        WindowManager.activateWindow(selectedWindow)
    }
    
    private func hideSwitcher() {
        print("🔚 Session complete")
        print(String(repeating: "=", count: 50) + "\n")
        
        overlayWindow?.hide()
        isShowingSwitcher = false
        cmdPressed = false
        windows.removeAll()
        selectedIndex = 0
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up global monitor
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        // Hide overlay window
        overlayWindow?.hide()
        overlayWindow = nil
        
        setNativeCommandTabEnabled(true)
        print("✅ Native Cmd+Tab re-enabled")
    }
}

// MARK: - Signal Handlers

func emergencyExit(_ message: String) {
    setNativeCommandTabEnabled(true)
    print("🚨 Emergency exit: \(message)")
    exit(0)
}

Darwin.signal(SIGTERM) { _ in emergencyExit("SIGTERM received") }
Darwin.signal(SIGINT) { _ in emergencyExit("SIGINT received") }

// MARK: - Main

let app = NSApplication.shared
let delegate = SimpleWindowSwitcher()
app.delegate = delegate

app.setActivationPolicy(.accessory)
app.run() 