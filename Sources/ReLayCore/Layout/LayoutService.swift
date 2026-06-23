import AppKit
import ApplicationServices

// MARK: - Pasteboard Type

private let kLayoutAppPasteboardType = NSPasteboard.PasteboardType("com.relay.layoutapp")

// MARK: - LayoutService

public final class LayoutService: NSWindowController {
    public static let shared = LayoutService()

    private let history    = LayoutHistoryStore.shared
    private let appLibrary = AppLibraryStore.shared

    public private(set) var isPresented: Bool = false

    private var selectedTemplateID: String = LayoutTemplate.all.first?.id ?? "split"
    private var slotAssignments: [Int: String] = [:]
    private var triggerWindow: AXUIElement?
    private var currentWindows: [LayoutWindowItem] = []

    private var templateStrip: LayoutTemplateStrip?
    private var canvasView: LibraryCanvasView?
    private var dockView: LibraryAppDockView?

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
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

        // Spatial suggestion — picks best template, slots stay empty
        let screen = screenForWindow(triggerWindow)
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
        slotAssignments = [:]

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

    /// Returns (templateID, displayName) pairs for the most recent layouts.
    /// Used by the menu bar to populate dynamic items without exposing LayoutTemplate.
    public func recentMenuItems(max: Int = 4) -> [(id: String, name: String)] {
        history.getRecentTemplateIDs().prefix(max).compactMap { id in
            guard let name = LayoutTemplate.all.first(where: { $0.id == id })?.name else { return nil }
            return (id, name)
        }
    }

