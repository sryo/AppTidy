// Toast notification with countdown.

import Cocoa
import SwiftUI

class ToastWindow {
    private var window: NSPanel?
    private var toastView: ToastView?
    private var timer: Timer?
    private var secondsRemaining: Int
    private var totalSeconds: Int
    private var onDismiss: (() -> Void)?
    
    init(appName: String, hotkeyString: String, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        // Get custom duration from UserDefaults, default to 5 seconds
        let duration = UserDefaults.standard.integer(forKey: Constants.UserDefaults.toastDurationSeconds)
        self.totalSeconds = duration > 0 ? duration : 5
        self.secondsRemaining = self.totalSeconds
        setupWindow(appName: appName, hotkeyString: hotkeyString)
    }
    
    private func setupWindow(appName: String, hotkeyString: String) {
        let windowWidth: CGFloat = 360
        let windowHeight: CGFloat = 48
        
        // Position based on preference
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let padding: CGFloat = 20
            
            let positionRaw = UserDefaults.standard.string(forKey: "toastPosition") ?? ToastPosition.bottomRight.rawValue
            let position = ToastPosition(rawValue: positionRaw) ?? .bottomRight
            
            var x: CGFloat = 0
            var y: CGFloat = 0
            
            switch position {
            case .topLeft:
                x = screenFrame.minX + padding
                y = screenFrame.maxY - windowHeight - padding
            case .topCenter:
                x = screenFrame.midX - (windowWidth / 2)
                y = screenFrame.maxY - windowHeight - padding
            case .topRight:
                x = screenFrame.maxX - windowWidth - padding
                y = screenFrame.maxY - windowHeight - padding
            case .centerLeft:
                x = screenFrame.minX + padding
                y = screenFrame.midY - (windowHeight / 2)
            case .center:
                x = screenFrame.midX - (windowWidth / 2)
                y = screenFrame.midY - (windowHeight / 2)
            case .centerRight:
                x = screenFrame.maxX - windowWidth - padding
                y = screenFrame.midY - (windowHeight / 2)
            case .bottomLeft:
                x = screenFrame.minX + padding
                y = screenFrame.minY + padding
            case .bottomCenter:
                x = screenFrame.midX - (windowWidth / 2)
                y = screenFrame.minY + padding
            case .bottomRight:
                x = screenFrame.maxX - windowWidth - padding
                y = screenFrame.minY + padding
            }
            
            let panel = NSPanel(
                contentRect: NSRect(x: x, y: y, width: windowWidth, height: windowHeight),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            
            let viewModel = ToastViewModel(
                appName: appName,
                hotkeyString: hotkeyString,
                secondsRemaining: secondsRemaining
            )
            
            let view = ToastView(viewModel: viewModel)
            self.toastView = view
            
            let hostingView = NSHostingView(rootView: view)
            panel.contentView = hostingView
            window = panel
        }
    }

    func show() {
        window?.orderFront(nil)
        
        // Start countdown
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
    }
    
    func dismiss() {
        timer?.invalidate()
        timer = nil
        
        // Quick fadeout animation (0.2 seconds)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window?.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })
    }
    
    private func updateCountdown() {
        secondsRemaining -= 1
        
        if secondsRemaining <= 0 {
            dismiss()
            onDismiss?()
        } else {
            if let hostingView = window?.contentView as? NSHostingView<ToastView> {
                hostingView.rootView.viewModel.secondsRemaining = secondsRemaining
            }
        }
    }
}

class ToastViewModel: ObservableObject {
    let appName: String
    let hotkeyString: String
    @Published var secondsRemaining: Int
    
    init(appName: String, hotkeyString: String, secondsRemaining: Int) {
        self.appName = appName
        self.hotkeyString = hotkeyString
        self.secondsRemaining = secondsRemaining
    }
}

struct ToastView: View {
    @ObservedObject var viewModel: ToastViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Text("Undo close")
                .foregroundColor(Color(white: 0.7))
                .font(.system(size: 14))
            
            Text(viewModel.appName)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            Text(viewModel.hotkeyString)
                .foregroundColor(.white)
                .font(.system(size: 14, weight: .medium))
            
            Text("\(viewModel.secondsRemaining)s")
                .foregroundColor(Color(white: 0.7))
                .font(.system(size: 14))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.2))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(white: 0.3), lineWidth: 1)
        )
    }
}
