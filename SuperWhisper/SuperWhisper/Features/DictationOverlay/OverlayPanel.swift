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
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isExcludedFromWindowsMenu = true
        repositionToScreen()
    }

    private func setupContent() {
        let contentRect = NSRect(x: 0, y: 0, width: 380, height: 90)
        let visualEffect = NSVisualEffectView(frame: contentRect)
        visualEffect.material = NSVisualEffectView.Material.hudWindow
        visualEffect.blendingMode = NSVisualEffectView.BlendingMode.behindWindow
        visualEffect.state = NSVisualEffectView.State.active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true
        visualEffect.autoresizingMask = [.width, .height]

        let overlayContent = OverlayContentView()
            .environmentObject(appState)
            .environmentObject(settingsService)

        let hostingView = NSHostingView(rootView: AnyView(overlayContent))
        hostingView.frame = contentRect
        hostingView.autoresizingMask = [.width, .height]

        visualEffect.addSubview(hostingView)
        contentView_ = visualEffect
    }

    private var contentView_: NSView? {
        get { contentView }
        set { contentView = newValue }
    }

    private func repositionToScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.minY + 80
        setFrame(NSRect(x: x, y: y, width: frame.width, height: frame.height), display: false)
    }

    // #1: Cancellable work item for hide retries
    private var isAnimating = false
    private var pendingHideWork: DispatchWorkItem?

    func showOverlay() {
        // Cancel any pending hide retry
        pendingHideWork?.cancel()
        pendingHideWork = nil

        guard !isAnimating else { return }
        isAnimating = true

        repositionToScreen()

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
    }

    func hideOverlay() {
        // Cancel any previous pending hide
        pendingHideWork?.cancel()
        pendingHideWork = nil

        guard !isAnimating else {
            // Schedule a single retry (cancellable, no recursion)
            let work = DispatchWorkItem { [weak self] in
                self?.pendingHideWork = nil
                self?.isAnimating = false // Force reset after wait
                self?.hideOverlay()
            }
            pendingHideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            return
        }
        isAnimating = true

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.isAnimating = false
        })
    }
}
