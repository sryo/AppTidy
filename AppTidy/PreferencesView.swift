// Preferences UI with General, Whitelist, Permissions, and About sections.

import SwiftUI

struct PreferencesView: View {
    @ObservedObject var appTimeoutManager: AppTimeoutManager
    @ObservedObject var undoCloseManager: UndoCloseManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab(
                appTimeoutManager: appTimeoutManager,
                undoCloseManager: undoCloseManager
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(0)
            
            PermissionsTab()
                .tabItem {
                    Label("Permissions", systemImage: "lock.shield")
                }
                .tag(1)
            
            AboutTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(2)
        }
    }
}

// MARK: - General Settings

struct GeneralTab: View {
    @ObservedObject var appTimeoutManager: AppTimeoutManager
    @ObservedObject var undoCloseManager: UndoCloseManager
    @AppStorage(Constants.UserDefaults.appTimeoutSeconds) private var timeoutSeconds = 300
    @AppStorage(Constants.UserDefaults.appTimeoutEnabled) private var appTimeoutEnabled = true
    @AppStorage(Constants.UserDefaults.undoCloseEnabled) private var undoCloseEnabled = true
    @AppStorage(Constants.UserDefaults.toastPosition) private var toastPosition = ToastPosition.bottomRight
    @AppStorage(Constants.UserDefaults.protectAudioApps) private var protectAudioApps = true
    @AppStorage(Constants.UserDefaults.toastDurationSeconds) private var toastDuration = 5
    @State private var launchAtLogin = LoginItemManager.shared.isEnabled
    
    var body: some View {
        Form {
            // AppTimeout Section
            Section {
                LabeledContent {
                    Toggle("", isOn: Binding(
                        get: { appTimeoutManager.isEnabled },
                        set: { enabled in
                            if enabled {
                                appTimeoutManager.start()
                            } else {
                                appTimeoutManager.stop()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                } label: {
                    Label("Quit apps with no windows", systemImage: "hourglass")
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Timeout")
                        Picker("", selection: $timeoutSeconds) {
                            Text("1 minute").tag(60)
                            Text("5 minutes").tag(300)
                            Text("10 minutes").tag(600)
                            Text("30 minutes").tag(1800)
                        }
                        .labelsHidden()
                    }

                    Divider()
                    
                    Toggle("Skip quitting apps playing audio", isOn: $protectAudioApps)
                }
                .padding(.vertical, 4)
                .disabled(!appTimeoutManager.isEnabled)
            } header: {
                Text("AppTimeout")
            }
            
            // UndoClose Section
            Section {
                LabeledContent {
                    Toggle("", isOn: Binding(
                        get: { undoCloseManager.isEnabled },
                        set: { enabled in
                            if enabled {
                                undoCloseManager.start()
                            } else {
                                undoCloseManager.stop()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                } label: {
                    Label("Undo closed apps", systemImage: "arrow.uturn.backward")
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Text("Undo Period")
                        Picker("", selection: $toastDuration) {
                            Text("3 seconds").tag(3)
                            Text("5 seconds").tag(5)
                            Text("10 seconds").tag(10)
                            Text("15 seconds").tag(15)
                        }
                        .labelsHidden()
                        .onChange(of: toastDuration) { _ in
                            undoCloseManager.showTestToast()
                        }
                        
                        Spacer()
                        
                        Text("Shortcut:")
                        HotkeyRecorder(hotkeyManager: undoCloseManager.hotkeyManager)
                    }
                    
                    Divider()
                    
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Position")
                            
                            Text("Choose where notifications will appear on screen")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        ToastPositionPicker(selection: $toastPosition)
                            .onChange(of: toastPosition) { _ in
                                undoCloseManager.showTestToast()
                            }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("UndoClose")
            }
            
            // Startup Section
            Section {
                LabeledContent("Launch at Login") {
                    Toggle("", isOn: Binding(
                        get: { launchAtLogin },
                        set: { enabled in
                            LoginItemManager.shared.isEnabled = enabled
                            launchAtLogin = enabled
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            } header: {
                Text("Startup")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions Settings

struct PermissionsTab: View {
    @State private var hasAccessibility = AccessibilityHelper.checkPermission()
    @State private var permissionCheckTimer: Timer?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AppTidy requires the following permissions:")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
            
            // Accessibility Permission
            PermissionRow(
                icon: "hand.point.up.left",
                title: "Accessibility",
                description: "Required to detect window states and control app lifecycle",
                isGranted: hasAccessibility,
                action: {
                    AccessibilityHelper.requestPermission()
                }
            )
            
            Spacer()
            
            HStack {
                Text("After granting permissions in System Settings, the status will update automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Check Again") {
                    hasAccessibility = AccessibilityHelper.checkPermission()
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            
            Text("If the status doesn't update, try restarting the app.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .onAppear {
            hasAccessibility = AccessibilityHelper.checkPermission()
            // Start periodic checking to update when user grants permissions
            permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                hasAccessibility = AccessibilityHelper.checkPermission()
            }
        }
        .onDisappear {
            permissionCheckTimer?.invalidate()
            permissionCheckTimer = nil
        }
    }
}

// MARK: - Permission Row

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(isGranted ? .green : .orange)
                .frame(width: 32, alignment: .leading)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(isGranted ? .green : .orange)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !isGranted, let action = action {
                    Button("Grant Permission") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - About Settings

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)
            
            Text("AppTidy")
                .font(.title)
                .bold()
            
            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Keep your Mac tidy by auto-quitting unused apps and undoing accidental closes.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Text("© 2025")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }
}



// MARK: - Toast Position Picker

struct ToastPositionPicker: View {
    @Binding var selection: ToastPosition
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<3) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3) { col in
                        let position = position(row: row, col: col)
                        Circle()
                            .fill(selection == position ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 12, height: 12)
                            .onTapGesture {
                                selection = position
                            }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    func position(row: Int, col: Int) -> ToastPosition {
        let positions: [[ToastPosition]] = [
            [.topLeft, .topCenter, .topRight],
            [.centerLeft, .center, .centerRight],
            [.bottomLeft, .bottomCenter, .bottomRight]
        ]
        return positions[row][col]
    }
}



