import Foundation

// Opaque types for function pointers
typealias MRMediaRemoteGetNowPlayingClientFunction = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
typealias MRNowPlayingClientGetBundleIdentifierFunction = @convention(c) (AnyObject) -> CFString?
typealias MRMediaRemoteGetNowPlayingApplicationIsPlayingFunction = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

class MediaRemoteHelper {
    static func isPlaying(bundleID: String) -> Bool {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else {
            return false
        }
        defer { dlclose(handle) }
        
        guard let getNowPlayingInfoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") else {
            return false
        }
        
        // Function type for getting now playing info
        typealias GetNowPlayingInfoFunction = @convention(c) (DispatchQueue, @escaping (CFDictionary?) -> Void) -> Void
        let getNowPlayingInfo = unsafeBitCast(getNowPlayingInfoSym, to: GetNowPlayingInfoFunction.self)
        
        var result = false
        let semaphore = DispatchSemaphore(value: 0)
        
        getNowPlayingInfo(DispatchQueue.global()) { info in
            guard let info = info as? [String: Any] else {
                semaphore.signal()
                return
            }
            
            if let clientBundle = info["kMRMediaRemoteNowPlayingApplicationBundleIdentifier"] as? String {
                if clientBundle == bundleID {
                    if let playbackState = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double {
                        result = playbackState > 0
                    } else {
                        result = true
                    }
                }
            }
            
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 1.0)
        
        return result
    }
}
