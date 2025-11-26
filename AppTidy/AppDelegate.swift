// Main app entry point and coordinator.

import Cocoa
import SwiftUI

import os.log

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var appTimeoutManager: AppTimeoutManager?
    private var undoCloseManager: UndoCloseManager?
    private var preferencesWindow: NSWindow?
    private let logger = Logger(subsystem: "com.sryo.AppTidy", category: "AppDelegate")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("applicationDidFinishLaunching called")
        
        // Register default preferences
        UserDefaults.standard.register(defaults: [
            Constants.UserDefaults.appTimeoutEnabled: true,
            Constants.UserDefaults.undoCloseEnabled: true,
            Constants.UserDefaults.toastPosition: "bottomRight",
            Constants.UserDefaults.protectAudioApps: true
        ])
        
        // Ensure app is running as accessory (no dock icon, but can have UI)
        NSApp.setActivationPolicy(.accessory)
        
        // Check permissions
        let trusted = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [trusted: true] as CFDictionary
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        logger.info("AccessibilityHelper: checkPermission = \(accessEnabled)")
        
        // Check accessibility permission
        if !AccessibilityHelper.checkPermission() {
            logger.notice("Requesting accessibility permission")
            AccessibilityHelper.requestPermission()
        } else {
            logger.info("Accessibility permission already granted")
        }
        
        // Initialize managers - order matters for dependencies
        logger.info("Initializing managers")
        undoCloseManager = UndoCloseManager()
        appTimeoutManager = AppTimeoutManager(undoCloseManager: undoCloseManager)
        
        // Create status bar immediately
        statusBarController = StatusBarController(
            appTimeoutManager: appTimeoutManager!,
            undoCloseManager: undoCloseManager!
        )
        
        statusBarController?.showPreferences = { [weak self] in
            self?.showPreferences()
        }
        
        logger.info("Status bar controller created")
        
        // Start managers if enabled
        if UserDefaults.standard.bool(forKey: Constants.UserDefaults.appTimeoutEnabled) {
            logger.info("Starting AppTimeout")
            appTimeoutManager?.start()
        }
        let undoEnabled = UserDefaults.standard.bool(forKey: Constants.UserDefaults.undoCloseEnabled)
        logger.info("undoCloseEnabled = \(undoEnabled)")
        
        if undoEnabled {
            logger.info("Starting UndoClose")
            undoCloseManager?.start()
        }
        
        // Window is not shown automatically on launch.
        // User can open it from the menu bar.
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // No need to stop managers here, as calling stop() would disable the features in UserDefaults.
        // The OS will clean up resources (timers, observers) automatically.
    }
    
    private func showPreferences() {
        logger.info("showPreferences called")
        
        if preferencesWindow == nil {
            logger.info("Creating new preferences window")
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AppTidy Preferences"
            window.center()
            window.isReleasedWhenClosed = false
            
            // Create dummy managers if needed for the view
            let timeoutManager = appTimeoutManager ?? AppTimeoutManager()
            let undoManager = undoCloseManager ?? UndoCloseManager()
            
            window.contentView = NSHostingView(
                rootView: PreferencesView(
                    appTimeoutManager: timeoutManager,
                    undoCloseManager: undoManager
                )
            )
            preferencesWindow = window
        }
        
        logger.info("Ordering window front")
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
