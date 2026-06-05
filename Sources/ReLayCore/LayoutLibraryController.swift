import AppKit
import ApplicationServices

// MARK: - Pasteboard Type

private let kLayoutAppPasteboardType = NSPasteboard.PasteboardType("com.relay.layoutapp")

// MARK: - LayoutLibraryController

/// Single source of truth for layout management UI.
/// Replaces LayoutExposeController. All callers route through this singleton.
public final class LayoutLibraryController: NSWindowController {
    public static let shared = LayoutLibraryController()

    private let orchestrator = LayoutOrchestrator.shared
    private let history = LayoutHistoryStore.shared
    private let appLibrary = AppLibraryStore.shared

    public private(set) var isPresented: Bool = false

    private var selectedTemplateID: String = LayoutTemplate.all.first?.id ?? "split"
    private var slotAssignments: [Int: String] = [:]
    private var triggerWindow: AXUIElement?
    private var currentWindows: [LayoutWindowItem] = []

    private var sidebarView: LibrarySidebarView?
    private var canvasView: LibraryCanvasView?
    private var dockView: LibraryAppDockView?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
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
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Present / Dismiss

    public func present(triggerWindow: AXUIElement? = nil) {
        guard !isPresented else { dismiss(); return }
        self.triggerWindow = triggerWindow
        currentWindows = makeWindowItems(triggerWindow: triggerWindow)

        // Spatial suggestion — selects best template, but slots start EMPTY
        let screen = orchestrator.getUsableScreenFrame(for: triggerWindow ?? AXUIElementCreateSystemWide())
        let suggestion = LayoutSuggestionEngine.rank(context: LayoutSuggestionEngine.Context(
            windows: currentWindows,
            activeWindow: currentWindows.first(where: { $0.isActive }),
            screenSize: screen.size,
            isUltrawide: screen.width / max(screen.height, 1) > 2.0,
            recentTemplateIDs: history.getRecentTemplateIDs(),
            workspaces: history.getWorkspaces(),
            history: history.getHistory()
        )).first

        selectedTemplateID = suggestion?.template.id
            ?? history.getRecentTemplateIDs().first
            ?? LayoutTemplate.all.first!.id
        slotAssignments = [:]   // Always start empty — user assigns intentionally

        buildUI()
        center()
        animateIn()
        isPresented = true
        NSApp.activate(ignoringOtherApps: false)
    }

    public func dismiss() {
        guard isPresented else { return }
        isPresented = false
        animateOut { [weak self] in
            self?.window?.orderOut(nil)
            self?.cleanupUI()
        }
    }

    public func promptSaveCurrentFromMenu() {
        selectedTemplateID = history.getRecentTemplateIDs().first ?? LayoutTemplate.all.first!.id
        slotAssignments = [:]
        present(triggerWindow: nil)
    }

