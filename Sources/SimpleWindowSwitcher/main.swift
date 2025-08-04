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

// External function for brute force window discovery (from alt-tab-macos)
@_silgen_name("_AXUIElementCreateWithRemoteToken")
func _AXUIElementCreateWithRemoteToken(_ data: CFData) -> Unmanaged<AXUIElement>?

func setNativeCommandTabEnabled(_ isEnabled: Bool, _ hotkeys: [CGSSymbolicHotKey] = CGSSymbolicHotKey.allCases) {
    for hotkey in hotkeys {
        CGSSetSymbolicHotKeyEnabled(hotkey.rawValue, isEnabled)
    }
}

// MARK: - Performance Cache

class PerformanceCache {
    static let shared = PerformanceCache()
    
    private var cachedRunningApps: [NSRunningApplication] = []
    private var appCacheTime: TimeInterval = 0
    private let appCacheTimeout: TimeInterval = 2.0 // Cache for 2 seconds
    
    private var excludedAppsCache: [String: Bool] = [:]
    private var iconCache: [pid_t: NSImage] = [:]
    
    private init() {}
    
    func getCachedRunningApps() -> [NSRunningApplication] {
        let now = Date().timeIntervalSince1970
        
        if now - appCacheTime > appCacheTimeout || cachedRunningApps.isEmpty {
            cachedRunningApps = NSWorkspace.shared.runningApplications.filter { app in
                app.activationPolicy == .regular && !app.isTerminated
            }
            appCacheTime = now
        }
        
        return cachedRunningApps
    }
    
    func isAppExcluded(_ appName: String) -> Bool {
        if let cached = excludedAppsCache[appName] {
            return cached
        }
        
        let excluded = shouldExcludeApp(appName)
        excludedAppsCache[appName] = excluded
        return excluded
    }
    
    func getCachedIcon(for pid: pid_t, app: NSRunningApplication) -> NSImage? {
        if let cached = iconCache[pid] {
            return cached
        }
        
        if let icon = app.icon {
            iconCache[pid] = icon
            return icon
        }
        
        return nil
    }
    
    private func shouldExcludeApp(_ appName: String) -> Bool {
        let excludedApps = [
            "Window Server", "WindowServer",
            "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter",
            "TextInputMenuAgent", "TextInputSwitcher",
            "Spotlight", "Siri", "VoiceOver",
            "AXVisualSupportAgent", "UniversalAccessAuthWarn",
            "WiFiAgent", "UserEventAgent", "CommCenter",
            "ReportCrash", "CrashReporter", "Problem Reporter",
            "loginwindow", "SecurityAgent", "ScreenSaverEngine",
            "SimpleWindowSwitcher", // Our own app
            "Steam Helper", // Steam background processes
            "CleanMyMac", "CleanMyMac X Business", // System cleaners
            "Raycast", "Alfred", // Other launchers that might interfere
        ]
        
        return excludedApps.contains { appName.contains($0) }
    }
    
    func clearCaches() {
        cachedRunningApps.removeAll()
        excludedAppsCache.removeAll()
        iconCache.removeAll()
        appCacheTime = 0
    }
}

// MARK: - Window Information

struct WindowInfo {
    let id: CGWindowID
    let title: String
    let ownerName: String
    let ownerPID: pid_t
    let bounds: CGRect
    let isActive: Bool
    let axElement: AXUIElement?  // Store AX element for proper switching
    
    // Lazy icon loading
    private var _icon: NSImage?
    private var iconLoaded = false
    
    var icon: NSImage? {
        mutating get {
            if !iconLoaded {
                _icon = PerformanceCache.shared.getCachedIcon(
                    for: ownerPID, 
                    app: NSRunningApplication(processIdentifier: ownerPID) ?? NSRunningApplication()
                )
                iconLoaded = true
            }
            return _icon ?? NSImage(named: NSImage.applicationIconName)
        }
    }
    
    var displayTitle: String {
        if title.isEmpty {
            return ownerName
        }
        return "\(ownerName) - \(title)"
    }
    
