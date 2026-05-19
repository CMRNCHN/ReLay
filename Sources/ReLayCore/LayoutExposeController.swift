import AppKit
import ApplicationServices

public final class LayoutExposeController: NSWindowController {
    public static let shared = LayoutExposeController()

    private let orchestrator = LayoutOrchestrator.shared

    private var triggerWindow: AXUIElement?
    private var screenFrame: CGRect = .zero
    private var currentWindows: [LayoutWindowItem] = []
    private var selectedTemplate: LayoutTemplate?
    private var currentWorkspace: WorkspacePreset?
    private var assignments: [Int: LayoutWindowItem] = [:]
    private var selectedSlotID: Int?
    private var eventMonitor: Any?

    private let rootView = NSView()
    private let titleLabel = NSTextField(labelWithString: "Layout Exposé")
    private let contentStack = NSStackView()

    private init() {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)

        let panel = NSPanel(
            contentRect: screen.insetBy(dx: 80, dy: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        configureRoot()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(triggerWindow: AXUIElement, sessionID: String) {
        self.triggerWindow = triggerWindow
        self.screenFrame = orchestrator.getUsableScreenFrame(for: triggerWindow)
        self.currentWindows = makeWindowItems()
        self.selectedTemplate = nil
        self.currentWorkspace = nil
        self.assignments = [:]
        self.selectedSlotID = nil

        if let screen = NSScreen.main?.frame {
            window?.setFrame(screen.insetBy(dx: 80, dy: 80), display: true)
        }

        renderLayoutSelectionPage()
        setupEventMonitor()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            switch event.keyCode {
            case 53: // Escape
                self.cancelPressed()
                return nil
            case 36: // Return
                if self.selectedTemplate != nil {
                    self.applyPressed()
                }
                return nil
            case 51, 117: // Backspace, Delete
                if let slotID = self.selectedSlotID {
                    self.assignments.removeValue(forKey: slotID)
                    self.renderWindowAssignmentPage()
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    public override func close() {
        removeEventMonitor()
        super.close()
    }

    private func configureRoot() {
        guard let window else { return }

        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        rootView.layer?.cornerRadius = 22

        window.contentView = rootView

        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.alignment = .center

        contentStack.orientation = .vertical
        contentStack.spacing = 18
        contentStack.alignment = .centerX
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 28),
            contentStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -28),
            contentStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 28),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: rootView.bottomAnchor, constant: -28)
        ])
    }

    private func renderLayoutSelectionPage() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let context = LayoutSuggestionEngine.Context(
            windows: currentWindows,
            activeWindow: currentWindows.first(where: { $0.element == triggerWindow }),
            screenSize: screenFrame.size,
            isUltrawide: screenFrame.width > screenFrame.height * 2.1,
            recentTemplateIDs: LayoutHistoryStore.shared.getRecentTemplateIDs(),
            workspaces: LayoutHistoryStore.shared.getWorkspaces(),
            history: LayoutHistoryStore.shared.getHistory()
        )
        let suggestions = LayoutSuggestionEngine.rank(context: context)
        let other = suggestions.dropFirst(3).map { $0.template }

        contentStack.addArrangedSubview(titleLabel)

        contentStack.addArrangedSubview(sectionLabel("Suggested"))
        
        let suggestedRow = NSStackView()
        suggestedRow.orientation = .horizontal
        suggestedRow.spacing = 14
        suggestedRow.alignment = .centerY
        
        for suggestion in suggestions.prefix(3) {
            let button = LayoutTemplateButton(template: suggestion.template, reason: suggestion.reason)
            button.target = self
            button.action = #selector(layoutTemplatePressed(_:))
            suggestedRow.addArrangedSubview(button)
        }
        contentStack.addArrangedSubview(suggestedRow)

        let workspaces = LayoutHistoryStore.shared.getWorkspaces().sorted(by: { $0.lastUsedAt > $1.lastUsedAt })
        if !workspaces.isEmpty {
            contentStack.addArrangedSubview(sectionLabel("Saved Workspaces"))
            let workspaceRow = NSStackView()
            workspaceRow.orientation = .horizontal
            workspaceRow.spacing = 14
            workspaceRow.alignment = .centerY
            
            for workspace in workspaces.prefix(4) {
                let button = WorkspaceButton(workspace: workspace)
                button.target = self
                button.action = #selector(workspacePressed(_:))
                workspaceRow.addArrangedSubview(button)
            }
            contentStack.addArrangedSubview(workspaceRow)
        }

        contentStack.addArrangedSubview(sectionLabel("All Layouts"))
        contentStack.addArrangedSubview(layoutRow(other))

        let footerStack = NSStackView()
        footerStack.orientation = .horizontal
        footerStack.spacing = 20

        if SpatialTransitionEngine.shared.canUndo {
            let undo = NSButton(title: "Undo Last Layout", target: self, action: #selector(undoPressed))
            undo.bezelStyle = .rounded
            footerStack.addArrangedSubview(undo)
        }

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancel.bezelStyle = .rounded
        footerStack.addArrangedSubview(cancel)
        
        contentStack.addArrangedSubview(footerStack)
    }

    private func renderWindowAssignmentPage() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let title = NSTextField(labelWithString: selectedTemplate.map { "Assign Windows: \($0.name)" } ?? "Assign Windows")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.alignment = .center
        contentStack.addArrangedSubview(title)

        contentStack.addArrangedSubview(sectionLabel("Current Windows"))
        contentStack.addArrangedSubview(windowStrip())

        contentStack.addArrangedSubview(sectionLabel("Selected Layout Canvas"))

        if let selectedTemplate {
            let canvas = LayoutCanvasView(
                template: selectedTemplate,
                assignments: assignments,
                selectedSlotID: selectedSlotID,
                itemForID: { [weak self] id in
                    self?.currentWindows.first { $0.id == id }
                },
                onDrop: { [weak self] slotID, item in
                    self?.swapAssignments(slotID: slotID, newItem: item)
                },
                onSelect: { [weak self] slotID in
                    self?.selectedSlotID = slotID
                    self?.renderWindowAssignmentPage()
                }
            )
            canvas.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                canvas.widthAnchor.constraint(equalToConstant: 760),
                canvas.heightAnchor.constraint(equalToConstant: 360)
            ])
            contentStack.addArrangedSubview(canvas)
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        buttonRow.addArrangedSubview(NSButton(title: "Back", target: self, action: #selector(backPressed)))
        buttonRow.addArrangedSubview(NSButton(title: "Cancel", target: self, action: #selector(cancelPressed)))
        buttonRow.addArrangedSubview(NSButton(title: "Auto", target: self, action: #selector(autoFillPressed)))
        buttonRow.addArrangedSubview(NSButton(title: "Apply", target: self, action: #selector(applyPressed)))

        contentStack.addArrangedSubview(buttonRow)
    }

    private func layoutRow(_ templates: [LayoutTemplate]) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 14
        row.alignment = .centerY

        for template in templates {
            let button = LayoutTemplateButton(template: template)
            button.target = self
            button.action = #selector(layoutTemplatePressed(_:))
            row.addArrangedSubview(button)
        }

        return row
    }

    private func windowStrip() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY

        for item in currentWindows {
            let view = WindowTokenView(item: item)
            NSLayoutConstraint.activate([
                view.widthAnchor.constraint(equalToConstant: 150),
                view.heightAnchor.constraint(equalToConstant: 56)
            ])
            row.addArrangedSubview(view)
        }

        return row
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }

    private func getActiveAppName() -> String? {
        guard let window = triggerWindow else { return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private func makeWindowItems() -> [LayoutWindowItem] {
        orchestrator.getAllVisibleWindows().enumerated().map { index, element in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let app = NSRunningApplication(processIdentifier: pid)
            let appName = app?.localizedName
            let bundleID = app?.bundleIdentifier
            let icon = app?.icon
            let title = orchestrator.windowTitle(for: element)
            
            return LayoutWindowItem(
                id: "\(index)-\(title)",
                element: element,
                title: title,
                appName: appName,
                bundleID: bundleID,
                appIcon: icon,
                role: WindowRoleClassifier.classify(appName: appName, windowTitle: title)
            )
        }
    }

    @objc private func layoutTemplatePressed(_ sender: LayoutTemplateButton) {
        selectedTemplate = sender.template
        autoFillAssignments()
        renderWindowAssignmentPage()
    }

    func autoPlaceItem(_ item: LayoutWindowItem) {
        guard let selectedTemplate else { return }
        for slot in selectedTemplate.slots {
            if assignments[slot.id] == nil {
                assignments[slot.id] = item
                renderWindowAssignmentPage()
                return
            }
        }
    }

    private func swapAssignments(slotID: Int, newItem: LayoutWindowItem) {
        // If the item is already assigned to another slot, swap them
        if let existingSlotID = assignments.first(where: { $0.value.id == newItem.id })?.key {
            if let targetExistingItem = assignments[slotID] {
                assignments[existingSlotID] = targetExistingItem
            } else {
                assignments.removeValue(forKey: existingSlotID)
            }
        }
        assignments[slotID] = newItem
        renderWindowAssignmentPage()
    }

    @objc private func backPressed() {
        selectedTemplate = nil
        assignments = [:]
        renderLayoutSelectionPage()
    }

    @objc private func cancelPressed() {
        close()
    }

    @objc private func undoPressed() {
        SpatialTransitionEngine.shared.performExposeUndo()
        close()
    }

    @objc private func autoFillPressed() {
        autoFillAssignments()
        renderWindowAssignmentPage()
    }

    @objc private func applyPressed() {
        AppLogger.log("Layout Expose: Apply pressed", subsystem: "expose")
        guard let selectedTemplate else {
            AppLogger.log("Layout Expose: Apply failed - no template selected", subsystem: "expose")
            return 
        }
        AppLogger.log("Layout Expose: Applying template \(selectedTemplate.name) with \(assignments.count) assignments", subsystem: "expose")

        // Record usage for suggestions
        let event = AppliedLayoutEvent(
            layoutTemplateID: selectedTemplate.id,
            workspacePresetID: currentWorkspace?.id,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screenFrame.width / screenFrame.height,
            displayCount: NSScreen.screens.count
        )
        LayoutHistoryStore.shared.recordApply(event: event)

        // Capture original frames for Undo
        var originalFrames: [AXUIElement: CGRect] = [:]
        for slot in selectedTemplate.slots {
            if let item = assignments[slot.id], 
               let currentFrame = orchestrator.getWindowFrame(item.element) {
                originalFrames[item.element] = currentFrame
            }
        }
        SpatialTransitionEngine.shared.registerExposeUndo(frames: originalFrames)

        for slot in selectedTemplate.slots {
            if let item = assignments[slot.id] {
                let targetFrame = selectedTemplate.frame(for: slot, in: screenFrame)
                AppLogger.log("Layout Expose: Animating \(item.title) to \(targetFrame)", subsystem: "expose")
                orchestrator.animateWindowFrame(item.element, to: targetFrame)
            } else {
                AppLogger.log("Layout Expose: No assignment for slot \(slot.id)", subsystem: "expose")
            }
        }

        renderAppliedConfirmationPage()
    }

    private func renderAppliedConfirmationPage() {
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let successLabel = NSTextField(labelWithString: "Layout Applied")
        successLabel.font = .systemFont(ofSize: 32, weight: .bold)
        successLabel.alignment = .center
        contentStack.addArrangedSubview(successLabel)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 20

        let undoBtn = NSButton(title: "Undo", target: self, action: #selector(undoPressed))
        undoBtn.bezelStyle = .rounded
        buttonRow.addArrangedSubview(undoBtn)

        if currentWorkspace == nil {
            let saveBtn = NSButton(title: "Save as Workspace", target: self, action: #selector(saveWorkspacePressed))
            saveBtn.bezelStyle = .rounded
            buttonRow.addArrangedSubview(saveBtn)
        }

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(cancelPressed))
        doneBtn.bezelStyle = .rounded
        doneBtn.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(doneBtn)

        contentStack.addArrangedSubview(buttonRow)
        
        // Check if we should suggest saving as workspace
        if currentWorkspace == nil {
            let history = LayoutHistoryStore.shared.getHistory()
            let currentRoles = currentWindows.map { $0.role }
            let count = history.filter { 
                $0.layoutTemplateID == selectedTemplate?.id && 
                $0.visibleWindowRoles == currentRoles 
            }.count
            
            if count >= 5 {
                let promoLabel = NSTextField(labelWithString: "You've used this setup \(count) times. Save as workspace?")
                promoLabel.font = .systemFont(ofSize: 13)
                promoLabel.textColor = .secondaryLabelColor
                contentStack.addArrangedSubview(promoLabel)
            }
        }
    }

    @objc private func saveWorkspacePressed() {
        guard let template = selectedTemplate else { return }
        
        // Simple name prompt (in a real app we'd use a better UI)
        let alert = NSAlert()
        alert.messageText = "Save Workspace"
        alert.informativeText = "Enter a name for this workspace:"
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = template.name
        alert.accessoryView = input
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let name = input.stringValue
            var rules: [Int: [WindowRole]] = [:]
            for (slotID, item) in assignments {
                rules[slotID] = [item.role]
            }
            
            let workspace = WorkspacePreset(
                name: name,
                layoutTemplateID: template.id,
                slotRules: rules
            )
            LayoutHistoryStore.shared.saveWorkspace(workspace)
            close()
        }
    }

    @objc private func workspacePressed(_ sender: WorkspaceButton) {
        let workspace = sender.workspace
        guard let template = LayoutTemplate.all.first(where: { $0.id == workspace.layoutTemplateID }) else { return }
        
        selectedTemplate = template
        currentWorkspace = workspace
        
        assignments = [:]
        var remainingWindows = currentWindows
        
        // 1. Apply rules from workspace
        for (slotID, roles) in workspace.slotRules {
            if let index = remainingWindows.firstIndex(where: { roles.contains($0.role) }) {
                assignments[slotID] = remainingWindows.remove(at: index)
            }
        }
        
        // 2. Fill rest
        autoFillAssignments()
        
        renderWindowAssignmentPage()
    }

    private func autoFillAssignments() {
        guard let selectedTemplate else { return }

        // Filter out windows already assigned (e.g. from workspace preset)
        var remainingWindows = currentWindows.filter { item in
            !assignments.values.contains(where: { $0.id == item.id })
        }
        
        // 1. Try to fill empty slots based on preferred roles
        for slot in selectedTemplate.slots {
            if assignments[slot.id] != nil { continue }
            
            if let index = remainingWindows.firstIndex(where: { slot.preferredRoles.contains($0.role) }) {
                assignments[slot.id] = remainingWindows.remove(at: index)
            }
        }
        
        // 2. Fill remaining empty slots with remaining windows
        for slot in selectedTemplate.slots {
            if assignments[slot.id] == nil && !remainingWindows.isEmpty {
                assignments[slot.id] = remainingWindows.remove(at: 0)
            }
        }
    }
}

final class LayoutTemplateButton: NSButton {
    let template: LayoutTemplate

    init(template: LayoutTemplate, reason: String? = nil) {
        self.template = template
        super.init(frame: .zero)

        title = template.name
        if let reason = reason, !reason.isEmpty {
            toolTip = "Suggested because: \(reason)"
        }
        
        bezelStyle = .rounded
        font = .systemFont(ofSize: 15, weight: .semibold)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 150),
            heightAnchor.constraint(equalToConstant: 86)
        ])
        
        if let reason = reason, !reason.isEmpty {
            addReasonBadge(reason)
        }
    }

    private func addReasonBadge(_ reason: String) {
        let label = NSTextField(labelWithString: reason)
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WindowTokenView: NSView, NSDraggingSource {
    let item: LayoutWindowItem

    init(item: LayoutWindowItem) {
        self.item = item
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        addSubview(stack)

        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        if let icon = item.appIcon {
            let iv = NSImageView(image: icon)
            iv.imageScaling = .scaleProportionallyDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 18).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 18).isActive = true
            stack.addArrangedSubview(iv)
        }

        let label = NSTextField(labelWithString: item.title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(label)

        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            LayoutExposeController.shared.autoPlaceItem(item)
            return
        }
        
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.id, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: bitmapImage())

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func bitmapImage() -> NSImage {
        let representation = bitmapImageRepForCachingDisplay(in: bounds)!
        cacheDisplay(in: bounds, to: representation)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }
}

final class LayoutCanvasView: NSView {
    private let template: LayoutTemplate
    private let assignments: [Int: LayoutWindowItem]
    private let itemForID: (String) -> LayoutWindowItem?
    private let onDrop: (Int, LayoutWindowItem) -> Void
    private let onSelect: (Int?) -> Void
    private let selectedSlotID: Int?
    private var hoveredSlotID: Int?

    init(
        template: LayoutTemplate,
        assignments: [Int: LayoutWindowItem],
        selectedSlotID: Int?,
        itemForID: @escaping (String) -> LayoutWindowItem?,
        onDrop: @escaping (Int, LayoutWindowItem) -> Void,
        onSelect: @escaping (Int?) -> Void
    ) {
        self.template = template
        self.assignments = assignments
        self.selectedSlotID = selectedSlotID
        self.itemForID = itemForID
        self.onDrop = onDrop
        self.onSelect = onSelect

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor

        registerForDraggedTypes([.string])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for slot in template.slots {
            let rect = canvasRect(for: slot)
            let isSelected = slot.id == selectedSlotID
            let isHovered = slot.id == hoveredSlotID
            
            if isSelected {
                NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
                NSColor.controlAccentColor.setStroke()
            } else if isHovered {
                NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            } else {
                NSColor.separatorColor.setStroke()
            }
            
            let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
            path.lineWidth = isSelected ? 3 : 2
            path.stroke()

            let text = assignments[slot.id]?.title ?? "Drop window here"
            drawCentered(text, in: rect, isHighlighted: isSelected || isHovered)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let slot = template.slots.first(where: { canvasRect(for: $0).contains(point) })
        onSelect(slot?.id)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateHover(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoveredSlotID = nil
        needsDisplay = true
    }

    private func updateHover(_ sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        let slot = template.slots.first(where: { canvasRect(for: $0).contains(point) })
        if hoveredSlotID != slot?.id {
            hoveredSlotID = slot?.id
            needsDisplay = true
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hoveredSlotID = nil
        needsDisplay = true
        guard
            let id = sender.draggingPasteboard.string(forType: .string),
            let item = itemForID(id)
        else {
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)

        guard let slot = template.slots.first(where: { canvasRect(for: $0).contains(point) }) else {
            return false
        }

        onDrop(slot.id, item)
        return true
    }

    private func canvasRect(for slot: LayoutTemplate.Slot) -> CGRect {
        CGRect(
            x: bounds.minX + slot.rect.minX * bounds.width + 5,
            y: bounds.minY + slot.rect.minY * bounds.height + 5,
            width: slot.rect.width * bounds.width - 10,
            height: slot.rect.height * bounds.height - 10
        )
    }

    private func drawCentered(_ string: String, in rect: CGRect, isHighlighted: Bool = false) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: isHighlighted ? .bold : .medium),
            .foregroundColor: isHighlighted ? NSColor.labelColor : NSColor.secondaryLabelColor
        ]

        let size = string.size(withAttributes: attributes)
        let origin = CGPoint(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2
        )

        string.draw(at: origin, withAttributes: attributes)
    }
}

final class WorkspaceButton: NSButton {
    let workspace: WorkspacePreset

    init(workspace: WorkspacePreset) {
        self.workspace = workspace
        super.init(frame: .zero)

        title = workspace.name
        bezelStyle = .rounded
        font = .systemFont(ofSize: 15, weight: .semibold)
        
        // Add a small badge for usage count
        if workspace.usageCount > 1 {
            toolTip = "Used \(workspace.usageCount) times"
        }

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 150),
            heightAnchor.constraint(equalToConstant: 86)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