    public func handleKeyCode(_ code: UInt16) {
        switch code {
        case 53: dismiss()
        case 36, 76: applyLayout()
        default: break
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let panel = window else { return }

        let fx = NSVisualEffectView(frame: panel.contentView!.bounds)
        fx.material = .sidebar
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 16
        fx.layer?.masksToBounds = true
        fx.autoresizingMask = [.width, .height]
        panel.contentView = fx

        let root = NSView(frame: fx.bounds)
        root.autoresizingMask = [.width, .height]
        fx.addSubview(root)

        let sidebarW: CGFloat = 240
        let dockH: CGFloat = 92
        let bounds = root.bounds

        // Sidebar — template thumbnail cards + saved layouts
        let sidebar = LibrarySidebarView(
            frame: CGRect(x: 0, y: 0, width: sidebarW, height: bounds.height),
            savedLayouts: history.getSavedLayouts(),
            recentIDs: history.getRecentTemplateIDs(),
            selectedID: selectedTemplateID,
            onSelect: { [weak self] id in self?.selectTemplate(id) },
            onApplySaved: { [weak self] layout in self?.applySavedLayout(layout) }
        )
        sidebar.autoresizingMask = [.height]
        root.addSubview(sidebar)
        self.sidebarView = sidebar

        // Separator
        let sep = NSView(frame: CGRect(x: sidebarW, y: 0, width: 1, height: bounds.height))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        sep.autoresizingMask = [.height]
        root.addSubview(sep)

        // App dock — sole drag source
        let dock = LibraryAppDockView(
            frame: CGRect(x: sidebarW + 1, y: 0, width: bounds.width - sidebarW - 1, height: dockH),
            apps: dockApps()
        )
        dock.autoresizingMask = [.width]
        root.addSubview(dock)
        self.dockView = dock

        // Canvas — large slot grid, assignment target
        let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }) ?? LayoutTemplate.all[0]
        let canvas = LibraryCanvasView(
            frame: CGRect(x: sidebarW + 1, y: dockH,
                          width: bounds.width - sidebarW - 1,
                          height: bounds.height - dockH),
            template: template,
            assignments: slotAssignments,
            appLibrary: appLibrary,
            onDrop:  { [weak self] slotID, bid in self?.assignApp(bid, toSlot: slotID) },
            onApply: { [weak self] in self?.applyLayout() },
            onSave:  { [weak self] in self?.promptSaveLayout() }
        )
        canvas.autoresizingMask = [.width, .height]
        root.addSubview(canvas)
        self.canvasView = canvas