    init(id: CGWindowID, title: String, ownerName: String, ownerPID: pid_t, bounds: CGRect, isActive: Bool, axElement: AXUIElement?) {
        self.id = id
        self.title = title
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.bounds = bounds
        self.isActive = isActive
        self.axElement = axElement
    }
}

// MARK: - AX Window Manager (like alt-tab-macos)

class WindowManager {
    static func getAllWindows() -> [WindowInfo] {
        let startTime = Date()
        var windows: [WindowInfo] = []
        let activeWindowID = getCurrentActiveWindowID()
        
        // Use cached running applications
        let runningApps = PerformanceCache.shared.getCachedRunningApps()
        
        // Process apps concurrently for better performance
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInteractive)
        let syncQueue = DispatchQueue(label: "windows.sync")
        
        for app in runningApps {
            guard let appName = app.localizedName else { continue }
            
            // Skip excluded apps using cache
            if PerformanceCache.shared.isAppExcluded(appName) {
                continue
            }
            
            dispatchGroup.enter()
            queue.async {
                let appWindows = getWindowsForApp(app, activeWindowID: activeWindowID)
                
                syncQueue.async {
                    windows.append(contentsOf: appWindows)
                    dispatchGroup.leave()
                }
            }
        }
        
        dispatchGroup.wait()
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        print("⏱️ Window discovery took \(String(format: "%.3f", elapsedTime))s")
        
        // Sort windows: non-active windows first, then active window
        return windows.sorted { window1, window2 in
            if window1.isActive != window2.isActive {
                return !window1.isActive // Non-active windows first
            }
            if window1.ownerName != window2.ownerName {
                return window1.ownerName < window2.ownerName // Alphabetical by app
            }
            return window1.title < window2.title // Then by window title
        }
    }
    
    private static func getWindowsForApp(_ app: NSRunningApplication, activeWindowID: CGWindowID?) -> [WindowInfo] {
        var windows: [WindowInfo] = []
        
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        
        do {
            // Get windows using optimized AX API
            let axWindows = try getAXWindows(appRef, app.processIdentifier)
            
            for axWindow in axWindows {
                if let windowInfo = createWindowInfo(
                    from: axWindow,
                    app: app,
                    activeWindowID: activeWindowID
                ) {
                    windows.append(windowInfo)
                }
            }
        } catch {
            // Silent error handling
        }
        
        return windows
    }
    
    private static func getAXWindows(_ appRef: AXUIElement, _ pid: pid_t) throws -> [AXUIElement] {
        // First try the normal AX approach
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)
        
        var axWindows: [AXUIElement] = []
        
        if result == .success, let windows = windowsRef as? [AXUIElement] {
            axWindows.append(contentsOf: windows)
        }
        
        // Optimized brute force approach - reduced from 500 to 100 iterations
        let bruteForceWindows = getWindowsByBruteForce(pid, maxIterations: 100)
        axWindows.append(contentsOf: bruteForceWindows)
        
        // Remove duplicates
        axWindows = Array(Set(axWindows))
        
        // Filter for actual windows
        let filteredWindows = axWindows.filter { axWindow in
            var subroleRef: CFTypeRef?
            let subroleResult = AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleRef)
            
            if subroleResult == .success, let subrole = subroleRef as? String {
                return subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
            }
            
            // If no subrole, check if it has a title (likely a window)
            var titleRef: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            return titleResult == .success
        }
        
        return filteredWindows
    }
    
    private static func getWindowsByBruteForce(_ pid: pid_t, maxIterations: Int = 100) -> [AXUIElement] {
        var axWindows: [AXUIElement] = []
        
        // Create remote token for brute force (like alt-tab-macos)
        var remoteToken = Data(count: 20)
        remoteToken.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        remoteToken.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        remoteToken.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f636f)) { Data($0) })
        
        // Reduced iterations for better performance
        for axUiElementId: UInt64 in 0..<UInt64(maxIterations) {
            remoteToken.replaceSubrange(12..<20, with: withUnsafeBytes(of: axUiElementId) { Data($0) })
            
            if let axUiElement = _AXUIElementCreateWithRemoteToken(remoteToken as CFData)?.takeRetainedValue() {
                var subroleRef: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(axUiElement, kAXSubroleAttribute as CFString, &subroleRef)
                
                if result == .success,
                   let subrole = subroleRef as? String,
                   (subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole) {
                    axWindows.append(axUiElement)
                }
            }
        }
        
        return axWindows
    }
    
    private static func createWindowInfo(
        from axWindow: AXUIElement,
        app: NSRunningApplication,
        activeWindowID: CGWindowID?
    ) -> WindowInfo? {
        // Get window title
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""
        
        // Get window size and position
        var sizeRef: CFTypeRef?
        var positionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
        
        let size = sizeRef as? CGSize ?? CGSize.zero
        let position = positionRef as? CGPoint ?? CGPoint.zero
        let bounds = CGRect(origin: position, size: size)
        
        // Accept windows with meaningful titles or valid sizes
        let hasValidSize = size.width > 50 && size.height > 30
        let hasMeaningfulTitle = !title.isEmpty && title != "Window" && title != "Untitled"
        
        // Accept windows if they have either valid size OR meaningful title
        guard hasValidSize || hasMeaningfulTitle else {
            return nil
        }
        
        // Try to get CGWindowID - this is important for window switching
        var windowIDRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXIdentifierAttribute as CFString, &windowIDRef)
        let windowID = windowIDRef as? CGWindowID ?? 0
        
        let isActive = windowID == activeWindowID
        
        // If AX size is zero but we have a meaningful window, use a default size
        let finalBounds = hasValidSize ? bounds : CGRect(x: position.x, y: position.y, width: 800, height: 600)
        
        let windowInfo = WindowInfo(
            id: windowID,
            title: title,
            ownerName: app.localizedName ?? "Unknown",
            ownerPID: app.processIdentifier,
            bounds: finalBounds,
            isActive: isActive,
            axElement: axWindow  // Store AX element for proper window switching
        )
        
        return windowInfo
    }
    
    static func getCurrentActiveWindowID() -> CGWindowID? {
        // Get the currently focused window ID using CG API
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
        
        // First activate the application
        let appSuccess = app.activate(options: [.activateIgnoringOtherApps])
        
        // Then focus the specific window using AX API
        if let axElement = windowInfo.axElement {
            let focusResult = AXUIElementPerformAction(axElement, kAXRaiseAction as CFString)
            if focusResult == .success {
                // Also try to make it the main window
                AXUIElementPerformAction(axElement, kAXPressAction as CFString)
            }
            print("✓ App activation: \(appSuccess), Window focus: \(focusResult == .success)")
        } else {
            print("✓ App activation: \(appSuccess) (no AX element for window focus)")
        }
    }
}

