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
        // The overlay content is white-on-dark: pin the dark HUD look instead of following the system light mode.
        appearance = NSAppearance(named: .vibrantDark)
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
        // The behind-window blur is composited by the WindowServer and ignores the layer's cornerRadius: without a
        // mask image it fills the whole window rectangle (square background behind the rounded corners).
        visualEffect.maskImage = Self.roundedMaskImage(cornerRadius: Self.cornerRadius)
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = Self.cornerRadius
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

    private static let cornerRadius: CGFloat = 22

    /// Stretchable rounded-rect mask: only the cap insets keep their shape when the panel is resized.
    private static func roundedMaskImage(cornerRadius: CGFloat) -> NSImage {
        let edgeLength = cornerRadius * 2 + 1
        let maskImage = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        maskImage.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        maskImage.resizingMode = .stretch
        return maskImage
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
        invalidateShadow()  // Shadow follows the rounded mask, not the window rectangle
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