        // Traffic-light close button
        let close = makeCloseButton(in: fx)
        fx.addSubview(close)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyCode(event.keyCode)
            return event
        }
    }

    private func cleanupUI() {
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        sidebarView = nil; canvasView = nil; dockView = nil
    }

    private func makeCloseButton(in parent: NSView) -> NSButton {
        let btn = NSButton(frame: CGRect(x: 14, y: parent.bounds.height - 34, width: 14, height: 14))
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 7
        btn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.85).cgColor
        btn.target = self
        btn.action = #selector(closeButtonTapped)
        btn.autoresizingMask = [.minYMargin]
        return btn
    }

    @objc private func closeButtonTapped() { dismiss() }

    // MARK: - Animations

    private func animateIn() {
        guard let panel = window, let screen = NSScreen.main else { window?.orderFront(nil); return }
        let sf = screen.visibleFrame
        let pw = panel.frame
        let targetY = sf.midY - pw.height / 2
        panel.setFrameOrigin(CGPoint(x: sf.midX - pw.width / 2, y: targetY - 24))
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(CGPoint(x: sf.midX - pw.width / 2, y: targetY))
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        guard let panel = window else { completion(); return }
        let origin = panel.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(CGPoint(x: origin.x, y: origin.y - 16))
        }, completionHandler: completion)
    }

    // MARK: - Template Selection

    private func selectTemplate(_ id: String) {
        selectedTemplateID = id
        slotAssignments = [:]   // slots stay empty on template switch
        guard let template = LayoutTemplate.all.first(where: { $0.id == id }) else { return }
        canvasView?.update(template: template, assignments: slotAssignments)
        sidebarView?.setSelected(id)
    }

    // MARK: - Assignment

    private func assignApp(_ bundleID: String, toSlot slotID: Int) {
        for (k, v) in slotAssignments where v == bundleID { slotAssignments.removeValue(forKey: k) }
        slotAssignments[slotID] = bundleID
        canvasView?.update(assignments: slotAssignments)
    }

    // MARK: - Apply

    private func applyLayout() {
        guard let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }) else { return }
        let screen = orchestrator.getUsableScreenFrame(for: triggerWindow ?? AXUIElementCreateSystemWide())
        guard screen != .zero else { dismiss(); return }

        for slot in template.slots {
            guard let bundleID = slotAssignments[slot.id], let win = axWindow(forBundleID: bundleID) else { continue }
            orchestrator.animateWindowFrame(win, to: CGRect(
                x: screen.origin.x + slot.rect.origin.x * screen.width,
                y: screen.origin.y + slot.rect.origin.y * screen.height,
                width: slot.rect.width * screen.width,
                height: slot.rect.height * screen.height
            ), source: "expose")
        }

        history.recordApply(event: AppliedLayoutEvent(
            layoutTemplateID: selectedTemplateID,
            workspacePresetID: nil,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screen.width / max(screen.height, 1),
            displayCount: NSScreen.screens.count
        ))

        SpatialTransitionEngine.shared.registerExposeState(
            template: template,
            windows: orchestrator.getAllVisibleWindows(),
            screenFrame: screen
        )

        dismiss()
    }

    // MARK: - Save

    private func promptSaveLayout() {
        guard let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }),
              let w = window else { return }
        let alert = NSAlert()
        alert.messageText = "Save Layout"
        alert.informativeText = "Name this layout to add it to your library."
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = template.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: w) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            let saved = SavedLayout(name: name.isEmpty ? template.name : name,
                                    templateID: self.selectedTemplateID,
                                    slotBundleIDs: self.slotAssignments)
            self.history.saveSavedLayout(saved)
            self.sidebarView?.reload(saved: self.history.getSavedLayouts())
        }
    }

    private func applySavedLayout(_ layout: SavedLayout) {
        selectedTemplateID = layout.templateID
        slotAssignments = layout.slotBundleIDs
        guard let template = LayoutTemplate.all.first(where: { $0.id == layout.templateID }) else { return }
        canvasView?.update(template: template, assignments: slotAssignments)
        sidebarView?.setSelected(layout.templateID)
        history.touchSavedLayout(id: layout.id)
    }

    // MARK: - Helpers

    private func dockApps() -> [AppInfo] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var apps = appLibrary.allApps
        apps.sort { a, b in
            let aRun = running.contains(a.id), bRun = running.contains(b.id)
            if aRun != bRun { return aRun }
            return a.name < b.name
        }
        return apps
    }

    private func center() {
        guard let screen = NSScreen.main, let panel = window else { return }
        let sf = screen.visibleFrame, pw = panel.frame
        panel.setFrameOrigin(CGPoint(x: sf.midX - pw.width / 2, y: sf.midY - pw.height / 2))
    }

    private func axWindow(forBundleID bundleID: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return nil }
        return windows.first { win in
            var minRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
                  let isMin = minRef as? Bool else { return true }
            return !isMin
        } ?? windows.first
    }

    private func makeWindowItems(triggerWindow: AXUIElement?) -> [LayoutWindowItem] {
        var items: [LayoutWindowItem] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, "AXEnhancedUserInterface" as CFString, true as CFTypeRef)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                  let windows = ref as? [AXUIElement] else { continue }
            for win in windows {
                var minRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
                   let isMin = minRef as? Bool, isMin { continue }
                let title = orchestrator.windowTitle(for: win)
                let role = WindowRoleClassifier.classify(appName: app.localizedName, windowTitle: title)
                var isActive = false
                if let tw = triggerWindow {
                    var twPID: pid_t = 0, winPID: pid_t = 0
                    AXUIElementGetPid(tw, &twPID); AXUIElementGetPid(win, &winPID)
                    isActive = twPID == winPID
                } else {
                    isActive = app == NSWorkspace.shared.frontmostApplication
                }
                var item = LayoutWindowItem(
                    id: "\(app.processIdentifier)-\(title)",
                    element: win, title: title,
                    appName: app.localizedName, bundleID: app.bundleIdentifier,
                    appIcon: app.icon, role: role
                )
                item.isActive = isActive
                items.append(item)
            }
        }
        return items
    }
}

// MARK: - LibrarySidebarView

final class LibrarySidebarView: NSView {
    private var onSelect: (String) -> Void
    private var onApplySaved: (SavedLayout) -> Void
    private var selectedID: String
    private var savedLayouts: [SavedLayout]
    private var scrollView: NSScrollView!
    private var contentStack: NSStackView!
    private var cardViews: [LayoutThumbnailCard] = []

