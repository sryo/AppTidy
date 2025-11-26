// Global hotkey registration using Carbon.

import Cocoa
import Carbon

class HotkeyManager: ObservableObject {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?
    
    @Published var keyCode: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(keyCode), forKey: Constants.UserDefaults.undoHotkeyKeyCode)
        }
    }
    
    @Published var modifiers: UInt32 {
        didSet {
            UserDefaults.standard.set(Int(modifiers), forKey: Constants.UserDefaults.undoHotkeyModifiers)
        }
    }
    
    init() {
        // Default: ⌘⌥Z (Z = 6)
        let savedKeyCode = UserDefaults.standard.integer(forKey: Constants.UserDefaults.undoHotkeyKeyCode)
        let savedModifiers = UserDefaults.standard.integer(forKey: Constants.UserDefaults.undoHotkeyModifiers)
        
        if savedKeyCode == 0 && savedModifiers == 0 {
            self.keyCode = 6
            self.modifiers = UInt32(cmdKey | optionKey)
        } else {
            self.keyCode = UInt32(savedKeyCode)
            self.modifiers = UInt32(savedModifiers)
        }
    }
    
    func register(callback: @escaping () -> Void) {
        self.callback = callback
        registerHotKey()
    }
    
    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        registerHotKey()
    }
    
    private func registerHotKey() {
        unregister()
        
        let hotKeyID = EventHotKeyID(signature: FourCharCode("undo".fourCharCodeValue), id: 1)
        
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (_, inEvent, userData) -> OSStatus in
            guard let userData = userData else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.callback?()
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    var hotkeyString: String {
        var symbols: [String] = []
        if (modifiers & UInt32(controlKey)) != 0 { symbols.append("⌃") }
        if (modifiers & UInt32(optionKey)) != 0 { symbols.append("⌥") }
        if (modifiers & UInt32(shiftKey)) != 0 { symbols.append("⇧") }
        if (modifiers & UInt32(cmdKey)) != 0 { symbols.append("⌘") }
        symbols.append(keyCodeToString(keyCode))
        return symbols.joined()
    }
    
    func keyCodeToString(_ keyCode: UInt32) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 50: return "`"
        case 65: return "."
        case 67: return "*"
        case 69: return "+"
        case 71: return "Clear"
        case 75: return "/"
        case 76: return "Enter"
        case 78: return "-"
        case 81: return "="
        case 82: return "0"
        case 83: return "1"
        case 84: return "2"
        case 85: return "3"
        case 86: return "4"
        case 87: return "5"
        case 88: return "6"
        case 89: return "7"
        case 91: return "8"
        case 92: return "9"
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 119: return "↘"
        case 121: return "⇟"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "?"
        }
    }
    
    deinit {
        unregister()
    }
}

extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in self.utf8 {
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
}
