// Status bar menu and controls.

import Cocoa

import Combine

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let whitelistManager = WhitelistManager()
    private var runningApps: [NSRunningApplication] = []
    
    // Mandatory system apps that should not appear in the menu
    private let mandatoryWhitelist: Set<String> = [
        "com.apple.finder",
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow"
    ]
    
    // Dependencies
    private let appTimeoutManager: AppTimeoutManager
    private let undoCloseManager: UndoCloseManager
    private var cancellables = Set<AnyCancellable>()
    var showPreferences: (() -> Void)?
    
    init(appTimeoutManager: AppTimeoutManager, undoCloseManager: UndoCloseManager) {
        self.appTimeoutManager = appTimeoutManager
        self.undoCloseManager = undoCloseManager
        super.init()
        setupStatusBar()
        setupBindings()
        setupAppObservers()
    }
    
    private func setupBindings() {
        // Observe changes from managers (e.g. when changed in Preferences)
        appTimeoutManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Menu updates on reopen via delegate
            }
            .store(in: &cancellables)
            
        undoCloseManager.$isEnabled
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Menu updates on reopen via delegate
            }
            .store(in: &cancellables)
            
        // Observe whitelist changes (we need to make WhitelistManager observable or use notification)
        // For now, we'll rely on menu reopening or manual refresh
    }
    
    private func setupAppObservers() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(refreshApps), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(refreshApps), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        refreshApps()
    }
    
    @objc private func refreshApps() {
        runningApps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        updateMenu()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 28.0)
        
        if let button = statusItem?.button {
            button.title = "🧹"
            button.imagePosition = .imageLeft
            
            if let image = NSImage(systemSymbolName: "app.badge.checkmark", accessibilityDescription: "AppTidy") {
                image.isTemplate = true
                button.image = image
                button.title = ""
            }
        }
        
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }
    
    struct AppDisplayItem {
        let bundleID: String
        let name: String
        let icon: NSImage?
        let isRunning: Bool
        let isWhitelisted: Bool
        let isPlaying: Bool
    }
    
    private func updateMenu() {
        let menu = NSMenu()
        menu.delegate = self // Set delegate to refresh on open
        
        // Header
        let headerItem = NSMenuItem(title: "Keep Alive", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        // Combine running apps and whitelisted apps
        var allAppItems: [AppDisplayItem] = []
        
        // 1. Add running apps
        let protectAudio = UserDefaults.standard.bool(forKey: Constants.UserDefaults.protectAudioApps)
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            // Skip mandatory whitelisted apps (Dock, Finder, etc.)
            if mandatoryWhitelist.contains(bundleID) { continue }
            
            let item = AppDisplayItem(
                bundleID: bundleID,
                name: app.localizedName ?? "Unknown",
                icon: app.icon,
                isRunning: true,
                isWhitelisted: whitelistManager.isWhitelisted(bundleID),
                isPlaying: false
            )
            allAppItems.append(item)
        }
        
        // 2. Add non-running whitelisted apps
        let whitelisted = whitelistManager.whitelistedBundleIDs
        for bundleID in whitelisted {
            // Skip mandatory whitelisted apps (Dock, Finder, etc.)
            if mandatoryWhitelist.contains(bundleID) { continue }
            
            // Skip if already added (i.e., is running)
            if allAppItems.contains(where: { $0.bundleID == bundleID }) { continue }
            
            // Resolve info
            var name = bundleID
            var icon: NSImage?
            
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                // Get name using FileManager which is reliable for display names
                name = FileManager.default.displayName(atPath: url.path)
                
                // Get icon
                icon = NSWorkspace.shared.icon(forFile: url.path)
            }
            
            let item = AppDisplayItem(
                bundleID: bundleID,
                name: name,
                icon: icon,
                isRunning: false,
                isWhitelisted: true,
                isPlaying: false
            )
            allAppItems.append(item)
        }
        
        // Sort by name
        allAppItems.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        if allAppItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No apps found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for item in allAppItems {
                let menuItem = NSMenuItem(
                    title: item.name, // Fallback title
                    action: nil, // No action - handled in custom view
                    keyEquivalent: ""
                )
                menuItem.target = nil
                menuItem.representedObject = item.bundleID
                
                // Use custom view
                let view = AppMenuItemView(
                    item: item,
                    whitelistManager: whitelistManager
                )
                menuItem.view = view
                
                menu.addItem(menuItem)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Preferences
        let preferencesItem = NSMenuItem(
            title: "Preferences...",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        preferencesItem.target = self
        menu.addItem(preferencesItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(
            title: "Quit AppTidy",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    @objc private func toggleAppWhitelist(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        
        if whitelistManager.isWhitelisted(bundleID) {
            whitelistManager.remove(bundleID)
        } else {
            whitelistManager.add(bundleID)
        }
        
        // Don't refresh menu here - let it update next time it opens
        // Calling updateMenu() would close the currently open menu
    }
    
    @objc private func openPreferences() {
        showPreferences?()
    }
    
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshApps()
    }
}

// Custom view for menu items to support right-aligned content
class AppMenuItemView: NSView {
    private var item: StatusBarController.AppDisplayItem
    private let whitelistManager: WhitelistManager
    private var isHovered = false
    private var trackingArea: NSTrackingArea?
    
    init(item: StatusBarController.AppDisplayItem, whitelistManager: WhitelistManager) {
        self.item = item
        self.whitelistManager = whitelistManager
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        
        // Setup tracking area for hover - use activeAlways for menu items
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        setNeedsDisplay(bounds)
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        setNeedsDisplay(bounds)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw highlight if hovered - uses native menu item selection color
        if isHovered {
            NSColor.selectedMenuItemColor.setFill()
            let insetRect = bounds.insetBy(dx: 4, dy: 2)  // Match native menu padding
            let path = NSBezierPath(roundedRect: insetRect, xRadius: 4, yRadius: 4)
            path.fill()
        }
        
        // Draw content - adapt colors based on hover state
        let contentColor: NSColor = isHovered ? .selectedMenuItemTextColor : .labelColor
        let secondaryColor: NSColor = isHovered ? .selectedMenuItemTextColor : .secondaryLabelColor
        
        // 1. Checkbox (Left) - use native NSButtonCell for perfect appearance
        let checkboxRect = NSRect(x: 12, y: 5, width: 16, height: 16)
        
        // Create a button cell configured as a checkbox
        let buttonCell = NSButtonCell()
        buttonCell.setButtonType(.switch)
        buttonCell.controlSize = .small
        buttonCell.title = ""
        buttonCell.allowsMixedState = true  // Enable indeterminate state
        
        // Set the state based on whitelist/playing status
        if item.isWhitelisted {
            buttonCell.state = .on
            buttonCell.isEnabled = true
        } else if item.isPlaying {
            buttonCell.state = .mixed  // Indeterminate state (dash)
            // Enable so user can click to permanently whitelist
            buttonCell.isEnabled = true
        } else {
            buttonCell.state = .off
            buttonCell.isEnabled = true
        }
        
        // Draw the native checkbox
        buttonCell.draw(withFrame: checkboxRect, in: self)
        
        // 2. App Icon (bigger, 24x24)
        if let icon = item.icon {
            let iconRect = NSRect(x: 34, y: 1, width: 24, height: 24)
            icon.draw(in: iconRect)
        }
        
        // 3. App Name
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
            .foregroundColor: contentColor
        ]
        let nameRect = NSRect(x: 64, y: 6, width: 160, height: 16)
        item.name.draw(in: nameRect, withAttributes: nameAttributes)
        
        // 4. Status (Right)
        if !item.isRunning {
            let statusAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: secondaryColor
            ]
            let statusText = "Not Running" as NSString
            let size = statusText.size(withAttributes: statusAttributes)
            let statusRect = NSRect(x: bounds.width - size.width - 12, y: 7, width: size.width, height: 14)
            statusText.draw(in: statusRect, withAttributes: statusAttributes)
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if item.isPlaying && item.isWhitelisted {
            return
        }
        
        // Toggle whitelist status
        if whitelistManager.isWhitelisted(item.bundleID) {
            whitelistManager.remove(item.bundleID)
            item = StatusBarController.AppDisplayItem(
                bundleID: item.bundleID,
                name: item.name,
                icon: item.icon,
                isRunning: item.isRunning,
                isWhitelisted: false,
                isPlaying: item.isPlaying
            )
        } else {
            whitelistManager.add(item.bundleID)
            item = StatusBarController.AppDisplayItem(
                bundleID: item.bundleID,
                name: item.name,
                icon: item.icon,
                isRunning: item.isRunning,
                isWhitelisted: true,
                isPlaying: item.isPlaying
            )
        }
        
        // Redraw to show updated checkmark
        setNeedsDisplay(bounds)
    }
}

// Helper to tint images
extension NSImage {
    func tinted(with color: NSColor) -> NSImage? {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        rect.fill()
        NSGraphicsContext.current?.cgContext.setBlendMode(.destinationIn)
        NSGraphicsContext.current?.cgContext.draw(cgImage, in: rect)
        image.unlockFocus()
        return image
    }
}