    init(frame: CGRect, savedLayouts: [SavedLayout], recentIDs: [String],
         selectedID: String,
         onSelect: @escaping (String) -> Void,
         onApplySaved: @escaping (SavedLayout) -> Void) {
        self.savedLayouts = savedLayouts
        self.selectedID = selectedID
        self.onSelect = onSelect
        self.onApplySaved = onApplySaved
        super.init(frame: frame)
        wantsLayer = true
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        subviews.forEach { $0.removeFromSuperview() }
        cardViews = []

        contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6
        contentStack.edgeInsets = NSEdgeInsets(top: 48, left: 14, bottom: 14, right: 14)

        // Title
        let title = NSTextField(labelWithString: "Layout Library")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        contentStack.addArrangedSubview(title)
        contentStack.setCustomSpacing(20, after: title)

        // All Layouts — thumbnail cards
        addSectionHeader("All Layouts")
        for template in LayoutTemplate.all {
            addTemplateCard(id: template.id, name: template.name, template: template, saved: nil)
        }

        // Saved Layouts
        if !savedLayouts.isEmpty {
            contentStack.setCustomSpacing(20, after: contentStack.arrangedSubviews.last ?? title)
            addSectionHeader("Saved")
            for saved in savedLayouts {
                let template = LayoutTemplate.all.first(where: { $0.id == saved.templateID })
                addTemplateCard(id: saved.templateID, name: saved.name, template: template, saved: saved)
            }
        }

        let scrollContent = contentStack
        let totalH = contentStack.arrangedSubviews.reduce(62.0 + CGFloat(contentStack.arrangedSubviews.count) * 8) { acc, v in
            acc + v.intrinsicContentSize.height
        }
        contentStack.frame = CGRect(x: 0, y: 0, width: bounds.width - 28, height: max(totalH, bounds.height))

        scrollView = NSScrollView(frame: bounds)
        scrollView.documentView = scrollContent
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
    }

    private func addSectionHeader(_ text: String) {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        contentStack.addArrangedSubview(label)
        contentStack.setCustomSpacing(6, after: label)
    }

    private func addTemplateCard(id: String, name: String, template: LayoutTemplate?, saved: SavedLayout?) {
        let card = LayoutThumbnailCard(
            templateID: id,
            name: name,
            template: template,
            isSelected: id == selectedID,
            onTap: { [weak self] in
                if let saved = saved { self?.onApplySaved(saved) } else { self?.onSelect(id) }
            }
        )
        let w = bounds.width - 28
        card.widthAnchor.constraint(equalToConstant: w).isActive = true
        contentStack.addArrangedSubview(card)
        contentStack.setCustomSpacing(4, after: card)
        cardViews.append(card)
    }

    func setSelected(_ id: String) {
        selectedID = id
        cardViews.forEach { $0.setSelected($0.templateID == id) }
    }

    func reload(saved: [SavedLayout]) {
        savedLayouts = saved
        buildContent()
    }
}

// MARK: - LayoutThumbnailCard

final class LayoutThumbnailCard: NSView {
    let templateID: String
    private let name: String
    private let template: LayoutTemplate?
    private var isSelected: Bool
    private var onTap: () -> Void
    private var isHovered = false

