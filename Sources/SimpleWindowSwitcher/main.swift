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
        
        for windowDict in windowList {
            guard let windowID = windowDict[kCGWindowNumber] as? CGWindowID,
                  let ownerPID = windowDict[kCGWindowOwnerPID] as? pid_t,
                  let ownerName = windowDict[kCGWindowOwnerName] as? String,
                  let boundsDict = windowDict[kCGWindowBounds] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            let title = windowDict[kCGWindowName] as? String ?? ""
            
            // More permissive window filtering - include more windows
            if bounds.width > 20 && bounds.height > 20 && 
               !ownerName.contains("Window Server") && 
               ownerName != "Dock" &&
               ownerName != "SystemUIServer" &&
               ownerName != "ControlCenter" &&
               ownerName != "NotificationCenter" {
                
                let windowInfo = WindowInfo(
                    id: windowID,
                    title: title,
                    ownerName: ownerName,
                    ownerPID: ownerPID,
                    bounds: bounds
                )
                windows.append(windowInfo)
            }
        }
        
        return windows
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

// MARK: - Minimal Console-Based Switcher

class SimpleWindowSwitcher: NSObject, NSApplicationDelegate {
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var isShowingSwitcher = false
    private var cmdPressed = false
    
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
        
        // Disable native Cmd+Tab
        setNativeCommandTabEnabled(false)
        print("🚫 Native Cmd+Tab disabled")
        
        // Simple global key monitoring
        NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleGlobalEvent(event)
        }
        
        print("⌨️  Press Cmd+Tab to activate window switcher")
        print("📝 Console-based interface: Tab cycles, Cmd release activates")
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
        print("🪟 Starting window switcher session")
        
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
        displayCurrent()
    }
    
    private func selectNext() {
        selectedIndex = (selectedIndex + 1) % windows.count
        displayCurrent()
    }
    
    private func displayCurrent() {
        guard selectedIndex < windows.count else { return }
        let selectedWindow = windows[selectedIndex]
        let displayText = "(\(selectedIndex + 1)/\(windows.count)) \(selectedWindow.displayTitle)"
        print("👉 \(displayText)")
    }
    
    private func activateSelectedWindow() {
        guard selectedIndex < windows.count else { return }
        let selectedWindow = windows[selectedIndex]
        WindowManager.activateWindow(selectedWindow)
    }
    
    private func hideSwitcher() {
        print("🔚 Session complete")
        print(String(repeating: "=", count: 50) + "\n")
        isShowingSwitcher = false
        cmdPressed = false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
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