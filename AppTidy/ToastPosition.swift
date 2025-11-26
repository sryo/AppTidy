import SwiftUI

enum ToastPosition: String, CaseIterable, Identifiable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight
    
    var id: String { rawValue }
}