    init(templateID: String, name: String, template: LayoutTemplate?, isSelected: Bool, onTap: @escaping () -> Void) {
        self.templateID = templateID
        self.name = name
        self.template = template
        self.isSelected = isSelected
        self.onTap = onTap
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 80).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().layer?.backgroundColor = self.cardBackground().cgColor
        }
        needsDisplay = true
    }

    private func cardBackground() -> NSColor {
        if isSelected { return NSColor.controlAccentColor.withAlphaComponent(0.9) }
        if isHovered { return NSColor.controlAccentColor.withAlphaComponent(0.12) }
        return NSColor.quaternaryLabelColor.withAlphaComponent(0.3)
    }

    private func updateAppearance() {
        layer?.backgroundColor = cardBackground().cgColor
    }

    // Draw the template slot geometry as a thumbnail
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let template = template else {
            // Fallback label for saved-only items with no template
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor
            ]
            name.draw(in: bounds.insetBy(dx: 10, dy: 28), withAttributes: attrs)
            return
        }

        let previewRect = CGRect(x: 10, y: 24, width: bounds.width - 20, height: bounds.height - 36)
        let gap: CGFloat = 2
        let slotColor = isSelected
            ? NSColor.white.withAlphaComponent(0.25)
            : NSColor.labelColor.withAlphaComponent(0.12)
        let slotBorder = isSelected
            ? NSColor.white.withAlphaComponent(0.4)
            : NSColor.labelColor.withAlphaComponent(0.2)

        for slot in template.slots {
            let r = CGRect(
                x: previewRect.origin.x + slot.rect.origin.x * previewRect.width + gap,
                y: previewRect.origin.y + slot.rect.origin.y * previewRect.height + gap,
                width: slot.rect.width * previewRect.width - gap * 2,
                height: slot.rect.height * previewRect.height - gap * 2
            )
            let path = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
            slotColor.setFill()
            path.fill()
            slotBorder.setStroke()
            path.lineWidth = 0.75
            path.stroke()
        }

        // Name label below thumbnail
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: isSelected ? .medium : .regular),
            .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor
        ]
        name.draw(in: CGRect(x: 10, y: 6, width: bounds.width - 20, height: 16), withAttributes: labelAttrs)
    }

    override func mouseDown(with event: NSEvent) { onTap() }

    override func mouseEntered(with event: NSEvent) {
        guard !isSelected else { return }
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.backgroundColor = self.cardBackground().cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.backgroundColor = self.cardBackground().cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        ))
    }
}

// MARK: - LibraryCanvasView

final class LibraryCanvasView: NSView {
    private var template: LayoutTemplate
    private var assignments: [Int: String]
    private let appLibrary: AppLibraryStore
    private var onDrop: (Int, String) -> Void
    private var onApply: () -> Void
    private var onSave: () -> Void
    private var slotViews: [Int: LibrarySlotView] = [:]
    private var canvasArea: NSView!
    private var templateNameLabel: NSTextField!

    init(frame: CGRect, template: LayoutTemplate, assignments: [Int: String],
         appLibrary: AppLibraryStore,
         onDrop: @escaping (Int, String) -> Void,
         onApply: @escaping () -> Void,
         onSave: @escaping () -> Void) {
        self.template = template
        self.assignments = assignments
        self.appLibrary = appLibrary
        self.onDrop = onDrop
        self.onApply = onApply
        self.onSave = onSave
        super.init(frame: frame)
        wantsLayer = true
        buildCanvas()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildCanvas() {
        subviews.forEach { $0.removeFromSuperview() }
        slotViews = [:]

        // Template name
        templateNameLabel = NSTextField(labelWithString: template.name)
        templateNameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        templateNameLabel.textColor = .labelColor
        templateNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(templateNameLabel)

        // Slot hint
        let hint = NSTextField(labelWithString: "Drag apps from the shelf below into slots")
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        // Canvas area
        canvasArea = NSView()
        canvasArea.wantsLayer = true
        canvasArea.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.05).cgColor
        canvasArea.layer?.cornerRadius = 14
        canvasArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasArea)

        // Apply button
        let applyBtn = makeApplyButton()
        addSubview(applyBtn)

        let saveBtn = NSButton(title: "Save…", target: self, action: #selector(saveTapped))
        saveBtn.bezelStyle = .roundRect
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(saveBtn)

        NSLayoutConstraint.activate([
            templateNameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            templateNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),

            hint.topAnchor.constraint(equalTo: templateNameLabel.bottomAnchor, constant: 2),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),

            canvasArea.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 16),
            canvasArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            canvasArea.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            canvasArea.bottomAnchor.constraint(equalTo: applyBtn.topAnchor, constant: -16),

            applyBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            applyBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            applyBtn.widthAnchor.constraint(equalToConstant: 140),
            applyBtn.heightAnchor.constraint(equalToConstant: 34),

            saveBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -22),
            saveBtn.trailingAnchor.constraint(equalTo: applyBtn.leadingAnchor, constant: -8),
            saveBtn.heightAnchor.constraint(equalToConstant: 34),
        ])

        layoutSubtreeIfNeeded()
        buildSlots()
    }

    private func makeApplyButton() -> NSButton {
        let btn = NSButton(title: "Apply Layout", target: self, action: #selector(applyTapped))
        btn.bezelStyle = .roundRect
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        btn.layer?.cornerRadius = 8
        btn.contentTintColor = .white
        btn.font = .systemFont(ofSize: 13, weight: .medium)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    private func buildSlots() {
        let aw = canvasArea.bounds.width, ah = canvasArea.bounds.height
        guard aw > 10, ah > 10 else {
            DispatchQueue.main.async { [weak self] in self?.buildSlots() }
            return
        }
        let pad: CGFloat = 18
        let inner = CGRect(x: pad, y: pad, width: aw - pad * 2, height: ah - pad * 2)

        for slot in template.slots {
            let f = CGRect(
                x: inner.origin.x + slot.rect.origin.x * inner.width,
                y: inner.origin.y + slot.rect.origin.y * inner.height,
                width: slot.rect.width * inner.width,
                height: slot.rect.height * inner.height
            ).insetBy(dx: 5, dy: 5)

            let appInfo = assignments[slot.id].flatMap { appLibrary.app(bundleID: $0) }
            let sv = LibrarySlotView(
                frame: f, slotID: slot.id, appInfo: appInfo,
                onDrop: { [weak self] bid in self?.onDrop(slot.id, bid) }
            )
            canvasArea.addSubview(sv)
            slotViews[slot.id] = sv
        }
    }

    func update(template: LayoutTemplate? = nil, assignments: [Int: String]) {
        if let t = template { self.template = t }
        self.assignments = assignments
        buildCanvas()
    }

    @objc private func applyTapped() { onApply() }
    @objc private func saveTapped()  { onSave()  }
}

// MARK: - LibrarySlotView

final class LibrarySlotView: NSView {
    private let slotID: Int
    private var appInfo: AppInfo?
    private var onDrop: (String) -> Void
    private var isDropTarget = false

    init(frame: CGRect, slotID: Int, appInfo: AppInfo?, onDrop: @escaping (String) -> Void) {
        self.slotID = slotID
        self.appInfo = appInfo
        self.onDrop = onDrop
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1.5
        registerForDraggedTypes([kLayoutAppPasteboardType])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        subviews.forEach { $0.removeFromSuperview() }
        layer?.borderColor = isDropTarget
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.withAlphaComponent(0.6).cgColor
        layer?.backgroundColor = isDropTarget
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor

        if let app = appInfo {
            let iconSize: CGFloat = min(bounds.width, bounds.height) * 0.44
            let iconView = NSImageView(image: app.icon ?? defaultAppIcon())
            iconView.imageScaling = .scaleProportionallyUpOrDown
            iconView.frame = CGRect(x: (bounds.width - iconSize) / 2,
                                    y: (bounds.height - iconSize) / 2 + 10,
                                    width: iconSize, height: iconSize)
            addSubview(iconView)

            let label = NSTextField(labelWithString: app.name)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.frame = CGRect(x: 4, y: 8, width: bounds.width - 8, height: 14)
            addSubview(label)
        } else {
            // Empty state: large plus, no instructional text
            let plus = NSTextField(labelWithString: "+")
            plus.font = .systemFont(ofSize: 28, weight: .ultraLight)
            plus.textColor = .quaternaryLabelColor
            plus.alignment = .center
            plus.frame = CGRect(x: 0, y: (bounds.height - 36) / 2, width: bounds.width, height: 36)
            addSubview(plus)
        }
    }

    private func defaultAppIcon() -> NSImage {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: 40, height: 40))
    }

    // MARK: Drop destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.string(forType: kLayoutAppPasteboardType) != nil else { return [] }
        isDropTarget = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.borderColor = NSColor.controlAccentColor.cgColor
            self.animator().layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        }
        // Pulse scale up
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0; pulse.toValue = 1.03
        pulse.duration = 0.12; pulse.autoreverses = true; pulse.fillMode = .forwards
        layer?.add(pulse, forKey: "pulse")
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            self.animator().layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bid = sender.draggingPasteboard.string(forType: kLayoutAppPasteboardType) else { return false }
        onDrop(bid)
        springAccept()
        return true
    }

    private func springAccept() {
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 1.08; spring.toValue = 1.0
        spring.mass = 1; spring.stiffness = 280; spring.damping = 20
        spring.duration = spring.settlingDuration
        layer?.add(spring, forKey: "spring")
    }
}

