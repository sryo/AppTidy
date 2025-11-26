// Auto-quits apps with no windows after timeout.

import Cocoa
import os.log

class AppTimeoutManager: ObservableObject {
    private var appStates: [String: AppState] = [:]
    private var timer: Timer?
    private let whitelistManager = WhitelistManager()
    private let logger = Logger(subsystem: "com.sryo.AppTidy", category: "AppTimeout")
    private weak var undoCloseManager: UndoCloseManager?
    
    @Published var isEnabled: Bool = UserDefaults.standard.bool(forKey: Constants.UserDefaults.appTimeoutEnabled) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Constants.UserDefaults.appTimeoutEnabled)
            if isEnabled {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }
    
    var timeoutSeconds: TimeInterval {
        let value = UserDefaults.standard.integer(forKey: Constants.UserDefaults.appTimeoutSeconds)
        return value > 0 ? TimeInterval(value) : 300 // Default 5 minutes
    }
    
    init(undoCloseManager: UndoCloseManager? = nil) {
        self.undoCloseManager = undoCloseManager
    }
    
    func start() {
        isEnabled = true
    }
    
    func stop() {
        isEnabled = false
    }
    
    private func startTimer() {
        // Initial scan of running apps
        updateAllAppStates()
        
        // Start periodic timer (every 5 seconds)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTimeouts()
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        appStates.removeAll()
    }
    
    private func updateAllAppStates() {
        // Safety check: If we don't have accessibility permissions, we can't count windows.
        // Returning early prevents us from assuming 0 windows and closing apps incorrectly.
        guard AccessibilityHelper.checkPermission() else {
            logger.warning("Missing accessibility permissions. Skipping scan.")
            return
        }
        
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }
            
            
            guard !whitelistManager.isWhitelisted(bundleID),
                  app.activationPolicy == .regular else {
                continue
            }
            
            let windowCount = AccessibilityHelper.getWindowCount(for: app)
            let hasWindows = windowCount > 0
            
            if let state = appStates[bundleID] {
                state.updateWindowState(hasWindows: hasWindows)
            } else {
                appStates[bundleID] = AppState(bundleID: bundleID, hasWindows: hasWindows)
            }
        }
    }
    
    private func checkTimeouts() {
        updateAllAppStates()
        
        let workspace = NSWorkspace.shared
        let timeout = timeoutSeconds
        
        for (bundleID, state) in appStates {
            if !state.hasWindows, let closedAt = state.lastWindowClosedAt {
                let elapsed = Date().timeIntervalSince(closedAt)
                if elapsed > 10 && Int(elapsed) % 30 == 0 { // Log periodically
                    logger.debug("\(bundleID) waiting... \(Int(elapsed))/\(Int(timeout))s")
                }
            }
            
            guard state.shouldTimeout(afterSeconds: timeout) else { continue }
            
            // Find running app
            if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                
                // Check if app is playing audio (if protection is enabled)
                let protectAudio = UserDefaults.standard.bool(forKey: Constants.UserDefaults.protectAudioApps)
                if protectAudio && (AudioSessionHelper.isPlayingAudio(bundleID: bundleID) || MediaRemoteHelper.isPlaying(bundleID: bundleID)) {
                    continue
                }
                
                logger.notice("Terminating \(bundleID) after \(timeout)s with no windows")
                
                // Store app info for undo before terminating
                let appName = app.localizedName ?? "App"
                let appURL = app.bundleURL
                
                // Try graceful termination
                if !app.terminate() {
                    // Force terminate after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        _ = app.forceTerminate()
                    }
                }
                
                // Show toast notification with undo option
                if let undoManager = undoCloseManager, undoManager.isEnabled, let appURL = appURL {
                    undoManager.registerAutoQuit(bundleID: bundleID, appURL: appURL, appName: appName)
                }
                
                // Remove from tracking
                appStates.removeValue(forKey: bundleID)
            }
        }
    }
}
