import SwiftUI

/// Shown when auto-paste needs Accessibility access. Polls the trust state so it flips to
/// "done" the moment the user ticks the box in System Settings.
final class AccessibilityOnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: AccessibilityOnboardingView { [weak self] in self?.close() })
        let window = NSWindow(contentViewController: hosting)
        window.title = "Enable Auto-Paste"
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

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct AccessibilityOnboardingView: View {
    let dismiss: () -> Void
    @State private var trusted = AXPermission.isTrusted

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: trusted ? "checkmark.circle.fill" : "hand.raised.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(trusted ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(trusted ? "Auto-Paste Is On" : "Allow Clippy to Paste for You")
                    .font(.title2.weight(.semibold))
                Text(trusted
                     ? "Clippy can now paste directly into the app you were using."
                     : "To paste into other apps, Clippy needs Accessibility access to press ⌘V on your behalf. Until then, items are copied and you paste them yourself.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !trusted {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Click Open System Settings.")
                    step(2, "Turn on Clippy under Privacy & Security → Accessibility.")
                    step(3, "Come back — this window updates automatically.")
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack {
                if trusted {
                    Button("Done", action: dismiss)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Not Now", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Open System Settings") {
                        AXPermission.requestTrust()
                        AXPermission.openSystemSettings()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .task {
            while !Task.isCancelled {
                let now = AXPermission.isTrusted
                if now != trusted { withAnimation { trusted = now } }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.tint.opacity(0.2)))
            Text(text)
        }
        .accessibilityElement(children: .combine)
    }
}
