import SwiftUI
import ServiceManagement

/// Everything Clippy can ask macOS for, with live status.
enum Permission: String, CaseIterable, Identifiable {
    case accessibility, screenRecording, loginItem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: "Accessibility"
        case .screenRecording: "Screen Recording"
        case .loginItem: "Open at Login"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: "accessibility"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .loginItem: "power"
        }
    }

    var purpose: String {
        switch self {
        case .accessibility:
            "Required to paste into other apps, the ⌘-right-click menu, actions on selected text (⌥⌘K) and paste as text (⌥⇧⌘V)."
        case .screenRecording:
            "Only for capturing text from the screen (⌥⇧⌘2). Screenshots are read on this Mac and deleted right away."
        case .loginItem:
            "Starts Clippy when you log in so your clipboard history is always being kept."
        }
    }

    var isRequired: Bool { self == .accessibility }

    var isGranted: Bool {
        switch self {
        case .accessibility: AXPermission.isTrusted
        case .screenRecording: CGPreflightScreenCaptureAccess()
        case .loginItem: LoginItem.isEnabled
        }
    }

    func request() {
        switch self {
        case .accessibility:
            AXPermission.requestTrust()
            AXPermission.openSystemSettings()
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() {
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            }
        case .loginItem:
            if !LoginItem.setEnabled(true) || LoginItem.requiresApproval {
                open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
            }
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

final class PermissionsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: PermissionsView { [weak self] in self?.window?.close() })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Clippy Permissions"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct PermissionsView: View {
    let dismiss: () -> Void
    @State private var granted: [Permission: Bool] = [:]
    @State private var screenRecordingRequested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set Up Clippy").font(.title2.weight(.semibold))
                    Text("Clippy needs a few permissions from macOS. Turn them on in System Settings — this window updates by itself.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                ForEach(Permission.allCases) { permission in
                    row(permission)
                    if permission != Permission.allCases.last { Divider().padding(.leading, 44) }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if screenRecordingRequested && granted[.screenRecording] != true {
                Text("After allowing Screen Recording, macOS may ask to quit and reopen Clippy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if granted[.accessibility] != true {
                    Text("Without Accessibility, Clippy only copies — you press ⌘V yourself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(allRequiredGranted ? "Done" : "Later", action: dismiss)
                    .keyboardShortcut(allRequiredGranted ? .defaultAction : .cancelAction)
            }
        }
        .padding(22)
        .frame(width: 520)
        .task {
            while !Task.isCancelled {
                var now: [Permission: Bool] = [:]
                for permission in Permission.allCases { now[permission] = permission.isGranted }
                if now != granted { withAnimation { granted = now } }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var allRequiredGranted: Bool {
        Permission.allCases.filter(\.isRequired).allSatisfy { granted[$0] == true }
    }

    private func row(_ permission: Permission) -> some View {
        let isGranted = granted[permission] == true
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(permission.title).font(.headline)
                    Text(permission.isRequired ? "Required" : "Optional")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Text(permission.purpose)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Button(permission == .loginItem ? "Turn On" : "Open Settings") {
                    if permission == .screenRecording { screenRecordingRequested = true }
                    permission.request()
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isGranted ? "Allowed" : "Not allowed")
    }
}

/// Settings → Permissions: what Clippy needs and what's currently allowed.
struct PermissionsSettingsView: View {
    @State private var granted: [Permission: Bool] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(Permission.allCases) { permission in
                    let isGranted = granted[permission] == true
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: permission.symbol)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(permission.title).font(.headline)
                                Text(permission.isRequired ? "Required" : "Optional")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                            Text(permission.purpose)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if isGranted {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            VStack(alignment: .trailing, spacing: 4) {
                                Label("Not allowed", systemImage: permission.isRequired ? "exclamationmark.triangle.fill" : "circle.dashed")
                                    .foregroundStyle(permission.isRequired ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                                Button(permission == .loginItem ? "Turn On" : "Open Settings") { permission.request() }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(isGranted ? "Allowed" : "Not allowed")
                }
            } footer: {
                Text("Status updates automatically. Clippy never needs Full Disk Access, contacts or location. If you just allowed Screen Recording, macOS may ask you to quit and reopen Clippy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                var now: [Permission: Bool] = [:]
                for permission in Permission.allCases { now[permission] = permission.isGranted }
                if now != granted { withAnimation { granted = now } }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