// MARK: - LibraryAppDockView

final class LibraryAppDockView: NSView {
    private var apps: [AppInfo]
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var searchField: NSSearchField!

    init(frame: CGRect, apps: [AppInfo]) {
        self.apps = apps
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.035).cgColor
        buildDock()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildDock() {
        subviews.forEach { $0.removeFromSuperview() }

        let sep = NSView(frame: CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        sep.autoresizingMask = [.width, .minYMargin]
        addSubview(sep)

        searchField = NSSearchField(frame: CGRect(x: bounds.width - 186, y: (bounds.height - 24) / 2, width: 166, height: 24))
        searchField.placeholderString = "Search apps…"
        searchField.font = .systemFont(ofSize: 11)
        searchField.autoresizingMask = [.minXMargin]
        searchField.target = self
        searchField.action = #selector(searchChanged)
        addSubview(searchField)

        let scrollW = bounds.width - 206
        scrollView = NSScrollView(frame: CGRect(x: 4, y: 2, width: scrollW, height: bounds.height - 4))
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width]

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 6
        stackView.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stackView.alignment = .centerY

        buildItems(apps.prefix(80))

        scrollView.documentView = stackView
        addSubview(scrollView)
    }

    private func buildItems(_ source: any Collection<AppInfo>) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = Array(source)
        for app in items {
            stackView.addArrangedSubview(LibraryAppItemView(app: app))
        }
        let totalW = CGFloat(items.count) * 62 + 16
        stackView.frame = CGRect(x: 0, y: 0, width: max(totalW, scrollView.bounds.width), height: bounds.height - 4)
    }

    @objc private func searchChanged() {
        let q = searchField.stringValue
        let filtered = q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
        buildItems(filtered.prefix(80))
    }
}

// MARK: - LibraryAppItemView

final class LibraryAppItemView: NSView, NSDraggingSource {
    private let app: AppInfo
    private var isHighlighted = false

    init(app: AppInfo) {
        self.app = app
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 58).isActive = true
        heightAnchor.constraint(equalToConstant: 80).isActive = true
        buildView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildView() {
        let iconSize: CGFloat = 38
        let iconView = NSImageView(frame: CGRect(x: (58 - iconSize) / 2, y: 24, width: iconSize, height: iconSize))
        iconView.image = app.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        let label = NSTextField(labelWithString: app.name)
        label.font = .systemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = CGRect(x: 2, y: 5, width: 54, height: 14)
        addSubview(label)
    }

    override func mouseDown(with event: NSEvent) {
        isHighlighted = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.animator().layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard event.deltaX * event.deltaX + event.deltaY * event.deltaY > 4 else { return }
        isHighlighted = false
        layer?.backgroundColor = nil

        let icon = app.icon ?? NSImage(size: NSSize(width: 38, height: 38))
        let dragImg = NSImage(size: NSSize(width: 40, height: 40))
        dragImg.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: NSSize(width: 40, height: 40)))
        dragImg.unlockFocus()

        let pb = NSPasteboardItem()
        pb.setString(app.id, forType: kLayoutAppPasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pb)
        item.setDraggingFrame(CGRect(x: 9, y: 20, width: 40, height: 40), contents: dragImg)

        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isHighlighted else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard !isHighlighted else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil
        ))
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}
