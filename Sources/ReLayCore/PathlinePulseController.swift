import AppKit

// MARK: - PathlinePulseController
//
// The menu bar entry point for Pathline. A lightweight NSPopover showing:
//   • The active/last workspace name
//   • Recent layouts as quick-apply cards
//   • A button to open Layout Library
//
// This is the "front door." Layout Library is the editing surface.

public final class PathlinePulseController: NSObject {
    public static let shared = PathlinePulseController()

    private let history = LayoutHistoryStore.shared
    private let appLibrary = AppLibraryStore.shared

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var pulseView: PulseContentView?

    private override init() { super.init() }

    // MARK: - Setup

    public func install(into item: NSStatusItem) {
        self.statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseDown])
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if let popover, popover.isShown {
            close()
        } else {
            open(relativeTo: sender)
        }
    }

    private func open(relativeTo button: NSStatusBarButton) {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true

        let view = PulseContentView(
            recentLayouts: recentLayoutSummaries(),
            activeLayoutName: activeLayoutName(),
            onSelectLayout: { [weak self] templateID in
                self?.close()
                self?.quickApply(templateID: templateID)
            },
            onOpenLibrary: { [weak self] in
                self?.close()
                LayoutLibraryController.shared.present()
            }
        )
        view.frame = CGRect(x: 0, y: 0, width: 300, height: view.preferredHeight)
        pulseView = view

        let vc = NSViewController()
        vc.view = view
        pop.contentViewController = vc
        pop.contentSize = NSSize(width: 300, height: view.preferredHeight)

        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = pop
    }

    public func close() {
        popover?.close()
        popover = nil
        pulseView = nil
    }

    // MARK: - Quick Apply

    private func quickApply(templateID: String) {
        guard let template = LayoutTemplate.all.first(where: { $0.id == templateID }) else { return }
        let orchestrator = LayoutOrchestrator.shared

        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        let axApp = AXUIElementCreateApplication(frontmost.processIdentifier)
        var ref: CFTypeRef?
        let triggerWindow: AXUIElement? = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success
            ? (ref as! AXUIElement)
            : nil

        let screen = orchestrator.getUsableScreenFrame(for: triggerWindow ?? AXUIElementCreateSystemWide())
        guard screen != .zero else { return }

        // Tile all visible windows into template slots
        let windows = orchestrator.getAllVisibleWindows()
        for (i, slot) in template.slots.enumerated() where i < windows.count {
            orchestrator.animateWindowFrame(windows[i], to: CGRect(
                x: screen.origin.x + slot.rect.origin.x * screen.width,
                y: screen.origin.y + slot.rect.origin.y * screen.height,
                width: slot.rect.width * screen.width,
                height: slot.rect.height * screen.height
            ), source: "expose")
        }

        let historyStore = LayoutHistoryStore.shared
        historyStore.recordApply(event: AppliedLayoutEvent(
            layoutTemplateID: templateID,
            workspacePresetID: nil,
            visibleWindowRoles: [],
            visibleAppBundleIDs: [],
            screenAspectRatio: screen.width / max(screen.height, 1),
            displayCount: NSScreen.screens.count
        ))
    }

    // MARK: - Data

    private func activeLayoutName() -> String {
        history.getRecentTemplateIDs().first
            .flatMap { id in LayoutTemplate.all.first(where: { $0.id == id })?.name }
            ?? "—"
    }

    private func recentLayoutSummaries() -> [LayoutSummary] {
        let recentIDs = history.getRecentTemplateIDs().prefix(5)
        let saved = history.getSavedLayouts()

        return recentIDs.compactMap { id -> LayoutSummary? in
            guard let template = LayoutTemplate.all.first(where: { $0.id == id }) else { return nil }
            let savedName = saved.first(where: { $0.templateID == id })?.name
            return LayoutSummary(templateID: id, name: savedName ?? template.name, template: template)
        }
    }

    struct LayoutSummary {
        let templateID: String
        let name: String
        let template: LayoutTemplate
    }
}

// MARK: - PulseContentView

private final class PulseContentView: NSView {
    private let recentLayouts: [PathlinePulseController.LayoutSummary]
    private let activeLayoutName: String
    private var onSelectLayout: (String) -> Void
    private var onOpenLibrary: () -> Void

    var preferredHeight: CGFloat {
        let rowHeight: CGFloat = 56
        let baseHeight: CGFloat = 100 // header + footer
        return baseHeight + CGFloat(recentLayouts.count) * (rowHeight + 6)
    }

