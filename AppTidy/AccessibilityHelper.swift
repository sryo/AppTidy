import Cocoa
import ApplicationServices
import os.log

struct FinderWindowInfo: Hashable {
    let windowID: Int
    let path: String
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }
    
    static func == (lhs: FinderWindowInfo, rhs: FinderWindowInfo) -> Bool {
        return lhs.windowID == rhs.windowID
    }
}

struct AccessibilityHelper {
    private static let logger = Logger(subsystem: "com.sryo.AppTidy", category: "AccessibilityHelper")
    
    // Check if accessibility permission is granted
    static func checkPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        logger.debug("checkPermission = \(trusted)")
        return trusted
    }
    
    // Request accessibility permission
    static func requestPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options)
    }
    
    // Get window count for a running app
    static func getWindowCount(for app: NSRunningApplication) -> Int {
        guard let pid = app.processIdentifier as pid_t? else { return 0 }
        
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )
        
        guard result == .success,
              let windows = windowsValue as? [AXUIElement] else {
            return 0
        }
        
        // Count ALL windows, including minimized ones
        // Apps with minimized windows should not be automatically closed
        return windows.count
    }
    
    // Get Finder windows with IDs and paths
    static func getFinderWindows() -> [FinderWindowInfo] {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }),
              let pid = finder.processIdentifier as pid_t? else {
            return []
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            logger.error("Failed to get Finder windows (result: \(result.rawValue))")
            return []
        }
        
        var windowInfos: [FinderWindowInfo] = []
        
        for (index, window) in windows.enumerated() {
            var roleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? "Unknown"
            
            var titleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? "Unknown"
            
            var urlValue: CFTypeRef?
            let urlResult = AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &urlValue)
            
            // Try to get stable window identifier - use index and PID as stable ID
            // The AXUIElement pointer changes between polls, but window order is stable
            var identifierValue: CFTypeRef?
            let identifierResult = AXUIElementCopyAttributeValue(window, kAXIdentifierAttribute as CFString, &identifierValue)
            
            // Create stable ID from window index - windows maintain their order
            // Only actual close/open changes the window list, navigation doesn't
            let windowID = index
            
            if urlResult == .success,
               let urlString = urlValue as? String,
               let url = URL(string: urlString) {
                let info = FinderWindowInfo(windowID: windowID, path: url.path)
                windowInfos.append(info)
                logger.debug("Finder window \(windowID): \(url.path)")
            } else {
                // Fallback: Use AppleScript to get path by Title
                if role == "AXWindow" && title != "Unknown" {
                    if let path = getPathViaAppleScript(for: title) {
                        let info = FinderWindowInfo(windowID: windowID, path: path)
                        windowInfos.append(info)
                        logger.debug("Finder window \(windowID) (via AppleScript): \(path)")
                    } else {
                        // Still track it so we detect close, even if we can't restore it perfectly
                        let pseudoPath = "/PseudoPath/\(title)"
                        windowInfos.append(FinderWindowInfo(windowID: windowID, path: pseudoPath))
                        logger.debug("Finder window \(windowID) (pseudo): \(pseudoPath)")
                    }
                }
            }
        }
        
        logger.debug("Total Finder windows: \(windowInfos.count)")
        return windowInfos
    }
    
    // Get Finder window paths (legacy compatibility)
    static func getFinderWindowPaths() -> [String] {
        guard let finder = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.finder" }),
              let pid = finder.processIdentifier as pid_t? else {
            return []
        }
        
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            logger.error("Failed to get Finder windows (result: \(result.rawValue))")
            return []
        }
        
        var paths: [String] = []
        
        for window in windows {
            var roleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String ?? "Unknown"
            
            var titleValue: CFTypeRef?
            _ = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            let title = titleValue as? String ?? "Unknown"
            
            var urlValue: CFTypeRef?
            let urlResult = AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &urlValue)
            
            if urlResult == .success,
               let urlString = urlValue as? String,
               let url = URL(string: urlString) {
                paths.append(url.path)
            } else {
                // Fallback: Use AppleScript via Process (safer than NSAppleScript) to get path by Title
                if role == "AXWindow" && title != "Unknown" {
                    if let path = getPathViaAppleScript(for: title) {
                        paths.append(path)
                    } else {
                        // Still track it so we detect close, even if we can't restore it perfectly.
                        // If we track it as /PseudoPath/Title, restore will fail.
                        // But at least we get the toast.
                        paths.append("/PseudoPath/\(title)")
                    }
                }
            }
        }
        
        return paths
    }
    
    private static func getPathViaAppleScript(for title: String) -> String? {
        let script = "tell application \"Finder\" to get POSIX path of (target of window \"\(title)\" as alias)"
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", script]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()

            // Add timeout to prevent hanging indefinitely
            let timeoutSeconds = 3.0
            let completed = waitForProcess(process, timeout: timeoutSeconds)

            guard completed else {
                // Process timed out - kill it
                process.terminate()
                logger.warning("AppleScript timed out for window: \(title)")
                return nil
            }

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            logger.error("AppleScript failed: \(error.localizedDescription)")
        }

        return nil
    }

    /// Wait for a process to exit with timeout. Returns true if process exited, false if timed out.
    private static func waitForProcess(_ process: Process, timeout: TimeInterval) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)

        process.terminationHandler = { _ in
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + timeout)
        return result == .success
    }
}
