import AppKit
import ApplicationServices

// MARK: - Controller

public final class LayoutExposeController: NSWindowController {
    public static let shared = LayoutExposeController()

    private let orchestrator = LayoutOrchestrator.shared

    private var triggerWindow: AXUIElement?
    private var screenFrame: CGRect = .zero
    private var currentWindows: [LayoutWindowItem] = []
    private var eventMonitor: Any?

    private var cards: [TemplateCardView] = []
    private var selectedIndex: Int = 0 {
        didSet { updateCardSelection() }
    }

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 450),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Present / Dismiss

    public func present(triggerWindow: AXUIElement) {
        self.triggerWindow = triggerWindow
        self.screenFrame = orchestrator.getUsableScreenFrame(for: triggerWindow)
        self.currentWindows = makeWindowItems()
        self.selectedIndex = 0

        buildUI()
        centerOnScreen()

        window?.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1
        }

        installKeyboardMonitor()
    }

    public override func close() {
        uninstallKeyboardMonitor()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let window else { return }
        cards = []

        let fx = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        fx.autoresizingMask = [.width, .height]
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 20
        fx.layer?.masksToBounds = true
        window.contentView = fx

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 0
        outer.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 22, right: 28)
        outer.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            outer.topAnchor.constraint(equalTo: fx.topAnchor),
            outer.bottomAnchor.constraint(equalTo: fx.bottomAnchor)
        ])

        // Header
        let titleLabel = NSTextField(labelWithString: "Layout Exposé")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .white
        outer.addArrangedSubview(titleLabel)
        outer.setCustomSpacing(5, after: titleLabel)

        let subtitle = NSTextField(labelWithString: "Arrange your windows with one click")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.45)
        outer.addArrangedSubview(subtitle)
        outer.setCustomSpacing(22, after: subtitle)

        // Template grid — 3 cards per row
        let templates = LayoutTemplate.all
        let cols = 3
        var cardIndex = 0

        while cardIndex < templates.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 14
            row.distribution = .fillEqually

            for _ in 0..<cols where cardIndex < templates.count {
                let t = templates[cardIndex]
                let icons = autoFillIconsFor(t)
                let card = TemplateCardView(template: t, assignedIcons: icons)
                card.onActivate = { [weak self] in
                    self?.applyTemplate(t)
                }
                row.addArrangedSubview(card)
                cards.append(card)
                cardIndex += 1
            }

            outer.addArrangedSubview(row)
            outer.setCustomSpacing(12, after: row)
        }

        // Footer
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 16
        outer.addArrangedSubview(footer)

        if SpatialTransitionEngine.shared.canUndo {
            let undoBtn = footerButton("↩  Undo Last Layout", action: #selector(undoPressed))
            footer.addArrangedSubview(undoBtn)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)

        let hint = NSTextField(labelWithString: "↑↓←→ navigate  ·  ↵ apply  ·  esc cancel")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = NSColor.white.withAlphaComponent(0.28)
        footer.addArrangedSubview(hint)

        updateCardSelection()
    }

    private func footerButton(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 12)
        return btn
    }

    // MARK: - Apply

    private func applyTemplate(_ template: LayoutTemplate) {
        AppLogger.log("expose: applying \(template.name)", subsystem: "expose")

        let assignments = autoFillFor(template)

        var originalFrames: [AXUIElement: CGRect] = [:]
        for (_, item) in assignments {
            if let frame = orchestrator.getWindowFrame(item.element) {
                originalFrames[item.element] = frame
            }
        }
        SpatialTransitionEngine.shared.registerExposeUndo(frames: originalFrames)

        for slot in template.slots {
            if let item = assignments[slot.id] {
                let target = template.frame(for: slot, in: screenFrame)
                orchestrator.animateWindowFrame(item.element, to: target)
            }
        }

        let event = AppliedLayoutEvent(
            layoutTemplateID: template.id,
            workspacePresetID: nil,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screenFrame.width / max(1, screenFrame.height),
            displayCount: NSScreen.screens.count
        )
        LayoutHistoryStore.shared.recordApply(event: event)

        close()
    }

    // MARK: - Auto-fill helpers

    private func autoFillFor(_ template: LayoutTemplate) -> [Int: LayoutWindowItem] {
        var result: [Int: LayoutWindowItem] = [:]
        var remaining = currentWindows

        for slot in template.slots {
            if let idx = remaining.firstIndex(where: { slot.preferredRoles.contains($0.role) }) {
                result[slot.id] = remaining.remove(at: idx)
            }
        }
        for slot in template.slots where result[slot.id] == nil && !remaining.isEmpty {
            result[slot.id] = remaining.remove(at: 0)
        }
        return result
    }

    private func autoFillIconsFor(_ template: LayoutTemplate) -> [Int: NSImage] {
        Dictionary(uniqueKeysWithValues:
            autoFillFor(template).compactMap { slotID, item in
                item.appIcon.map { (slotID, $0) }
            }
        )
    }

    // MARK: - Keyboard navigation

    private func installKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53:       self.close();          return nil   // Escape
            case 36, 76:   self.applySelected();  return nil   // Return / numpad Enter
            case 123:      self.navigate(-1, axis: .horizontal); return nil  // ←
            case 124:      self.navigate( 1, axis: .horizontal); return nil  // →
            case 125:      self.navigate( 1, axis: .vertical);   return nil  // ↓
            case 126:      self.navigate(-1, axis: .vertical);   return nil  // ↑
            default:       return event
            }
        }
    }

    private func uninstallKeyboardMonitor() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
    }

    private enum NavAxis { case horizontal, vertical }

    private func navigate(_ delta: Int, axis: NavAxis) {
        let cols = 3
        let count = cards.count
        let row = selectedIndex / cols
        let col = selectedIndex % cols

        switch axis {
        case .horizontal:
            let maxCol = min(cols - 1, count - row * cols - 1)
            selectedIndex = row * cols + max(0, min(maxCol, col + delta))
        case .vertical:
            let rows = Int(ceil(Double(count) / Double(cols)))
            let newRow = max(0, min(rows - 1, row + delta))
            selectedIndex = min(count - 1, newRow * cols + col)
        }
    }

    private func applySelected() {
        guard selectedIndex < cards.count else { return }
        cards[selectedIndex].onActivate?()
    }

    private func updateCardSelection() {
        for (i, card) in cards.enumerated() {
            card.setSelected(i == selectedIndex)
        }
    }

    // MARK: - Actions

    @objc private func undoPressed() {
        SpatialTransitionEngine.shared.performExposeUndo()
        close()
    }

    // MARK: - Helpers

    private func centerOnScreen() {
        guard let window, let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let wf = window.frame
        window.setFrameOrigin(CGPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
    }

    private func makeWindowItems() -> [LayoutWindowItem] {
        orchestrator.getAllVisibleWindows().enumerated().map { i, element in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let app = NSRunningApplication(processIdentifier: pid)
            let title = orchestrator.windowTitle(for: element)
            return LayoutWindowItem(
                id: "\(i)-\(title)",
                element: element,
                title: title,
                appName: app?.localizedName,
                bundleID: app?.bundleIdentifier,
                appIcon: app?.icon,
                role: WindowRoleClassifier.classify(appName: app?.localizedName, windowTitle: title)
            )
        }
    }
}

