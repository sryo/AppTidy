// Watches for close/quit and enables undo with ⌘⌥Z.

import Cocoa

import os.log

class UndoCloseManager: ObservableObject {
    @Published var isEnabled = false
    let hotkeyManager = HotkeyManager()
    private var finderWindowPaths: [String] = []
    private var activeToken: UndoToken?
    private var toast: ToastWindow?
    private var finderTrackingTimer: Timer?
    private let logger = Logger(subsystem: "com.sryo.AppTidy", category: "UndoClose")
    
    func start() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaults.undoCloseEnabled)
        self.isEnabled = true
        
        // Register for app termination notifications
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidTerminate),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
        
        // Set up hotkey
        hotkeyManager.register { [weak self] in
            self?.performUndo()
        }
        
        // Track Finder windows periodically (store timer to prevent deallocation)
        finderTrackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.trackFinderWindow()
        }
        
        logger.info("UndoCloseManager started")
    }
    
    func stop() {
        UserDefaults.standard.set(false, forKey: Constants.UserDefaults.undoCloseEnabled)
        self.isEnabled = false
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        hotkeyManager.unregister()
        finderTrackingTimer?.invalidate()
        finderTrackingTimer = nil
        activeToken = nil
        toast?.dismiss()
        toast = nil
        logger.info("UndoCloseManager stopped")
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier,
              let appURL = app.bundleURL else {
            return
        }
        
        // Ignore our own app
        guard app.activationPolicy == .regular,
              !bundleID.contains("AppTidy") else {
            return
        }
        
        let appName = app.localizedName ?? "App"
        logger.info("App terminated: \(appName) (\(bundleID))")
        
        // Create undo token
        activeToken = UndoToken(
            bundleID: bundleID,
            appURL: appURL,
            timestamp: Date(),
            finderPath: nil, // Finder windows are handled by trackFinderWindow
            appName: appName
        )
        
        // Show toast
        showToast(for: appName)
    }
    
    private var finderWindowCount: Int = 0
    private var lastFinderPaths: [String] = []
    private let finderQueue = DispatchQueue(label: "com.sryo.AppTidy.finderQueue", qos: .userInitiated)
    private var isTracking = false
    
    private func trackFinderWindow() {
        guard !isTracking else { return }
        isTracking = true
        
        finderQueue.async { [weak self] in
            // Get current Finder window paths
            let currentPaths = AccessibilityHelper.getFinderWindowPaths()
            let currentCount = currentPaths.count
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isTracking = false
                
                let previousCount = self.finderWindowCount
                let previousPaths = self.lastFinderPaths
                
                self.logger.debug("Finder windows: \(previousCount) -> \(currentCount)")
                
                // Only trigger if window COUNT decreased
                if currentCount < previousCount {
                    self.logger.info("Window count decreased! Previous: \(previousCount), Current: \(currentCount)")
                    
                    // When count decreases, pick the most recently tracked path for undo
                    // This handles the case where multiple windows show the same folder
                    if let closedPath = previousPaths.last {
                        self.logger.info("Detected closed Finder window: \(closedPath)")
                        
                        // Create undo token
                        let folderName = URL(fileURLWithPath: closedPath).lastPathComponent
                        let appName = "Finder: \(folderName)"
                        
                        self.activeToken = UndoToken(
                            bundleID: "com.apple.finder",
                            appURL: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                            timestamp: Date(),
                            finderPath: closedPath,
                            appName: appName
                        )
                        
                        self.logger.info("Showing toast for: \(appName)")
                        self.showToast(for: appName)
                    }
                }
                
                // Update state
                self.finderWindowCount = currentCount
                self.lastFinderPaths = currentPaths
            }
        }
    }
    
    func showTestToast() {
        showToast(for: "Test App")
    }
    
    func registerAutoQuit(bundleID: String, appURL: URL, appName: String) {
        // Create undo token for auto-quit
        activeToken = UndoToken(
            bundleID: bundleID,
            appURL: appURL,
            timestamp: Date(),
            finderPath: nil,
            appName: appName
        )
        
        // Show toast with custom message indicating it was auto-quit
        showToast(for: appName)
        logger.info("Registered auto-quit for: \(appName)")
    }
    
    private func showToast(for appName: String) {
        toast?.dismiss()
        toast = ToastWindow(appName: appName, hotkeyString: hotkeyManager.hotkeyString) { [weak self] in
            self?.activeToken = nil
        }
        toast?.show()
    }
    
    private func performUndo() {
        guard let token = activeToken, !token.isExpired() else {
            logger.warning("No valid undo token")
            return
        }
        
        toast?.dismiss()
        toast = nil
        
        // Restore app
        if let finderPath = token.finderPath {
            // Restore Finder window
            let url = URL(fileURLWithPath: finderPath)
            NSWorkspace.shared.open(url)
            logger.info("Restored Finder window at \(finderPath)")
        } else {
            // Relaunch app
            NSWorkspace.shared.openApplication(at: token.appURL, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error = error {
                    self.logger.error("Failed to relaunch \(token.appName): \(error.localizedDescription)")
                } else {
                    self.logger.info("Relaunched \(token.appName)")
                }
            }
        }
        
        activeToken = nil
    }
}
