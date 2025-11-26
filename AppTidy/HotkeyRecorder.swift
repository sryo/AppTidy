import SwiftUI
import Carbon

struct HotkeyRecorder: View {
    @ObservedObject var hotkeyManager: HotkeyManager
    @State private var isRecording = false
    @State private var eventMonitor: Any?
    
    var body: some View {
        Button(action: {
            // Double click handled by onTapGesture count: 2
        }) {
            HStack(spacing: 4) {
                if isRecording {
                    Text("Press keys...")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.accentColor, lineWidth: 2)
                        )
                } else {
                    hotkeyView
                }
            }
        }
        .buttonStyle(.plain)
        .onTapGesture(count: 2) {
            startRecording()
        }
        .onTapGesture(count: 1) {
            // Consume single tap to prevent other actions if needed
        }
    }
    
    private var hotkeyView: some View {
        HStack(spacing: 4) {
            ForEach(modifiersList, id: \.self) { symbol in
                KeyCap(text: symbol)
            }
            KeyCap(text: keyString)
        }
        .padding(4)
        .background(Color.clear)
        .contentShape(Rectangle()) // Make the whole area tappable
    }
    
    private var modifiersList: [String] {
        var symbols: [String] = []
        let mods = hotkeyManager.modifiers
        
        if (mods & UInt32(controlKey)) != 0 { symbols.append("⌃") }
        if (mods & UInt32(optionKey)) != 0 { symbols.append("⌥") }
        if (mods & UInt32(shiftKey)) != 0 { symbols.append("⇧") }
        if (mods & UInt32(cmdKey)) != 0 { symbols.append("⌘") }
        
        return symbols
    }
    
    private var keyString: String {
        return hotkeyManager.keyCodeToString(hotkeyManager.keyCode)
    }
    
    private func startRecording() {
        isRecording = true
        
        // Capture global key events locally while recording
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Ignore just modifier keys
            if event.modifierFlags.contains(.command) || 
               event.modifierFlags.contains(.option) || 
               event.modifierFlags.contains(.control) || 
               event.modifierFlags.contains(.shift) {
                
                // If a non-modifier key is pressed, record it
                // We check if the key code is not a modifier key code
                // 54=cmd(right), 55=cmd, 56=shift, 57=caps, 58=opt, 59=ctrl, 60=shift(right), 61=opt(right), 62=ctrl(right)
                let modKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
                if !modKeyCodes.contains(event.keyCode) {
                    saveHotkey(event: event)
                    return nil // Consume event
                }
            }
            
            // Allow Escape to cancel
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }
            
            return nil // Consume all key events while recording
        }
    }
    
    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func saveHotkey(event: NSEvent) {
        var carbonModifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        hotkeyManager.updateHotkey(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        stopRecording()
    }
}

struct KeyCap: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
    }
}