    /// Instantly tiles visible windows into the named template. Bypasses the Library UI.
    public func quickApply(templateID: String, triggerWindow: AXUIElement?) {
        guard let template = templateByID(templateID) else { return }
        let screen = screenForWindow(triggerWindow)
        guard screen != .zero else { return }

        let windows = AXWindowOps.allVisible()
        applyFrames(template: template, windows: windows, screen: screen)

        history.recordApply(event: AppliedLayoutEvent(
            layoutTemplateID: templateID,
            workspacePresetID: nil,
            visibleWindowRoles: [],
            visibleAppBundleIDs: [],
            screenAspectRatio: screen.width / max(screen.height, 1),
            displayCount: NSScreen.screens.count
        ))
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
    //
    // Layout (top → bottom):
    //   [Template strip  112pt] ← hero: large horizontal card row
    //   [Canvas          flex ] ← slot assignment area
    //   [App dock         92pt] ← sole drag source

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

        let stripH: CGFloat = 114
        let dockH:  CGFloat = 92
        let w = root.bounds.width
        let h = root.bounds.height

        // Template strip — top hero row
        let strip = LayoutTemplateStrip(
            frame: CGRect(x: 0, y: h - stripH, width: w, height: stripH),
            templates: LayoutTemplate.all,
            savedLayouts: history.getSavedLayouts(),
            selectedID: selectedTemplateID,
            onSelect: { [weak self] id in self?.selectTemplate(id) },
            onApplySaved: { [weak self] layout in self?.applySavedLayout(layout) }
        )
        strip.autoresizingMask = [.width, .minYMargin]
        root.addSubview(strip)
        self.templateStrip = strip

        // Separator below strip
        let sep = NSView(frame: CGRect(x: 0, y: h - stripH - 1, width: w, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        sep.autoresizingMask = [.width, .minYMargin]
        root.addSubview(sep)

        // App dock — bottom
        let dock = LibraryAppDockView(
            frame: CGRect(x: 0, y: 0, width: w, height: dockH),
            apps: dockApps()
        )
        dock.autoresizingMask = [.width]
        root.addSubview(dock)
        self.dockView = dock

        // Canvas — middle, fills remaining space
        let template = templateByID(selectedTemplateID) ?? LayoutTemplate.all[0]
        let canvasY = dockH
        let canvasH = h - stripH - 1 - dockH
        let canvas = LibraryCanvasView(
            frame: CGRect(x: 0, y: canvasY, width: w, height: canvasH),
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

        // Close button
        fx.addSubview(makeCloseButton(in: fx))

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyCode(event.keyCode)
            return event
        }
    }

    private func cleanupUI() {
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        templateStrip = nil; canvasView = nil; dockView = nil
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
        let targetOrigin = CGPoint(x: sf.midX - pw.width / 2, y: sf.midY - pw.height / 2)
        panel.setFrameOrigin(CGPoint(x: targetOrigin.x, y: targetOrigin.y - 20))
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94)
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(targetOrigin)
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        guard let panel = window else { completion(); return }
        let origin = panel.frame.origin
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrameOrigin(CGPoint(x: origin.x, y: origin.y - 14))
        }, completionHandler: completion)
    }

    // MARK: - Template Selection

    private func selectTemplate(_ id: String) {
        selectedTemplateID = id
        slotAssignments = [:]
        guard let template = templateByID(id) else { return }
        canvasView?.switchTemplate(template)
        templateStrip?.setSelected(id)
    }

    // MARK: - Slot Assignment

    private func assignApp(_ bundleID: String, toSlot slotID: Int) {
        // Remove from any existing slot first
        for (k, v) in slotAssignments where v == bundleID { slotAssignments.removeValue(forKey: k) }
        slotAssignments[slotID] = bundleID
        // Update in-place so the spring animation plays on the live slot view
        let appInfo = appLibrary.app(bundleID: bundleID)
        canvasView?.dropApp(appInfo, intoSlot: slotID)
    }

    // MARK: - Apply

    private func applyLayout() {
        guard let template = templateByID(selectedTemplateID) else { return }
        let screen = screenForWindow(triggerWindow)
        guard screen != .zero else { dismiss(); return }

        for slot in template.slots {
            guard let bundleID = slotAssignments[slot.id], let win = axWindow(forBundleID: bundleID) else { continue }
            AXWindowOps.setFrame(win, frameForSlot(slot, in: screen))
        }

        history.recordApply(event: AppliedLayoutEvent(
            layoutTemplateID: selectedTemplateID,
            workspacePresetID: nil,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screen.width / max(screen.height, 1),
            displayCount: NSScreen.screens.count
        ))

        Logger.log("layout applied template=\(template.id) windows=\(AXWindowOps.allVisible().count)", subsystem: "layout")

        dismiss()
    }

    // MARK: - Save

    private func promptSaveLayout() {
        guard let template = templateByID(selectedTemplateID),
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
            self.history.saveSavedLayout(SavedLayout(
                name: name.isEmpty ? template.name : name,
                templateID: self.selectedTemplateID,
                slotBundleIDs: self.slotAssignments
            ))
            self.templateStrip?.reloadSaved(self.history.getSavedLayouts())
        }
    }

    private func applySavedLayout(_ layout: SavedLayout) {
        selectedTemplateID = layout.templateID
        slotAssignments = layout.slotBundleIDs
        guard let template = templateByID(layout.templateID) else { return }
        canvasView?.switchTemplate(template, assignments: slotAssignments)
        templateStrip?.setSelected(layout.templateID)
        history.touchSavedLayout(id: layout.id)
    }

    // MARK: - Helpers

    private func dockApps() -> [AppInfo] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var apps = appLibrary.allApps
        apps.sort { a, b in
            let ar = running.contains(a.id), br = running.contains(b.id)
            if ar != br { return ar }
            return a.name < b.name
        }
        return apps
    }

    private func center() {
        guard let screen = NSScreen.main, let panel = window else { return }
        let sf = screen.visibleFrame, pw = panel.frame
        panel.setFrameOrigin(CGPoint(x: sf.midX - pw.width / 2, y: sf.midY - pw.height / 2))
    }

    private func axWindow(forBundleID id: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement] else { return nil }
        return windows.first { win in
            var v: CFTypeRef?
            return !(AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &v) == .success && (v as? Bool) == true)
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
                var mv: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &mv) == .success,
                   (mv as? Bool) == true { continue }
                let title = AXWindowOps.title(win)
                let role  = WindowRoleClassifier.classify(appName: app.localizedName, windowTitle: title)
                var isActive = false
                if let tw = triggerWindow {
                    var twPID: pid_t = 0, wPID: pid_t = 0
                    AXUIElementGetPid(tw, &twPID); AXUIElementGetPid(win, &wPID)
                    isActive = twPID == wPID
                } else { isActive = app == NSWorkspace.shared.frontmostApplication }
                var item = LayoutWindowItem(
                    id: "\(app.processIdentifier)-\(title)", element: win, title: title,
                    appName: app.localizedName, bundleID: app.bundleIdentifier,
                    appIcon: app.icon, role: role
                )
                item.isActive = isActive
                items.append(item)
            }
        }
        return items
    }

    private func templateByID(_ id: String) -> LayoutTemplate? {
        LayoutTemplate.all.first(where: { $0.id == id })
    }

    private func screenForWindow(_ window: AXUIElement?) -> CGRect {
        WindowRuntime.usableScreen(containing: window.flatMap { AXWindowOps.frame($0) } ?? .zero)
    }

    private func frameForSlot(_ slot: LayoutTemplate.Slot, in screen: CGRect) -> CGRect {
        CGRect(
            x: screen.origin.x + slot.rect.origin.x * screen.width,
            y: screen.origin.y + slot.rect.origin.y * screen.height,
            width: slot.rect.width * screen.width,
            height: slot.rect.height * screen.height
        )
    }

    private func applyFrames(template: LayoutTemplate, windows: [AXUIElement], screen: CGRect) {
        for (i, slot) in template.slots.enumerated() where i < windows.count {
            AXWindowOps.setFrame(windows[i], frameForSlot(slot, in: screen))
        }
    }

}

