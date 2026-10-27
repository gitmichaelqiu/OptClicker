import AppKit
import SwiftUI

struct HUDView: View {
    let message: String
    let appIcon: NSImage?
    let systemImage: String?
    let iconColor: Color
    let buttonTitle: String?
    let buttonAction: (() -> Void)?
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var foregroundColor: Color {
        colorScheme == .light ? .black : .white
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if isHovered {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(foregroundColor)
                            .frame(width: 28, height: 28)
                            .background(foregroundColor.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Dismiss"))
                    .accessibilityLabel(String(localized: "Dismiss"))
                } else if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 28, height: 28)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 420, alignment: .leading)

            if let buttonTitle, let buttonAction {
                Button(buttonTitle, action: buttonAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Capsule())
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
    }
}

private final class HUDPanel: NSPanel {
    var isInteractive = false

    override var canBecomeKey: Bool { isInteractive }
    override var canBecomeMain: Bool { isInteractive }
}

enum HUDPresentationStyle {
    case success
    case info
    case warning
    case failure

    var iconColor: Color {
        switch self {
        case .success: .green
        case .info: .blue
        case .warning: .orange
        case .failure: .red
        }
    }
}

final class HUDWindowController: NSWindowController {
    static let shared = HUDWindowController()

    private var hideTimer: Timer?
    private var hostingView: NSHostingView<HUDView>?
    private var glassEffectView: NSView?
    private var legacyVisualEffectView: NSVisualEffectView?
    private var hideDuration: TimeInterval?
    private var isHoveringHUD = false
    private var presentationID = UUID()
    private var hideAnimationID: UUID?

    private init() {
        let panel = HUDPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .statusBar
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        super.init(window: panel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(message: String, style: HUDPresentationStyle, systemImage: String? = nil) {
        guard let panel = window as? HUDPanel else { return }

        presentationID = UUID()
        hideAnimationID = nil
        panel.appearance = NSApp.effectiveAppearance
        hideTimer?.invalidate()
        hideTimer = nil
        hideDuration = nil
        isHoveringHUD = false
        panel.isInteractive = false
        panel.becomesKeyOnlyIfNeeded = false

        let hudView = HUDView(
            message: message,
            appIcon: systemImage == nil ? NSApp.applicationIconImage : nil,
            systemImage: systemImage,
            iconColor: style.iconColor,
            buttonTitle: nil,
            buttonAction: nil,
            onDismiss: { [weak self] in self?.hideWithAnimation() },
            onHoverChanged: { [weak self] hovering in self?.handleHoverChange(hovering) }
        )

        if let hostingView {
            hostingView.rootView = hudView
        } else {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            let hostingView = NSHostingView(rootView: hudView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: container.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])

            let surfaceRoot = NSView()
            surfaceRoot.translatesAutoresizingMaskIntoConstraints = false
            let surfaceInset: CGFloat = 2

            if #available(macOS 26.0, *) {
                let glassView = NSGlassEffectView(frame: .zero)
                glassView.translatesAutoresizingMaskIntoConstraints = false
                glassView.cornerRadius = 26
                glassView.tintColor = NSColor.white.withAlphaComponent(0.03)
                glassView.contentView = container
                surfaceRoot.addSubview(glassView)
                NSLayoutConstraint.activate([
                    glassView.leadingAnchor.constraint(equalTo: surfaceRoot.leadingAnchor, constant: surfaceInset),
                    glassView.trailingAnchor.constraint(equalTo: surfaceRoot.trailingAnchor, constant: -surfaceInset),
                    glassView.topAnchor.constraint(equalTo: surfaceRoot.topAnchor, constant: surfaceInset),
                    glassView.bottomAnchor.constraint(equalTo: surfaceRoot.bottomAnchor, constant: -surfaceInset)
                ])
                self.glassEffectView = glassView
            } else {
                let visualEffectView = NSVisualEffectView(frame: .zero)
                visualEffectView.translatesAutoresizingMaskIntoConstraints = false
                visualEffectView.material = .hudWindow
                visualEffectView.blendingMode = .withinWindow
                visualEffectView.state = .active
                visualEffectView.wantsLayer = true
                visualEffectView.layer?.cornerRadius = 26
                visualEffectView.layer?.masksToBounds = true
                surfaceRoot.addSubview(visualEffectView)
                visualEffectView.addSubview(container)
                NSLayoutConstraint.activate([
                    visualEffectView.leadingAnchor.constraint(equalTo: surfaceRoot.leadingAnchor, constant: surfaceInset),
                    visualEffectView.trailingAnchor.constraint(equalTo: surfaceRoot.trailingAnchor, constant: -surfaceInset),
                    visualEffectView.topAnchor.constraint(equalTo: surfaceRoot.topAnchor, constant: surfaceInset),
                    visualEffectView.bottomAnchor.constraint(equalTo: surfaceRoot.bottomAnchor, constant: -surfaceInset),
                    container.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
                    container.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
                    container.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
                    container.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
                ])
                self.legacyVisualEffectView = visualEffectView
            }

            panel.contentView = surfaceRoot
            self.hostingView = hostingView
        }

        hostingView?.layout()
        let idealSize = hostingView?.intrinsicContentSize ?? NSSize(width: 300, height: 44)
        let contentSize = idealSize.width > 0 && idealSize.height > 0
            ? idealSize
            : NSSize(width: 300, height: 44)
        let surfaceInset: CGFloat = 2
        panel.setContentSize(NSSize(
            width: contentSize.width + surfaceInset * 2,
            height: contentSize.height + surfaceInset * 2
        ))

        if #available(macOS 26.0, *) {
            (glassEffectView as? NSGlassEffectView)?.cornerRadius = contentSize.height / 2
        }
        legacyVisualEffectView?.layer?.cornerRadius = contentSize.height / 2

        positionPanel(panel)
        panel.orderFrontRegardless()
        animateAlpha(1, on: panel, duration: 0.08)

        hideDuration = 1.8
        scheduleHide(after: 1.8)
    }

    private func handleHoverChange(_ hovering: Bool) {
        isHoveringHUD = hovering
        guard let hideDuration else { return }

        if hovering {
            hideTimer?.invalidate()
            hideTimer = nil
        } else {
            scheduleHide(after: hideDuration)
        }
    }

    private func scheduleHide(after duration: TimeInterval) {
        hideTimer?.invalidate()
        guard !isHoveringHUD else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hideWithAnimation()
        }
    }

    private func positionPanel(_ panel: NSWindow) {
        let cursorPoint = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(cursorPoint, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = activeScreen else { return }

        let screenFrame = screen.visibleFrame
        let panelFrame = panel.frame
        panel.setFrameOrigin(NSPoint(
            x: screenFrame.origin.x + (screenFrame.width - panelFrame.width) / 2,
            y: screenFrame.origin.y + 140
        ))
    }

    private func hideWithAnimation() {
        guard let panel = window else { return }
        hideTimer?.invalidate()
        hideTimer = nil
        hideDuration = nil

        let currentPresentationID = presentationID
        let currentHideAnimationID = UUID()
        hideAnimationID = currentHideAnimationID

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: {
            guard self.presentationID == currentPresentationID,
                  self.hideAnimationID == currentHideAnimationID else { return }
            self.hideAnimationID = nil
            panel.orderOut(nil)
        }
    }

    private func animateAlpha(_ alpha: CGFloat, on panel: NSWindow, duration: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = alpha
        }
    }
}
