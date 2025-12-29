// Auto-quits apps with no windows after timeout.

import Cocoa
import os.log

class AppTimeoutManager: ObservableObject {
    private var appStates: [String: AppState] = [:]
    private let appStatesLock = NSLock() // Thread safety for appStates
    private var timer: Timer?
    private let whitelistManager = WhitelistManager()
    private let logger = Logger(subsystem: "com.sryo.AppTidy", category: "AppTimeout")
    private weak var undoCloseManager: UndoCloseManager?
    private let backgroundQueue = DispatchQueue(label: "com.sryo.AppTidy.timeoutQueue", qos: .utility)
    private var isChecking = false
    
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
        // Initial scan of running apps on background thread
        backgroundQueue.async { [weak self] in
            self?.updateAllAppStates()
        }

        // Start periodic timer (every 5 seconds)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkTimeoutsAsync()
        }
        // CRITICAL: Add timer to .common modes so it fires during UI events (scrolling, menus, etc.)
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    private func checkTimeoutsAsync() {
        guard !isChecking else { return }
        isChecking = true

        backgroundQueue.async { [weak self] in
            self?.checkTimeouts()
            DispatchQueue.main.async {
                self?.isChecking = false
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        appStatesLock.lock()
        appStates.removeAll()
        appStatesLock.unlock()
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

        // Build set of currently running bundle IDs for cleanup
        var runningBundleIDs = Set<String>()
        // Track whitelisted apps to remove from tracking
        var whitelistedBundleIDs = Set<String>()

        for app in runningApps {
            guard let bundleID = app.bundleIdentifier else { continue }

            runningBundleIDs.insert(bundleID)

            guard !whitelistManager.isWhitelisted(bundleID),
                  app.activationPolicy == .regular else {
                // Track whitelisted apps so we can remove them from appStates
                whitelistedBundleIDs.insert(bundleID)
                continue
            }

            let windowCount = AccessibilityHelper.getWindowCount(for: app)
            let hasWindows = windowCount > 0

            appStatesLock.lock()
            if let state = appStates[bundleID] {
                state.updateWindowState(hasWindows: hasWindows)
            } else {
                appStates[bundleID] = AppState(bundleID: bundleID, hasWindows: hasWindows)
            }
            appStatesLock.unlock()
        }

        // Clean up stale entries for apps that are no longer running OR are now whitelisted
        appStatesLock.lock()
        let staleKeys = appStates.keys.filter { !runningBundleIDs.contains($0) || whitelistedBundleIDs.contains($0) }
        for key in staleKeys {
            appStates.removeValue(forKey: key)
        }
        appStatesLock.unlock()
    }
    
    private func checkTimeouts() {
        updateAllAppStates()

        let timeout = timeoutSeconds

        // Take a snapshot of app states under lock to avoid holding lock during iteration
        appStatesLock.lock()
        let statesSnapshot = appStates
        appStatesLock.unlock()

        var appsToTerminate: [String] = []

        for (bundleID, state) in statesSnapshot {
            if !state.hasWindows, let closedAt = state.lastWindowClosedAt {
                let elapsed = Date().timeIntervalSince(closedAt)
                if elapsed > 10 && Int(elapsed) % 30 == 0 { // Log periodically
                    logger.debug("\(bundleID) waiting... \(Int(elapsed))/\(Int(timeout))s")
                }
            }

            guard state.shouldTimeout(afterSeconds: timeout) else { continue }

            // Check if app is playing audio (if protection is enabled)
            let protectAudio = UserDefaults.standard.bool(forKey: Constants.UserDefaults.protectAudioApps)
            if protectAudio && (AudioSessionHelper.isPlayingAudio(bundleID: bundleID) || MediaRemoteHelper.isPlaying(bundleID: bundleID)) {
                continue
            }

            logger.notice("Terminating \(bundleID) after \(timeout)s with no windows")
            appsToTerminate.append(bundleID)
        }

        // Remove apps to terminate from tracking (under lock)
        if !appsToTerminate.isEmpty {
            appStatesLock.lock()
            for bundleID in appsToTerminate {
                appStates.removeValue(forKey: bundleID)
            }
            appStatesLock.unlock()
        }

        // Dispatch terminations to main thread
        for bundleID in appsToTerminate {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let workspace = NSWorkspace.shared

                // Find running app
                guard let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
                    return
                }

                // Store info for force terminate fallback
                let pid = app.processIdentifier

                // Try graceful termination first
                _ = app.terminate()

                // Force terminate if app didn't quit gracefully
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self else { return }

                    let stillRunning = NSWorkspace.shared.runningApplications.contains { $0.processIdentifier == pid }
                    if stillRunning {
                        self.logger.notice("App \(bundleID) didn't quit gracefully, force terminating")
                        _ = app.forceTerminate()
                    }
                }

                // Toast is shown by UndoCloseManager's appDidTerminate observer
                // when the app actually terminates
            }
        }
    }
}