// MARK: - Native-Style Overlay Window

class NativeStyleOverlay: NSWindow {
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var scrollOffset = 0
    private let iconsPerRow = 8
    private let maxRows = 4
    private var maxVisibleIcons: Int { return iconsPerRow * maxRows }
    private var iconViews: [NSView] = []
    private var previewViews: [NSImageView] = []
    private let iconContainer = NSView()
    private let titleLabel = NSTextField()
    private let previewContainer = NSView()
    private let scrollIndicator = NSTextField()
    
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
        
        // Will be resized dynamically
        let initialFrame = NSRect(x: 0, y: 0, width: 900, height: 450)
        setFrame(initialFrame, display: false)
        
        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 450
            let y = screenFrame.midY - 225
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        // Create main background view
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.frame = NSRect(x: 0, y: 0, width: 900, height: 450)
        backgroundView.autoresizingMask = [.width, .height]
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 12
        
        // Setup icon container for grid layout (4 rows x 8 cols of ~70px icons)
        iconContainer.frame = NSRect(x: 20, y: 150, width: 860, height: 280)
        
        // Setup title label  
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.backgroundColor = .clear
        titleLabel.textColor = .white
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 20, y: 110, width: 860, height: 25)
        
        // Setup scroll indicator
        scrollIndicator.isEditable = false
        scrollIndicator.isBordered = false
        scrollIndicator.backgroundColor = .clear
        scrollIndicator.textColor = .lightGray
        scrollIndicator.font = NSFont.systemFont(ofSize: 12)
        scrollIndicator.alignment = .center
        scrollIndicator.frame = NSRect(x: 20, y: 20, width: 860, height: 20)
        scrollIndicator.stringValue = ""
        
        // Setup preview container (smaller, positioned at bottom)
        previewContainer.frame = NSRect(x: 20, y: 50, width: 860, height: 50)
        previewContainer.wantsLayer = true
        
        backgroundView.addSubview(iconContainer)
        backgroundView.addSubview(titleLabel)
        backgroundView.addSubview(scrollIndicator)
        backgroundView.addSubview(previewContainer)
        contentView?.addSubview(backgroundView)
    }
    
    func updateWithWindows(_ windowList: [WindowInfo], selectedIndex: Int) {
        self.windows = windowList
        self.selectedIndex = selectedIndex
        
        // Update scroll offset if selection is outside visible range
        updateScrollOffset()
        
        // Clear existing views
        iconViews.forEach { $0.removeFromSuperview() }
        iconViews.removeAll()
        previewViews.forEach { $0.removeFromSuperview() }
        previewViews.removeAll()
        
        let iconSize: CGFloat = 70
        let spacing: CGFloat = 15
        
        // Calculate required space for grid
        let totalWidth = CGFloat(iconsPerRow) * iconSize + CGFloat(max(0, iconsPerRow - 1)) * spacing
        
        // Calculate dynamic window size based on actual content
        let visibleWindowCount = min(windows.count, maxVisibleIcons)
        let actualRows = min(maxRows, (visibleWindowCount + iconsPerRow - 1) / iconsPerRow)
        
        let windowWidth: CGFloat = max(900, totalWidth + 80)  // minimum width
        let windowHeight: CGFloat = max(350, CGFloat(actualRows) * (iconSize + spacing) + 200) // dynamic height
        
        // Update window size and position
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect.zero
        let newFrame = NSRect(
            x: screenFrame.midX - windowWidth / 2,
            y: screenFrame.midY - windowHeight / 2,
            width: windowWidth,
            height: windowHeight
        )
        setFrame(newFrame, display: true)
        
        // Update background view and containers
        if let backgroundView = contentView?.subviews.first {
            backgroundView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)
            let gridHeight = CGFloat(actualRows) * (iconSize + spacing)
            iconContainer.frame = NSRect(x: 20, y: windowHeight - gridHeight - 60, width: windowWidth - 40, height: gridHeight)
            titleLabel.frame = NSRect(x: 20, y: windowHeight - gridHeight - 100, width: windowWidth - 40, height: 25)
            previewContainer.frame = NSRect(x: 20, y: 50, width: windowWidth - 40, height: 50)
            scrollIndicator.frame = NSRect(x: 20, y: 20, width: windowWidth - 40, height: 20)
        }
        
        // Calculate start position for centering grid
        let startX = (iconContainer.bounds.width - totalWidth) / 2
        let startY = iconContainer.bounds.height - iconSize // Start from top
        
        // Draw visible windows in grid
        let startIndex = scrollOffset
        let endIndex = min(startIndex + maxVisibleIcons, windows.count)
        
        for i in startIndex..<endIndex {
            let displayIndex = i - startIndex
            let window = windows[i]
            
            // Calculate grid position
            let row = displayIndex / iconsPerRow
            let col = displayIndex % iconsPerRow
            
            // Create icon container
            let container = NSView()
            container.frame = NSRect(
                x: startX + CGFloat(col) * (iconSize + spacing),
                y: startY - CGFloat(row) * (iconSize + spacing),
                width: iconSize,
                height: iconSize
            )
            container.wantsLayer = true
            container.layer?.cornerRadius = 8
            
            // Create icon image view
            let imageView = NSImageView()
            imageView.frame = NSRect(x: 5, y: 5, width: iconSize - 10, height: iconSize - 10)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            
            // Use mutable copy to access lazy-loaded icon
            var mutableWindow = window
            imageView.image = mutableWindow.icon
            
            container.addSubview(imageView)
            iconContainer.addSubview(container)
            iconViews.append(container)
            
            // Apply selection styling
            if i == selectedIndex {
                container.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.3).cgColor
                container.layer?.borderWidth = 3
                container.layer?.borderColor = NSColor.controlAccentColor.cgColor
                container.layer?.shadowColor = NSColor.controlAccentColor.cgColor
                container.layer?.shadowOffset = CGSize.zero
                container.layer?.shadowRadius = 10
                container.layer?.shadowOpacity = 0.5
                
                // Add window preview for selected item
                addWindowPreview(for: window)
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
        
        // Update scroll indicator
        updateScrollIndicator()
    }
    
    private func updateScrollOffset() {
        // Ensure selected index is visible
        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + maxVisibleIcons {
            scrollOffset = selectedIndex - maxVisibleIcons + 1
        }
        
        // Clamp scroll offset
        scrollOffset = max(0, min(scrollOffset, max(0, windows.count - maxVisibleIcons)))
    }
    
    private func updateScrollIndicator() {
        if windows.count <= maxVisibleIcons {
            scrollIndicator.stringValue = ""
        } else {
            let currentPage = (scrollOffset / maxVisibleIcons) + 1
            let totalPages = (windows.count + maxVisibleIcons - 1) / maxVisibleIcons
            scrollIndicator.stringValue = "Page \(currentPage) of \(totalPages) • Use ← → to scroll"
        }
    }
    
    private func addWindowPreview(for window: WindowInfo) {
        // Create window preview
        let previewView = NSImageView()
        let previewWidth: CGFloat = 200
        let previewHeight: CGFloat = 40
        
        // Center preview in preview container
        previewView.frame = NSRect(
            x: (previewContainer.bounds.width - previewWidth) / 2,
            y: (previewContainer.bounds.height - previewHeight) / 2,
            width: previewWidth,
            height: previewHeight
        )
        
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 6
        previewView.layer?.borderWidth = 2
        previewView.layer?.borderColor = NSColor.controlAccentColor.cgColor
        previewView.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        
        // Try to get window content
        if let cgImage = getCGImageForWindow(window) {
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            previewView.image = nsImage
            previewView.imageScaling = .scaleProportionallyDown
        } else {
            // Fallback: show app icon in preview
            var mutableWindow = window
            previewView.image = mutableWindow.icon
            previewView.imageScaling = .scaleProportionallyDown
        }
        
        previewContainer.addSubview(previewView)
        previewViews.append(previewView)
    }
    
    private func getCGImageForWindow(_ window: WindowInfo) -> CGImage? {
        let windowID = window.id
        
        let imageRef = CGWindowListCreateImage(
            CGRect.null,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        )
        
        return imageRef
    }
    
    func show() {
        makeKeyAndOrderFront(nil)
    }
    
    func hide() {
        orderOut(nil)
    }
    
    var visibleIconsCount: Int {
        return iconsPerRow * maxRows
    }
    
    var iconsPerRowCount: Int {
        return iconsPerRow
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
        
        // Warm up performance cache in background
        DispatchQueue.global(qos: .background).async {
            _ = PerformanceCache.shared.getCachedRunningApps()
            print("📦 Performance cache warmed up")
        }
        
        // Disable native Cmd+Tab
        setNativeCommandTabEnabled(false)
        print("🚫 Native Cmd+Tab disabled")
        
        // Simple global key monitoring
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            self?.handleGlobalEvent(event)
        }
        
        print("⌨️  Press Cmd+Tab to activate AX-based window switcher")
        print("🔍 Using Accessibility API for comprehensive window detection")
    }
    
    private func handleGlobalEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            
            if isShowingSwitcher {
                // Handle navigation when switcher is open
                switch keyCode {
                case 48: // Tab key with Cmd
                    if modifiers.contains(.command) {
                        if modifiers.contains(.shift) {
                            selectPrevious()
                        } else {
                            selectNext()
                        }
                    }
                case 123: // Left arrow
                    selectPrevious()
                case 124: // Right arrow
                    selectNext()
                case 125: // Down arrow - move down one row
                    selectDown()
                case 126: // Up arrow - move up one row
                    selectUp()
                case 53: // Escape key - cancel and close switcher
                    cancelSwitcher()
                default:
                    break
                }
            } else {
                // Check for Cmd+Tab to start switcher
                if keyCode == 48 && modifiers.contains(.command) { // Tab key with Cmd
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
        print("🔍 Starting optimized window switcher")
        
        let startTime = Date()
        windows = WindowManager.getAllWindows()
        let elapsedTime = Date().timeIntervalSince(startTime)
        
        selectedIndex = 0
        isShowingSwitcher = true
        cmdPressed = true
        
        if windows.isEmpty {
            print("❌ No windows found")
            isShowingSwitcher = false
            return
        }
        
        print("📊 Found \(windows.count) windows in \(String(format: "%.3f", elapsedTime))s")
        updateDisplay()
        overlayWindow?.show()
    }
    
    private func selectNext() {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % windows.count
        updateDisplay()
    }
    
    private func selectPrevious() {
        guard !windows.isEmpty else { return }
        selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : windows.count - 1
        updateDisplay()
    }
    
    private func selectUp() {
        guard !windows.isEmpty else { return }
        guard let overlay = overlayWindow else { return }
        
        let iconsPerRow = overlay.iconsPerRowCount
        let currentRow = selectedIndex / iconsPerRow
        let currentCol = selectedIndex % iconsPerRow
        
        if currentRow > 0 {
            // Move up one row in the same column
            let newIndex = selectedIndex - iconsPerRow
            selectedIndex = max(0, newIndex)
        } else {
            // If in top row, wrap to bottom row in same column
            let totalRows = (windows.count + iconsPerRow - 1) / iconsPerRow
            let lastRowIndex = (totalRows - 1) * iconsPerRow + currentCol
            selectedIndex = min(lastRowIndex, windows.count - 1)
        }
        updateDisplay()
    }
    
    private func selectDown() {
        guard !windows.isEmpty else { return }
        guard let overlay = overlayWindow else { return }
        
        let iconsPerRow = overlay.iconsPerRowCount
        let currentRow = selectedIndex / iconsPerRow
        let currentCol = selectedIndex % iconsPerRow
        let totalRows = (windows.count + iconsPerRow - 1) / iconsPerRow
        
        if currentRow < totalRows - 1 {
            // Move down one row in the same column
            let newIndex = selectedIndex + iconsPerRow
            selectedIndex = min(newIndex, windows.count - 1)
        } else {
            // If in bottom row, wrap to top row in same column
            selectedIndex = currentCol
        }
        updateDisplay()
    }
    
    // Keep the old scroll functions for potential future use (page navigation)
    private func scrollUp() {
        guard !windows.isEmpty else { return }
        // Jump up by visible page size
        let maxVisibleIcons = overlayWindow?.visibleIconsCount ?? 10
        selectedIndex = max(0, selectedIndex - maxVisibleIcons)
        updateDisplay()
    }
    
    private func scrollDown() {
        guard !windows.isEmpty else { return }
        // Jump down by visible page size
        let maxVisibleIcons = overlayWindow?.visibleIconsCount ?? 10
        selectedIndex = min(windows.count - 1, selectedIndex + maxVisibleIcons)
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
    
    private func cancelSwitcher() {
        print("❌ Window switching cancelled")
        print(String(repeating: "=", count: 50) + "\n")
        
        overlayWindow?.hide()
        isShowingSwitcher = false
        cmdPressed = false
        windows.removeAll()
        selectedIndex = 0
        
        // Don't activate any window - just cancel the operation
    }
    
    private func hideSwitcher() {
        print("🔚 Session complete")
        print(String(repeating: "=", count: 50) + "\n")
        
        overlayWindow?.hide()
        isShowingSwitcher = false
        cmdPressed = false
        windows.removeAll()
        selectedIndex = 0
        
        // Optionally clear caches after extended use to free memory
        // PerformanceCache.shared.clearCaches()
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