// MARK: - TemplateCardView

final class TemplateCardView: NSView {
    let template: LayoutTemplate
    var assignedIcons: [Int: NSImage]
    var onActivate: (() -> Void)?

    private var isHovered  = false
    private var isSelected = false
    private var trackingArea: NSTrackingArea?

    init(template: LayoutTemplate, assignedIcons: [Int: NSImage]) {
        self.template = template
        self.assignedIcons = assignedIcons
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 136).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        needsDisplay = true
    }

    // MARK: - Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onActivate?() }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Card background
        let bgAlpha: CGFloat = isSelected ? 0.22 : isHovered ? 0.15 : 0.09
        let bgColor: NSColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(bgAlpha)
            : NSColor.white.withAlphaComponent(bgAlpha)
        bgColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()

        // Border
        let borderAlpha: CGFloat = isSelected ? 0.9 : isHovered ? 0.40 : 0.18
        let borderColor: NSColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(borderAlpha)
            : NSColor.white.withAlphaComponent(borderAlpha)
        borderColor.setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 14, yRadius: 14)
        borderPath.lineWidth = isSelected ? 1.5 : 1.0
        borderPath.stroke()

        // Diagram area — leaves 28pt at bottom for the name label
        let nameH: CGFloat = 28
        let pad: CGFloat   = 10
        let diagramRect = CGRect(x: pad, y: nameH, width: bounds.width - pad * 2, height: bounds.height - nameH - pad)

        drawSlots(in: diagramRect)
        drawName()
    }

    private func drawSlots(in diagramRect: CGRect) {
        let slotFill = NSColor.white.withAlphaComponent(isSelected ? 0.28 : 0.18)

        for slot in template.slots {
            // Template uses top-left-origin coords; AppKit uses bottom-left — flip Y
            let flippedY = 1.0 - slot.rect.minY - slot.rect.height
            let gap: CGFloat = 3
            let slotRect = CGRect(
                x: diagramRect.minX + slot.rect.minX * diagramRect.width  + gap,
                y: diagramRect.minY + flippedY      * diagramRect.height  + gap,
                width:  slot.rect.width  * diagramRect.width  - gap * 2,
                height: slot.rect.height * diagramRect.height - gap * 2
            )
            guard slotRect.width > 4, slotRect.height > 4 else { continue }

            slotFill.setFill()
            NSBezierPath(roundedRect: slotRect, xRadius: 5, yRadius: 5).fill()

            if let icon = assignedIcons[slot.id] {
                let maxIcon: CGFloat = 24
                let iconSize = min(maxIcon, slotRect.width * 0.42, slotRect.height * 0.55)
                let iconRect = CGRect(
                    x: slotRect.midX - iconSize / 2,
                    y: slotRect.midY - iconSize / 2,
                    width: iconSize, height: iconSize
                )
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.88)
            }
        }
    }

    private func drawName() {
        let font  = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let color = NSColor.white.withAlphaComponent(isSelected ? 1.0 : 0.72)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str   = NSAttributedString(string: template.name, attributes: attrs)
        let size  = str.size()
        str.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: 7))
    }
}