    init(recentLayouts: [PathlinePulseController.LayoutSummary],
         activeLayoutName: String,
         onSelectLayout: @escaping (String) -> Void,
         onOpenLibrary: @escaping () -> Void) {
        self.recentLayouts = recentLayouts
        self.activeLayoutName = activeLayoutName
        self.onSelectLayout = onSelectLayout
        self.onOpenLibrary = onOpenLibrary
        super.init(frame: .zero)
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        wantsLayer = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Header row: "Pathline" + active workspace indicator
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.spacing = 8

        let pathlineLabel = NSTextField(labelWithString: "Pathline")
        pathlineLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        pathlineLabel.textColor = .labelColor
        headerRow.addArrangedSubview(pathlineLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(spacer)

        if activeLayoutName != "—" {
            let activePill = makePill(activeLayoutName)
            headerRow.addArrangedSubview(activePill)
        }

        stack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        stack.setCustomSpacing(14, after: headerRow)

        // Recent layouts
        if !recentLayouts.isEmpty {
            let recentLabel = NSTextField(labelWithString: "RECENT")
            recentLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
            recentLabel.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(recentLabel)
            stack.setCustomSpacing(8, after: recentLabel)

            for summary in recentLayouts {
                let row = PulseLayoutRow(summary: summary) { [weak self] in
                    self?.onSelectLayout(summary.templateID)
                }
                row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
                stack.addArrangedSubview(row)
                stack.setCustomSpacing(6, after: row)
            }
        } else {
            let empty = NSTextField(labelWithString: "No recent layouts.")
            empty.font = .systemFont(ofSize: 11.5)
            empty.textColor = .tertiaryLabelColor
            stack.addArrangedSubview(empty)
        }

        stack.setCustomSpacing(16, after: stack.arrangedSubviews.last ?? headerRow)

        // Separator
        let sep = NSView()
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
        sep.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        stack.addArrangedSubview(sep)
        stack.setCustomSpacing(12, after: sep)

        // Footer: Open Layout Library button
        let libraryBtn = NSButton(title: "Open Layout Library…", target: self, action: #selector(openLibraryTapped))
        libraryBtn.bezelStyle = .roundRect
        libraryBtn.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(libraryBtn)
    }

    private func makePill(_ text: String) -> NSView {
        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        pill.layer?.cornerRadius = 10

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .controlAccentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -3),
        ])
        return pill
    }

    @objc private func openLibraryTapped() { onOpenLibrary() }
}

// MARK: - PulseLayoutRow

private final class PulseLayoutRow: NSView {
    private var onTap: () -> Void
    private let summary: PathlinePulseController.LayoutSummary
    private var isHovered = false

    init(summary: PathlinePulseController.LayoutSummary, onTap: @escaping () -> Void) {
        self.summary = summary
        self.onTap = onTap
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        heightAnchor.constraint(equalToConstant: 50).isActive = true
        buildRow()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildRow() {
        // Mini template thumbnail on the left
        let thumb = PulseThumbnail(template: summary.template)
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.widthAnchor.constraint(equalToConstant: 60).isActive = true
        thumb.heightAnchor.constraint(equalToConstant: 38).isActive = true
        addSubview(thumb)

        let nameLabel = NSTextField(labelWithString: summary.name)
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let slotCount = NSTextField(labelWithString: "\(summary.template.slots.count) slots")
        slotCount.font = .systemFont(ofSize: 10.5)
        slotCount.textColor = .secondaryLabelColor
        slotCount.translatesAutoresizingMaskIntoConstraints = false
        addSubview(slotCount)

        let applyBtn = NSButton(title: "Apply", target: self, action: #selector(tapped))
        applyBtn.bezelStyle = .roundRect
        applyBtn.font = .systemFont(ofSize: 11)
        applyBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(applyBtn)

        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),

            slotCount.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            slotCount.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),

            applyBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            applyBtn.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func tapped() { onTap() }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
}

// MARK: - PulseThumbnail

private final class PulseThumbnail: NSView {
    private let template: LayoutTemplate

    init(template: LayoutTemplate) {
        self.template = template
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.25).cgColor
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let pad: CGFloat = 3
        let inner = bounds.insetBy(dx: pad, dy: pad)
        let gap: CGFloat = 1.5

        for slot in template.slots {
            let r = CGRect(
                x: inner.origin.x + slot.rect.origin.x * inner.width + gap,
                y: inner.origin.y + slot.rect.origin.y * inner.height + gap,
                width: slot.rect.width * inner.width - gap * 2,
                height: slot.rect.height * inner.height - gap * 2
            )
            let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            NSColor.controlAccentColor.withAlphaComponent(0.35).setFill()
            path.fill()
        }
    }
}