// MARK: - LayoutTemplateStrip

final class LayoutTemplateStrip: NSView {
    private var onSelect: (String) -> Void
    private var onApplySaved: (SavedLayout) -> Void
    private var selectedID: String
    private var templates: [LayoutTemplate]
    private var savedLayouts: [SavedLayout]
    private var cardViews: [LayoutTemplateCard] = []
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!

    init(frame: CGRect,
         templates: [LayoutTemplate],
         savedLayouts: [SavedLayout],
         selectedID: String,
         onSelect: @escaping (String) -> Void,
         onApplySaved: @escaping (SavedLayout) -> Void) {
        self.templates    = templates
        self.savedLayouts = savedLayouts
        self.selectedID   = selectedID
        self.onSelect     = onSelect
        self.onApplySaved = onApplySaved
        super.init(frame: frame)
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        subviews.forEach { $0.removeFromSuperview() }
        cardViews = []

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        stackView.alignment = .centerY

        // Template cards
        for template in templates {
            addCard(templateID: template.id, name: template.name, template: template, saved: nil)
        }

        // Saved layouts — separated by a thin rule
        if !savedLayouts.isEmpty {
            let rule = NSView()
            rule.wantsLayer = true
            rule.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
            rule.widthAnchor.constraint(equalToConstant: 1).isActive = true
            rule.heightAnchor.constraint(equalToConstant: 60).isActive = true
            stackView.addArrangedSubview(rule)

            for saved in savedLayouts {
                let template = LayoutTemplate.all.first(where: { $0.id == saved.templateID })
                addCard(templateID: saved.templateID, name: saved.name, template: template, saved: saved)
            }
        }

        let totalW = CGFloat(cardViews.count) * (148 + 8) + 32 + CGFloat(savedLayouts.isEmpty ? 0 : 17)
        stackView.frame = CGRect(x: 0, y: 0, width: max(totalW, bounds.width), height: bounds.height)

        scrollView = NSScrollView(frame: bounds)
        scrollView.documentView = stackView
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller   = false
        scrollView.drawsBackground       = false
        scrollView.autoresizingMask      = [.width, .height]
        addSubview(scrollView)
    }

