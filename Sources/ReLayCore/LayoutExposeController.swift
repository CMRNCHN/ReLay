import AppKit
import ApplicationServices

public final class LayoutExposeController: NSWindowController {
    public static let shared = LayoutExposeController()

    private let orchestrator = LayoutOrchestrator.shared

    private var triggerWindow: AXUIElement?
    private var screenFrame: CGRect = .zero
    private var currentWindows: [LayoutWindowItem] = []
    private var currentWorkspace: WorkspacePreset?

    public private(set) var isPresented: Bool = false

    private var suggestions: [LayoutSuggestionEngine.Suggestion] = []
    private var selectedIndex: Int = 0 { didSet { updateCardSelection() } }
    private var cards: [TemplateCardView] = []
    private var gridCols: Int = 3

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 450),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Present / Dismiss

    public func present(triggerWindow: AXUIElement? = nil) {
        if orchestrator.isStageManagerEnabled() {
            orchestrator.setStageManager(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.presentCore(triggerWindow: triggerWindow)
            }
        } else {
            presentCore(triggerWindow: triggerWindow)
        }
    }

    private func presentCore(triggerWindow: AXUIElement?) {
        self.triggerWindow = triggerWindow
        if let tw = triggerWindow {
            self.screenFrame = orchestrator.getUsableScreenFrame(for: tw)
        } else {
            self.screenFrame = mainScreenFrame()
        }
        self.currentWindows = makeWindowItems()
        self.currentWorkspace = nil
        self.selectedIndex = 0

        buildUI()
        centerOnScreen()

        isPresented = true
        window?.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1
        }
    }

    public override func close() {
        isPresented = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    // MARK: - Keyboard (called by TitleBarInterceptor when isPresented)

    public func handleKeyCode(_ keyCode: UInt16) {
        switch keyCode {
        case 53:       close()
        case 36, 76:   applySelected()
        case 123:      navigate(-1, axis: .horizontal)
        case 124:      navigate( 1, axis: .horizontal)
        case 125:      navigate( 1, axis: .vertical)
        case 126:      navigate(-1, axis: .vertical)
        default:       break
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let window else { return }
        cards = []

        // Frosted glass panel background
        let fx = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        fx.autoresizingMask = [.width, .height]
        fx.material = .underWindowBackground
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 20
        fx.layer?.masksToBounds = true
        window.contentView = fx

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 0
        outer.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 20, right: 24)
        outer.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            outer.topAnchor.constraint(equalTo: fx.topAnchor),
            outer.bottomAnchor.constraint(equalTo: fx.bottomAnchor)
        ])

        // Header
        let titleLabel = NSTextField(labelWithString: "Choose a Layout")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = .labelColor
        outer.addArrangedSubview(titleLabel)
        outer.setCustomSpacing(3, after: titleLabel)

        let subtitle = NSTextField(labelWithString: "Applies to visible windows on this screen")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        outer.addArrangedSubview(subtitle)
        outer.setCustomSpacing(18, after: subtitle)

        // Rank templates via suggestion engine
        let context = LayoutSuggestionEngine.Context(
            windows: currentWindows,
            activeWindow: currentWindows.first(where: { $0.element == triggerWindow }),
            screenSize: screenFrame.size,
            isUltrawide: screenFrame.width > screenFrame.height * 2.1,
            recentTemplateIDs: LayoutHistoryStore.shared.getRecentTemplateIDs(),
            workspaces: LayoutHistoryStore.shared.getWorkspaces(),
            history: LayoutHistoryStore.shared.getHistory()
        )
        suggestions = LayoutSuggestionEngine.rank(context: context)

        // Template grid
        gridCols = suggestions.count <= 4 ? min(suggestions.count, 2) : 3
        if gridCols == 0 { gridCols = 3 }
        var cardIndex = 0

        while cardIndex < suggestions.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 12
            row.distribution = .fillEqually

            for _ in 0..<gridCols where cardIndex < suggestions.count {
                let s = suggestions[cardIndex]
                let icons = autoFillIconsFor(s.template)
                let card = TemplateCardView(template: s.template, assignedIcons: icons, reason: s.reason)
                card.onActivate = { [weak self] in
                    self?.applyTemplate(s.template)
                }
                row.addArrangedSubview(card)
                cards.append(card)
                cardIndex += 1
            }

            // Pad last row with spacers for equal sizing
            while row.arrangedSubviews.count < gridCols {
                let spacer = NSView()
                row.addArrangedSubview(spacer)
            }

            outer.addArrangedSubview(row)
            outer.setCustomSpacing(10, after: row)
        }

        // Saved workspaces row
        let workspaces = LayoutHistoryStore.shared.getWorkspaces().sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
        if !workspaces.isEmpty {
            outer.setCustomSpacing(10, after: outer.arrangedSubviews.last!)

            let sep = NSView()
            sep.wantsLayer = true
            sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
            sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
            outer.addArrangedSubview(sep)
            outer.setCustomSpacing(10, after: sep)

            let wsLabel = NSTextField(labelWithString: "Saved Workspaces")
            wsLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            wsLabel.textColor = .tertiaryLabelColor
            outer.addArrangedSubview(wsLabel)
            outer.setCustomSpacing(6, after: wsLabel)

            let wsRow = NSStackView()
            wsRow.orientation = .horizontal
            wsRow.spacing = 8
            for ws in workspaces.prefix(4) {
                let btn = WorkspaceChipView(workspace: ws)
                btn.onActivate = { [weak self] in self?.applyWorkspace(ws) }
                wsRow.addArrangedSubview(btn)
            }
            let wsSpacer = NSView()
            wsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            wsRow.addArrangedSubview(wsSpacer)
            outer.addArrangedSubview(wsRow)
            outer.setCustomSpacing(10, after: wsRow)
        }

        // Footer
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        outer.addArrangedSubview(footer)

        if SpatialTransitionEngine.shared.canUndo {
            let undoBtn = footerButton("↩  Undo Last Layout", action: #selector(undoPressed))
            footer.addArrangedSubview(undoBtn)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(spacer)

        let hint = NSTextField(labelWithString: "↑↓←→ navigate  ·  ↵ apply  ·  esc close")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .quaternaryLabelColor
        footer.addArrangedSubview(hint)

        updateCardSelection()
    }

    private func footerButton(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    // MARK: - Apply

    private func applyTemplate(_ template: LayoutTemplate, workspace: WorkspacePreset? = nil) {
        AppLogger.log("expose: applying \(template.name)", subsystem: "expose")

        if orchestrator.isStageManagerEnabled() {
            AppLogger.log("expose: disabling Stage Manager to access shelf windows", subsystem: "expose")
            orchestrator.setStageManager(false)
            Thread.sleep(forTimeInterval: 0.35)
            currentWindows = makeWindowItems()
        }

        var assignments: [Int: LayoutWindowItem] = [:]
        var remaining = currentWindows

        if let ws = workspace {
            for (slotID, roles) in ws.slotRules {
                if let idx = remaining.firstIndex(where: { roles.contains($0.role) }) {
                    assignments[slotID] = remaining.remove(at: idx)
                }
            }
        }
        for slot in template.slots {
            if assignments[slot.id] != nil { continue }
            if let idx = remaining.firstIndex(where: { slot.preferredRoles.contains($0.role) }) {
                assignments[slot.id] = remaining.remove(at: idx)
            }
        }
        for slot in template.slots where assignments[slot.id] == nil && !remaining.isEmpty {
            assignments[slot.id] = remaining.remove(at: 0)
        }

        let orderedWindows = template.slots.compactMap { assignments[$0.id]?.element }
        SpatialTransitionEngine.shared.registerExposeState(template: template, windows: orderedWindows, screenFrame: screenFrame)

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
            workspacePresetID: workspace?.id,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screenFrame.width / max(1, screenFrame.height),
            displayCount: NSScreen.screens.count
        )
        LayoutHistoryStore.shared.recordApply(event: event)

        close()
    }

    private func applyWorkspace(_ workspace: WorkspacePreset) {
        guard let template = LayoutTemplate.all.first(where: { $0.id == workspace.layoutTemplateID }) else { return }
        applyTemplate(template, workspace: workspace)
    }

    // MARK: - Icon helper

    private func autoFillIconsFor(_ template: LayoutTemplate) -> [Int: NSImage] {
        var result: [Int: NSImage] = [:]
        var remaining = currentWindows
        for slot in template.slots {
            if let idx = remaining.firstIndex(where: { slot.preferredRoles.contains($0.role) }) {
                let item = remaining.remove(at: idx)
                result[slot.id] = item.appIcon
            }
        }
        for slot in template.slots where result[slot.id] == nil && !remaining.isEmpty {
            result[slot.id] = remaining.remove(at: 0).appIcon
        }
        return result.compactMapValues { $0 }
    }

    // MARK: - Keyboard navigation

    private enum NavAxis { case horizontal, vertical }

    private func navigate(_ delta: Int, axis: NavAxis) {
        let cols = gridCols
        let count = cards.count
        guard count > 0 else { return }
        let row = selectedIndex / cols
        let col = selectedIndex % cols

        switch axis {
        case .horizontal:
            let rowStart = row * cols
            let rowEnd = min(rowStart + cols, count) - 1
            selectedIndex = max(rowStart, min(rowEnd, rowStart + col + delta))
        case .vertical:
            let rows = (count + cols - 1) / cols
            let newRow = max(0, min(rows - 1, row + delta))
            selectedIndex = min(count - 1, newRow * cols + col)
        }
    }

    private func applySelected() {
        guard selectedIndex < suggestions.count else { return }
        applyTemplate(suggestions[selectedIndex].template)
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
        guard let window else { return }
        let screen = nsScreenForScreenFrame() ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let wf = window.frame
        window.setFrameOrigin(CGPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
    }

    /// Convert AX-coordinate screenFrame back to the matching NSScreen.
    private func nsScreenForScreenFrame() -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryH = primary.frame.height
        var bestScreen: NSScreen?
        var bestArea: CGFloat = -1
        for screen in NSScreen.screens {
            let axY = primaryH - (screen.frame.origin.y + screen.frame.height)
            let axFrame = CGRect(x: screen.frame.origin.x, y: axY,
                                 width: screen.frame.width, height: screen.frame.height)
            let area = axFrame.intersection(screenFrame).width * axFrame.intersection(screenFrame).height
            if area > bestArea { bestArea = area; bestScreen = screen }
        }
        return bestScreen
    }

    private func mainScreenFrame() -> CGRect {
        guard let primary = NSScreen.screens.first else { return .zero }
        let target = NSScreen.main ?? primary
        let vf = target.visibleFrame
        let flipped = primary.frame.height - (vf.origin.y + vf.height)
        return CGRect(x: vf.origin.x, y: flipped, width: vf.width, height: vf.height)
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
    let reason: String
    var onActivate: (() -> Void)?

    private var isHovered  = false
    private var isSelected = false
    private var trackingArea: NSTrackingArea?

    init(template: LayoutTemplate, assignedIcons: [Int: NSImage], reason: String = "") {
        self.template = template
        self.assignedIcons = assignedIcons
        self.reason = reason
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 130).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected
        needsDisplay = true
    }

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
        let bg: NSColor
        if isSelected {
            bg = NSColor.controlAccentColor.withAlphaComponent(0.14)
        } else if isHovered {
            bg = NSColor.labelColor.withAlphaComponent(0.07)
        } else {
            bg = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
        }
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()

        // Border
        let borderColor: NSColor = isSelected ? .controlAccentColor : .separatorColor
        let borderAlpha: CGFloat = isSelected ? 0.85 : 0.6
        borderColor.withAlphaComponent(borderAlpha).setStroke()
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        borderPath.lineWidth = isSelected ? 1.5 : 0.5
        borderPath.stroke()

        let nameH: CGFloat = 24
        let reasonH: CGFloat = reason.isEmpty ? 4 : 18
        let pad: CGFloat = 10

        let diagramRect = CGRect(
            x: pad,
            y: reasonH,
            width: bounds.width - pad * 2,
            height: bounds.height - nameH - reasonH - pad / 2
        )

        drawName(at: bounds.height - nameH, height: nameH)
        drawSlots(in: diagramRect)
        if !reason.isEmpty { drawReason(height: reasonH) }
    }

    private func drawName(at yOffset: CGFloat, height: CGFloat) {
        let font  = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let color = NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str   = NSAttributedString(string: template.name, attributes: attrs)
        let size  = str.size()
        let pad: CGFloat = 10
        str.draw(at: CGPoint(x: pad, y: yOffset + (height - size.height) / 2))
    }

    private func drawSlots(in diagramRect: CGRect) {
        let slotFill: NSColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.25)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.18)

        for slot in template.slots {
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
                let maxIcon: CGFloat = 22
                let iconSize = min(maxIcon, slotRect.width * 0.42, slotRect.height * 0.55)
                let iconRect = CGRect(
                    x: slotRect.midX - iconSize / 2,
                    y: slotRect.midY - iconSize / 2,
                    width: iconSize, height: iconSize
                )
                icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 0.85)
            }
        }
    }

    private func drawReason(height: CGFloat) {
        let font  = NSFont.systemFont(ofSize: 10)
        let color = NSColor.tertiaryLabelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str   = NSAttributedString(string: reason, attributes: attrs)
        let size  = str.size()
        let pad: CGFloat = 10
        str.draw(at: CGPoint(x: pad, y: (height - size.height) / 2))
    }
}

// MARK: - WorkspaceChipView

final class WorkspaceChipView: NSView {
    let workspace: WorkspacePreset
    var onActivate: (() -> Void)?

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(workspace: WorkspacePreset) {
        self.workspace = workspace
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onActivate?() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSColor.labelColor.withAlphaComponent(isHovered ? 0.12 : 0.07)
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let str  = NSAttributedString(string: workspace.name, attributes: attrs)
        let size = str.size()
        str.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        let w = workspace.name.size(withAttributes: attrs).width
        return NSSize(width: w + 24, height: 28)
    }
}
