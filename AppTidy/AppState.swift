// Tracks window state for a running app.

import Foundation

class AppState {
    let bundleID: String
    var hasWindows: Bool
    var lastWindowClosedAt: Date?
    
    init(bundleID: String, hasWindows: Bool = true) {
        self.bundleID = bundleID
        self.hasWindows = hasWindows
        if !hasWindows {
            self.lastWindowClosedAt = Date()
        } else {
            self.lastWindowClosedAt = nil
        }
    }
    
    func updateWindowState(hasWindows: Bool) {
        let hadWindows = self.hasWindows
        self.hasWindows = hasWindows
        
        // Transition from windows to no windows
        if hadWindows && !hasWindows {
            lastWindowClosedAt = Date()
        }
        // Transition from no windows to windows
        else if !hadWindows && hasWindows {
            lastWindowClosedAt = nil
        }
    }
    
    func shouldTimeout(afterSeconds timeout: TimeInterval) -> Bool {
        guard !hasWindows, let closedAt = lastWindowClosedAt else {
            return false
        }
        return Date().timeIntervalSince(closedAt) >= timeout
    }
}