    private func addCard(templateID: String, name: String, template: LayoutTemplate?, saved: SavedLayout?) {
        let card = LayoutTemplateCard(
            templateID: templateID,
            name: name,
            template: template,
            isSaved: saved != nil,
            isSelected: templateID == selectedID,
            onTap: { [weak self] in
                if let saved { self?.onApplySaved(saved) } else { self?.onSelect(templateID) }
            }
        )
        stackView.addArrangedSubview(card)
        cardViews.append(card)
    }

    func setSelected(_ id: String) {
        selectedID = id
        for card in cardViews { card.setSelected(card.templateID == id) }
    }

    func reloadSaved(_ saved: [SavedLayout]) {
        savedLayouts = saved
        build()
    }
}

// MARK: - LayoutTemplateCard

final class LayoutTemplateCard: NSView {
    let templateID: String
    private let name: String
    private let template: LayoutTemplate?
    private let isSaved: Bool
    private var isSelected: Bool
    private var isHovered = false
    private var onTap: () -> Void

    init(templateID: String, name: String, template: LayoutTemplate?,
         isSaved: Bool, isSelected: Bool, onTap: @escaping () -> Void) {
        self.templateID = templateID
        self.name       = name
        self.template   = template
        self.isSaved    = isSaved
        self.isSelected = isSelected
        self.onTap      = onTap
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 148).isActive = true
        heightAnchor.constraint(equalToConstant: 90).isActive = true
        refreshBackground()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        guard isSelected != selected else { return }
        isSelected = selected
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().layer?.backgroundColor = self.cardBG().cgColor
        }
        needsDisplay = true
    }

    private func cardBG() -> NSColor {
        if isSelected { return .controlAccentColor }
        if isHovered  { return NSColor.controlAccentColor.withAlphaComponent(0.14) }
        return NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
    }

    private func refreshBackground() {
        layer?.backgroundColor = cardBG().cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let previewRect = CGRect(x: 10, y: 22, width: bounds.width - 20, height: bounds.height - 38)
        let gap: CGFloat = 2.5

        let slotFill   = isSelected ? NSColor.white.withAlphaComponent(0.28) : NSColor.labelColor.withAlphaComponent(0.13)
        let slotStroke = isSelected ? NSColor.white.withAlphaComponent(0.45) : NSColor.labelColor.withAlphaComponent(0.22)

        if let template {
            for slot in template.slots {
                let r = CGRect(
                    x:      previewRect.minX + slot.rect.minX * previewRect.width  + gap,
                    y:      previewRect.minY + slot.rect.minY * previewRect.height + gap,
                    width:  slot.rect.width  * previewRect.width  - gap * 2,
                    height: slot.rect.height * previewRect.height - gap * 2
                )
                let path = NSBezierPath(roundedRect: r, xRadius: 3.5, yRadius: 3.5)
                slotFill.setFill();   path.fill()
                slotStroke.setStroke(); path.lineWidth = 0.75; path.stroke()
            }
        }

        let color: NSColor = isSelected ? .white : .labelColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: isSelected ? .medium : .regular),
            .foregroundColor: color
        ]
        name.draw(in: CGRect(x: 10, y: 6, width: bounds.width - 20, height: 16), withAttributes: attrs)

        if isSaved {
            let badgeColor = isSelected ? NSColor.white.withAlphaComponent(0.7) : NSColor.controlAccentColor
            let img = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil)!
            img.size = NSSize(width: 9, height: 11)
            let tinted = img.copy() as! NSImage
            tinted.lockFocus()
            badgeColor.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: CGRect(x: bounds.width - 16, y: bounds.height - 16, width: 9, height: 11))
        }
    }

    override func mouseDown(with event: NSEvent) { onTap() }

    override func mouseEntered(with event: NSEvent) {
        guard !isSelected else { return }
        isHovered = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = self.cardBG().cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        guard !isSelected else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = self.cardBG().cgColor
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

    init(frame: CGRect, template: LayoutTemplate, assignments: [Int: String],
         appLibrary: AppLibraryStore,
         onDrop:  @escaping (Int, String) -> Void,
         onApply: @escaping () -> Void,
         onSave:  @escaping () -> Void) {
        self.template    = template
        self.assignments = assignments
        self.appLibrary  = appLibrary
        self.onDrop      = onDrop
        self.onApply     = onApply
        self.onSave      = onSave
        super.init(frame: frame)
        wantsLayer = true
        buildCanvas()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildCanvas() {
        subviews.forEach { $0.removeFromSuperview() }
        slotViews = [:]

        let nameLabel = NSTextField(labelWithString: template.name)
        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let hint = NSTextField(labelWithString: "Drag apps from the shelf below into slots")
        hint.font = .systemFont(ofSize: 11.5)
        hint.textColor = .tertiaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        canvasArea = NSView()
        canvasArea.wantsLayer = true
        canvasArea.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.05).cgColor
        canvasArea.layer?.cornerRadius = 14
        canvasArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasArea)

        let applyBtn = makeApplyButton()
        addSubview(applyBtn)
        let saveBtn = NSButton(title: "Save…", target: self, action: #selector(saveTapped))
        saveBtn.bezelStyle = .roundRect
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(saveBtn)

        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 22),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),

            hint.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),

            canvasArea.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 14),
            canvasArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            canvasArea.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            canvasArea.bottomAnchor.constraint(equalTo: applyBtn.topAnchor, constant: -14),

            applyBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            applyBtn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            applyBtn.widthAnchor.constraint(equalToConstant: 140),
            applyBtn.heightAnchor.constraint(equalToConstant: 34),

            saveBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
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
        slotViews.values.forEach { $0.removeFromSuperview() }
        slotViews = [:]
        let aw = canvasArea.bounds.width, ah = canvasArea.bounds.height
        guard aw > 10, ah > 10 else {
            DispatchQueue.main.async { [weak self] in self?.buildSlots() }
            return
        }
        let pad: CGFloat = 16
        let inner = CGRect(x: pad, y: pad, width: aw - pad * 2, height: ah - pad * 2)
        for slot in template.slots {
            let f = CGRect(
                x: inner.minX + slot.rect.minX * inner.width,
                y: inner.minY + slot.rect.minY * inner.height,
                width: slot.rect.width * inner.width,
                height: slot.rect.height * inner.height
            ).insetBy(dx: 5, dy: 5)
            let appInfo = assignments[slot.id].flatMap { appLibrary.app(bundleID: $0) }
            let sv = LibrarySlotView(frame: f, slotID: slot.id, appInfo: appInfo) { [weak self] bid in
                self?.onDrop(slot.id, bid)
            }
            canvasArea.addSubview(sv)
            slotViews[slot.id] = sv
        }
    }

    func switchTemplate(_ template: LayoutTemplate, assignments: [Int: String] = [:]) {
        self.template = template
        self.assignments = assignments
        buildCanvas()
    }

    func dropApp(_ appInfo: AppInfo?, intoSlot slotID: Int) {
        guard let sv = slotViews[slotID] else { return }
        sv.assignApp(appInfo)
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
        self.slotID  = slotID
        self.appInfo = appInfo
        self.onDrop  = onDrop
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth  = 1.5
        registerForDraggedTypes([kLayoutAppPasteboardType])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    func assignApp(_ info: AppInfo?) {
        appInfo = info
        refresh()
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue   = 1.08
        spring.toValue     = 1.0
        spring.mass        = 1
        spring.stiffness   = 280
        spring.damping     = 20
        spring.duration    = spring.settlingDuration
        layer?.add(spring, forKey: "spring")
    }

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
            let iv = NSImageView(image: app.icon ?? fallbackIcon())
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.frame = CGRect(x: (bounds.width - iconSize) / 2,
                              y: (bounds.height - iconSize) / 2 + 10,
                              width: iconSize, height: iconSize)
            addSubview(iv)

            let label = NSTextField(labelWithString: app.name)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.frame = CGRect(x: 4, y: 8, width: bounds.width - 8, height: 14)
            addSubview(label)
        } else {
            let plus = NSTextField(labelWithString: "+")
            plus.font = .systemFont(ofSize: 26, weight: .ultraLight)
            plus.textColor = .quaternaryLabelColor
            plus.alignment = .center
            plus.frame = CGRect(x: 0, y: (bounds.height - 34) / 2, width: bounds.width, height: 34)
            addSubview(plus)
        }
    }

    private func fallbackIcon() -> NSImage {
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 40, height: 40))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.string(forType: kLayoutAppPasteboardType) != nil else { return [] }
        isDropTarget = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.borderColor     = NSColor.controlAccentColor.cgColor
            self.animator().layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0; pulse.toValue = 1.04
        pulse.duration  = 0.1; pulse.autoreverses = true
        layer?.add(pulse, forKey: "pulse")
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.borderColor     = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            self.animator().layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.borderColor     = NSColor.separatorColor.withAlphaComponent(0.6).cgColor
            self.animator().layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bid = sender.draggingPasteboard.string(forType: kLayoutAppPasteboardType) else { return false }
        onDrop(bid)
        return true
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

        scrollView = NSScrollView(frame: CGRect(x: 4, y: 2, width: bounds.width - 206, height: bounds.height - 4))
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller   = false
        scrollView.drawsBackground       = false
        scrollView.autoresizingMask      = [.width]

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing     = 6
        stackView.edgeInsets  = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        stackView.alignment   = .centerY

        rebuildItems(apps.prefix(80))
        scrollView.documentView = stackView
        addSubview(scrollView)
    }

    private func rebuildItems(_ source: any Collection<AppInfo>) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let items = Array(source)
        for app in items { stackView.addArrangedSubview(LibraryAppItemView(app: app)) }
        let w = max(CGFloat(items.count) * 64, scrollView.bounds.width)
        stackView.frame = CGRect(x: 0, y: 0, width: w, height: bounds.height - 4)
    }

    @objc private func searchChanged() {
        let q = searchField.stringValue
        let filtered = q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
        rebuildItems(filtered.prefix(80))
    }
}

