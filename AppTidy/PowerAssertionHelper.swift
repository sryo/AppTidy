import Foundation
import Cocoa
import IOKit.pwr_mgt
import Darwin



class PowerAssertionHelper {
    
    private static func getPath(for pid: pid_t) -> String? {
        let maxPathSize = 4096
        var buffer = [Int8](repeating: 0, count: maxPathSize)
        let result = proc_pidpath(pid, &buffer, UInt32(maxPathSize))
        if result > 0 {
            return String(cString: buffer)
        }
        return nil
    }
    
    static func hasPowerAssertion(for bundleID: String) -> Bool {
        var assertions: Unmanaged<CFDictionary>?
        let result = IOPMCopyAssertionsByProcess(&assertions)
        
        guard result == kIOReturnSuccess,
              let assertionsDict = assertions?.takeRetainedValue() as? [Int: [Any]] else {
            return false
        }
        
        // Get target app path to compare against helpers
        let targetPath = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == bundleID })?
            .bundleURL?.path
        
        for (pidNum, appAssertions) in assertionsDict {
            let pid = pid_t(pidNum)
            var isMatch = false
            
            // 1. Check via NSRunningApplication (fast, main app)
            if let app = NSRunningApplication(processIdentifier: pid),
               let appBundleID = app.bundleIdentifier,
               appBundleID.hasPrefix(bundleID) {
                isMatch = true
            }
            // 2. Check via Path (slower, finds helpers)
            else if let targetPath = targetPath,
                    let path = getPath(for: pid),
                    path.contains(targetPath) {
                isMatch = true
            }
            
            if isMatch {
                // Check if any assertion is relevant
                for assertion in appAssertions {
                    if let assertionDict = assertion as? [String: Any],
                       let type = assertionDict[kIOPMAssertionTypeKey] as? String {
                        
                        if type == kIOPMAssertionTypePreventUserIdleSystemSleep ||
                           type == kIOPMAssertionTypePreventSystemSleep ||
                           type == "NoIdleSleepAssertion" ||
                           type == kIOPMAssertionTypePreventUserIdleDisplaySleep {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
}
