import Foundation
import CoreAudio
import Cocoa

class AudioSessionHelper {
    // Private property selector for getting running clients
    private static let kAudioDevicePropertyDeviceHogMode: AudioObjectPropertySelector = 0x6F727374 // 'orst'
    private static let kAudioDevicePropertyStreamConfiguration: AudioObjectPropertySelector = 0x73636667 // 'scfg'
    
    static func isPlayingAudio(bundleID: String) -> Bool {
        let outputDeviceID = getDefaultOutputDevice()
        guard outputDeviceID != kAudioDeviceUnknown else {
            return false
        }
        
        if !isDeviceActive(outputDeviceID) {
            return false
        }
        
        return checkIfProcessHasAudioOutput(bundleID: bundleID, deviceID: outputDeviceID)
    }
    
    private static func getDefaultOutputDevice() -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = kAudioDeviceUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        return deviceID
    }
    
    private static func isDeviceActive(_ deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var isRunning: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &isRunning
        )
        
        return status == kAudioHardwareNoError && isRunning != 0
    }
    
    private static func checkIfProcessHasAudioOutput(bundleID: String, deviceID: AudioDeviceID) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
              let pid = app.processIdentifier as pid_t? else {
            return false
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-p", "\(pid)", "-Fn"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            return output.contains("CoreAudio") || output.contains("coreaudiod")
        } catch {
            return false
        }
    }
}
