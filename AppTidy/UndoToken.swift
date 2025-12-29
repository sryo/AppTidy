// Undo token for recently closed app/window.

import Foundation

struct UndoToken {
    let bundleID: String
    let appURL: URL
    let timestamp: Date
    let finderPath: String?
    let appName: String
    
    func isExpired() -> Bool {
        return Date().timeIntervalSince(timestamp) > 5.0
    }
    
    var age: TimeInterval {
        return Date().timeIntervalSince(timestamp)
    }
}
