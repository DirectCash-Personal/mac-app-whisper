import AppKit
import SwiftUI

/// Floating overlay panel — borderless, non-activating, vibrancy-backed.
/// Uses NSPanel to stay above all windows without stealing focus.
class OverlayPanel: NSPanel {
    private var appState: AppStateManager
    private var settingsService: SettingsService
    private var hostingView: NSHostingView<AnyView>?

    init(appState: AppStateManager, settingsService: SettingsService) {
        self.appState = appState
        self.settingsService = settingsService

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 90),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        configure()
        setupContent()
    }

    private func configure() {
        // Panel behavior
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Don't show in dock or window list
        isExcludedFromWindowsMenu = true

        // Position: center horizontally, near bottom of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.minY + 80
            setFrame(NSRect(x: x, y: y, width: frame.width, height: frame.height), display: false)
        }
    }

    private func setupContent() {
        // Visual effect (blur/vibrancy)
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 90)
        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = NSVisualEffectView.Material.hudWindow
        visualEffect.blendingMode = NSVisualEffectView.BlendingMode.behindWindow
        visualEffect.state = NSVisualEffectView.State.active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true
        visualEffect.autoresizingMask = [.width, .height]

        // SwiftUI content
        let overlayContent = OverlayContentView()
            .environmentObject(appState)
            .environmentObject(settingsService)

        let hostingView = NSHostingView(rootView: AnyView(overlayContent))
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]

        // Layer hosting view on top of visual effect
        visualEffect.addSubview(hostingView)
        contentView_ = visualEffect
    }

    private var contentView_: NSView? {
        get { contentView }
        set { contentView = newValue }
    }

    func showOverlay() {
        // Animate in
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hideOverlay() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }
}
