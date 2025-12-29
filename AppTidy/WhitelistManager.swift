// Manages app whitelist.

import Foundation

class WhitelistManager: ObservableObject {
    private let key = "whitelistedBundleIDs"
    
    // Default system apps to whitelist (always protected)
    private let defaultWhitelist = [
        "com.apple.finder",
        "com.apple.controlcenter",
        "com.apple.dock",
        "com.apple.loginwindow"
    ]
    
    var whitelistedBundleIDs: Set<String> {
        get {
            let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
            return Set(stored + defaultWhitelist)
        }
        set {
            let userAdded = newValue.subtracting(defaultWhitelist)
            UserDefaults.standard.set(Array(userAdded), forKey: key)
        }
    }
    
    func isWhitelisted(_ bundleID: String) -> Bool {
        return whitelistedBundleIDs.contains(bundleID)
    }
    
    func add(_ bundleID: String) {
        var current = whitelistedBundleIDs
        current.insert(bundleID)
        whitelistedBundleIDs = current
    }
    
    func remove(_ bundleID: String) {
        var current = whitelistedBundleIDs
        current.remove(bundleID)
        whitelistedBundleIDs = current
    }
}