// MARK: - LibraryAppItemView

final class LibraryAppItemView: NSView, NSDraggingSource {
    private let app: AppInfo
    private var mouseDownPoint: NSPoint = .zero
    private var dragging = false

    init(app: AppInfo) {
        self.app = app
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 58).isActive = true
        heightAnchor.constraint(equalToConstant: bounds.height > 0 ? bounds.height : 80).isActive = true
        buildView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildView() {
        let iconSize: CGFloat = 38
        let iv = NSImageView(frame: CGRect(x: (58 - iconSize) / 2, y: 24, width: iconSize, height: iconSize))
        iv.image = app.icon
        iv.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iv)
        let label = NSTextField(labelWithString: app.name)
        label.font = .systemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = CGRect(x: 2, y: 5, width: 54, height: 14)
        addSubview(label)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        dragging = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.animator().layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging else { return }
        let loc = event.locationInWindow
        let dx = loc.x - mouseDownPoint.x
        let dy = loc.y - mouseDownPoint.y
        guard dx * dx + dy * dy > 16 else { return }
        dragging = true
        layer?.backgroundColor = nil

        let icon = app.icon ?? NSImage(size: NSSize(width: 38, height: 38))
        let dragImg = NSImage(size: NSSize(width: 40, height: 40))
        dragImg.lockFocus()
        icon.draw(in: NSRect(origin: .zero, size: dragImg.size))
        dragImg.unlockFocus()

        let pb = NSPasteboardItem()
        pb.setString(app.id, forType: kLayoutAppPasteboardType)
        let item = NSDraggingItem(pasteboardWriter: pb)
        item.setDraggingFrame(CGRect(x: 9, y: 20, width: 40, height: 40), contents: dragImg)

        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !dragging else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        guard !dragging else { return }
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

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}
