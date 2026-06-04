import AppKit
import ApplicationServices

// MARK: - Pasteboard Type

private let kLayoutAppPasteboardType = NSPasteboard.PasteboardType("com.relay.layoutapp")

// MARK: - LayoutLibraryController

/// Single source of truth for layout management UI.
/// Replaces LayoutExposeController. Invoked from menu bar, gesture engine, and title bar interceptor.
public final class LayoutLibraryController: NSWindowController {
    public static let shared = LayoutLibraryController()

    private let orchestrator = LayoutOrchestrator.shared
    private let history = LayoutHistoryStore.shared
    private let appLibrary = AppLibraryStore.shared

    public private(set) var isPresented: Bool = false

    // Current editing state
    private var selectedTemplateID: String = LayoutTemplate.all.first?.id ?? "split"
    private var slotAssignments: [Int: String] = [:]   // slotID → bundleID
    private var triggerWindow: AXUIElement?
    private var currentWindows: [LayoutWindowItem] = []

    // Subviews
    private var sidebarView: LibrarySidebarView?
    private var canvasView: LibraryCanvasView?
    private var dockView: LibraryAppDockView?
    private var searchField: NSSearchField?

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

        // Spatial suggestion: rank templates by current context
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

        selectedTemplateID = suggestion?.template.id ?? history.getRecentTemplateIDs().first ?? LayoutTemplate.all.first!.id
        slotAssignments = [:]

        // Auto-seed slots from running apps
        if let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }) {
            autoSeedSlots(template: template)
        }

        buildUI()
        center()
        showWindow(nil)
        isPresented = true

        NSApp.activate(ignoringOtherApps: false)
    }

    public func dismiss() {
        guard isPresented else { return }
        isPresented = false
        window?.orderOut(nil)
        cleanupUI()
    }

    public func promptSaveCurrentFromMenu() {
        let recent = history.getRecentTemplateIDs().first ?? LayoutTemplate.all.first!.id
        selectedTemplateID = recent
        slotAssignments = [:]
        present(triggerWindow: nil)
    }

    public func handleKeyCode(_ code: UInt16) {
        switch code {
        case 53: dismiss()  // Escape
        case 36, 76: applyLayout()  // Return / Enter
        default: break
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let panel = window else { return }

        let fx = NSVisualEffectView(frame: panel.contentView!.bounds)
        fx.material = .menu
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 14
        fx.layer?.masksToBounds = true
        fx.autoresizingMask = [.width, .height]
        panel.contentView = fx

        let root = NSView(frame: fx.bounds)
        root.autoresizingMask = [.width, .height]
        fx.addSubview(root)

        // Layout: sidebar (220) | canvas (flex) | dock (80h at bottom)
        let sidebarW: CGFloat = 220
        let dockH: CGFloat = 88
        let bounds = root.bounds

        // Sidebar
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
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.autoresizingMask = [.height]
        root.addSubview(sep)

        // App dock
        let dock = LibraryAppDockView(
            frame: CGRect(x: sidebarW + 1, y: 0, width: bounds.width - sidebarW - 1, height: dockH),
            apps: dockApps(),
            searchQuery: ""
        )
        dock.autoresizingMask = [.width]
        root.addSubview(dock)
        self.dockView = dock

        // Canvas
        let canvasFrame = CGRect(
            x: sidebarW + 1,
            y: dockH,
            width: bounds.width - sidebarW - 1,
            height: bounds.height - dockH
        )
        let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }) ?? LayoutTemplate.all[0]
        let canvas = LibraryCanvasView(
            frame: canvasFrame,
            template: template,
            assignments: slotAssignments,
            appLibrary: appLibrary,
            onDrop: { [weak self] slotID, bundleID in self?.assignApp(bundleID, toSlot: slotID) },
            onApply: { [weak self] in self?.applyLayout() },
            onSave: { [weak self] in self?.promptSaveLayout() }
        )
        canvas.autoresizingMask = [.width, .height]
        root.addSubview(canvas)
        self.canvasView = canvas

        // Close button
        let close = makeCloseButton(in: fx)
        fx.addSubview(close)

        // Keyboard
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyCode(event.keyCode)
            return event
        }
    }

    private func cleanupUI() {
        window?.contentView?.subviews.forEach { $0.removeFromSuperview() }
        sidebarView = nil
        canvasView = nil
        dockView = nil
    }

    private func makeCloseButton(in parent: NSView) -> NSButton {
        let btn = NSButton(frame: CGRect(x: 14, y: parent.bounds.height - 34, width: 14, height: 14))
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 7
        btn.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.8).cgColor
        btn.target = self
        btn.action = #selector(closeButtonTapped)
        btn.autoresizingMask = [.minYMargin]
        btn.toolTip = "Close"
        return btn
    }

    @objc private func closeButtonTapped() { dismiss() }

    // MARK: - Template Selection

    private func selectTemplate(_ id: String) {
        selectedTemplateID = id
        slotAssignments = [:]
        guard let template = LayoutTemplate.all.first(where: { $0.id == id }) else { return }
        autoSeedSlots(template: template)
        canvasView?.update(template: template, assignments: slotAssignments)
        sidebarView?.setSelected(id)
    }

    private func autoSeedSlots(template: LayoutTemplate) {
        var usedBundleIDs = Set(slotAssignments.values)
        for slot in template.slots {
            guard slotAssignments[slot.id] == nil else { continue }
            let preferred = slot.preferredRoles
            guard !preferred.isEmpty else { continue }
            for role in preferred {
                if let win = currentWindows.first(where: { $0.role == role && !usedBundleIDs.contains($0.bundleID ?? "") }),
                   let bid = win.bundleID {
                    slotAssignments[slot.id] = bid
                    usedBundleIDs.insert(bid)
                    break
                }
            }
        }
    }

    // MARK: - Slot Assignment

    private func assignApp(_ bundleID: String, toSlot slotID: Int) {
        // Remove the app from any other slot first
        for (k, v) in slotAssignments where v == bundleID { slotAssignments.removeValue(forKey: k) }
        slotAssignments[slotID] = bundleID
        canvasView?.update(assignments: slotAssignments)
    }

    // MARK: - Apply Layout

    private func applyLayout() {
        guard let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }) else { return }
        let screen = orchestrator.getUsableScreenFrame(
            for: triggerWindow ?? AXUIElementCreateSystemWide()
        )
        guard screen != .zero else { dismiss(); return }

        // Map slots → AX windows
        for slot in template.slots {
            guard let bundleID = slotAssignments[slot.id] else { continue }
            let targetFrame = CGRect(
                x: screen.origin.x + slot.rect.origin.x * screen.width,
                y: screen.origin.y + slot.rect.origin.y * screen.height,
                width: slot.rect.width * screen.width,
                height: slot.rect.height * screen.height
            )
            // Find AX window for this bundle
            if let win = axWindow(forBundleID: bundleID) {
                orchestrator.animateWindowFrame(win, to: targetFrame, source: "expose")
            }
        }

        // Also tile any unassigned visible windows that were assigned by gesture
        let assignedBundleIDs = Set(slotAssignments.values)
        let unassigned = currentWindows.filter { w in
            guard let bid = w.bundleID else { return false }
            return !assignedBundleIDs.contains(bid)
        }
        if !unassigned.isEmpty {
            let unassignedWindows = unassigned.compactMap { axWindow(forBundleID: $0.bundleID ?? "") }
            // Place remaining windows in any empty template slots
            let emptySlots = template.slots.filter { slotAssignments[$0.id] == nil }
            for (i, win) in unassignedWindows.enumerated() {
                if i < emptySlots.count {
                    let slot = emptySlots[i]
                    let targetFrame = CGRect(
                        x: screen.origin.x + slot.rect.origin.x * screen.width,
                        y: screen.origin.y + slot.rect.origin.y * screen.height,
                        width: slot.rect.width * screen.width,
                        height: slot.rect.height * screen.height
                    )
                    orchestrator.animateWindowFrame(win, to: targetFrame, source: "expose")
                }
            }
        }

        // Record to history
        let event = AppliedLayoutEvent(
            layoutTemplateID: selectedTemplateID,
            workspacePresetID: nil,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screen.width / max(screen.height, 1),
            displayCount: NSScreen.screens.count
        )
        history.recordApply(event: event)

        // Register undo state
        let allWindows = orchestrator.getAllVisibleWindows()
        SpatialTransitionEngine.shared.registerExposeState(
            template: template,
            windows: allWindows,
            screenFrame: screen
        )

        dismiss()
    }

    // MARK: - Save Layout

    private func promptSaveLayout() {
        guard let template = LayoutTemplate.all.first(where: { $0.id == selectedTemplateID }) else { return }
        let alert = NSAlert()
        alert.messageText = "Save Layout"
        alert.informativeText = "Give this layout a name to save it to your library."
        let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 260, height: 22))
        field.placeholderString = template.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        if let w = window { alert.beginSheetModal(for: w) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            let saved = SavedLayout(
                name: name.isEmpty ? template.name : name,
                templateID: self.selectedTemplateID,
                slotBundleIDs: self.slotAssignments
            )
            self.history.saveSavedLayout(saved)
            self.sidebarView?.reload(saved: self.history.getSavedLayouts())
        }}
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
        var apps = appLibrary.allApps
        // Surface running apps first
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        apps.sort { a, b in
            let aRun = running.contains(a.id)
            let bRun = running.contains(b.id)
            if aRun != bRun { return aRun }
            return a.name < b.name
        }
        return apps
    }

    private func center() {
        guard let screen = NSScreen.main, let panel = window else { return }
        let sf = screen.visibleFrame
        let pw = panel.frame
        panel.setFrameOrigin(CGPoint(
            x: sf.midX - pw.width / 2,
            y: sf.midY - pw.height / 2
        ))
    }

    private func axWindow(forBundleID bundleID: String) -> AXUIElement? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement], !windows.isEmpty else { return nil }
        return windows.first(where: { win in
            var minRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
               let isMin = minRef as? Bool, isMin { return false }
            return true
        }) ?? windows.first
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
                let isActive: Bool
                if let tw = triggerWindow {
                    var twPID: pid_t = 0
                    var winPID: pid_t = 0
                    AXUIElementGetPid(tw, &twPID)
                    AXUIElementGetPid(win, &winPID)
                    isActive = (twPID == winPID)
                } else {
                    isActive = (app == NSWorkspace.shared.frontmostApplication)
                }
                var item = LayoutWindowItem(
                    id: "\(app.processIdentifier)-\(title)",
                    element: win,
                    title: title,
                    appName: app.localizedName,
                    bundleID: app.bundleIdentifier,
                    appIcon: app.icon,
                    role: role
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
    private var recentIDs: [String]
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!

    init(frame: CGRect,
         savedLayouts: [SavedLayout],
         recentIDs: [String],
         selectedID: String,
         onSelect: @escaping (String) -> Void,
         onApplySaved: @escaping (SavedLayout) -> Void) {
        self.savedLayouts = savedLayouts
        self.recentIDs = recentIDs
        self.selectedID = selectedID
        self.onSelect = onSelect
        self.onApplySaved = onApplySaved
        super.init(frame: frame)
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        wantsLayer = true

        let titleLabel = NSTextField(labelWithString: "Layout Library")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 4
        stackView.edgeInsets = NSEdgeInsets(top: 44, left: 12, bottom: 12, right: 12)

        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(16, after: titleLabel)

        buildSection(title: "All Layouts", items: LayoutTemplate.all.map { ($0.id, $0.name, nil) })
        buildSavedSection()

        scrollView = NSScrollView(frame: bounds)
        scrollView.documentView = stackView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]

        // Size stackView
        let targetWidth = bounds.width - 24
        stackView.frame = CGRect(x: 0, y: 0, width: targetWidth, height: 10000)
        stackView.needsLayout = true

        addSubview(scrollView)
    }

    private func buildSection(title: String, items: [(String, String, SavedLayout?)]) {
        let header = NSTextField(labelWithString: title.uppercased())
        header.font = .systemFont(ofSize: 10, weight: .medium)
        header.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(6, after: header)

        for (id, name, saved) in items {
            let row = LibraryTemplateRowView(
                templateID: id,
                name: name,
                isSelected: id == selectedID,
                onTap: { [weak self] in
                    if let saved = saved { self?.onApplySaved(saved) } else { self?.onSelect(id) }
                }
            )
            row.widthAnchor.constraint(equalToConstant: bounds.width - 24).isActive = true
            stackView.addArrangedSubview(row)
            stackView.setCustomSpacing(2, after: row)
        }
        stackView.setCustomSpacing(16, after: stackView.arrangedSubviews.last ?? header)
    }

    private func buildSavedSection() {
        guard !savedLayouts.isEmpty else { return }
        let header = NSTextField(labelWithString: "SAVED")
        header.font = .systemFont(ofSize: 10, weight: .medium)
        header.textColor = .secondaryLabelColor
        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(6, after: header)

        for saved in savedLayouts {
            let row = LibraryTemplateRowView(
                templateID: saved.templateID,
                name: saved.name,
                isSelected: false,
                onTap: { [weak self] in self?.onApplySaved(saved) }
            )
            row.widthAnchor.constraint(equalToConstant: bounds.width - 24).isActive = true
            stackView.addArrangedSubview(row)
        }
    }

    func setSelected(_ id: String) {
        selectedID = id
        for sub in stackView.arrangedSubviews {
            (sub as? LibraryTemplateRowView)?.setSelected(sub.identifier?.rawValue == id)
        }
    }

    func reload(saved: [SavedLayout]) {
        self.savedLayouts = saved
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buildLayout()
    }
}

// MARK: - LibraryTemplateRowView

final class LibraryTemplateRowView: NSView {
    private var onTap: () -> Void
    private var isSelected: Bool
    private let label: NSTextField

    init(templateID: String, name: String, isSelected: Bool, onTap: @escaping () -> Void) {
        self.onTap = onTap
        self.isSelected = isSelected
        self.label = NSTextField(labelWithString: name)
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(templateID)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.font = .systemFont(ofSize: 12, weight: isSelected ? .medium : .regular)
        label.textColor = isSelected ? .white : .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        label.textColor = selected ? .white : .labelColor
        label.font = .systemFont(ofSize: 12, weight: selected ? .medium : .regular)
        updateAppearance()
    }

    private func updateAppearance() {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.clear.cgColor
    }

    override func mouseDown(with event: NSEvent) { onTap() }

    override func mouseEntered(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.clear.cgColor }
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
    private var applyButton: NSButton!
    private var templateNameLabel: NSTextField!

    init(frame: CGRect,
         template: LayoutTemplate,
         assignments: [Int: String],
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
        templateNameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        templateNameLabel.textColor = .labelColor
        templateNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(templateNameLabel)

        // Canvas area (inset from edges for padding)
        let canvasArea = NSView()
        canvasArea.wantsLayer = true
        canvasArea.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        canvasArea.layer?.cornerRadius = 12
        canvasArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(canvasArea)

        // Apply button
        applyButton = NSButton(title: "Apply Layout", target: self, action: #selector(applyTapped))
        applyButton.bezelStyle = .roundRect
        applyButton.wantsLayer = true
        applyButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        applyButton.layer?.cornerRadius = 8
        applyButton.contentTintColor = .white
        applyButton.font = .systemFont(ofSize: 13, weight: .medium)
        applyButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(applyButton)

        // Save button
        let saveBtn = NSButton(title: "Save…", target: self, action: #selector(saveTapped))
        saveBtn.bezelStyle = .roundRect
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(saveBtn)

        NSLayoutConstraint.activate([
            templateNameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            templateNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            canvasArea.topAnchor.constraint(equalTo: templateNameLabel.bottomAnchor, constant: 16),
            canvasArea.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            canvasArea.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            canvasArea.bottomAnchor.constraint(equalTo: applyButton.topAnchor, constant: -16),

            applyButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            applyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            applyButton.widthAnchor.constraint(equalToConstant: 130),
            applyButton.heightAnchor.constraint(equalToConstant: 32),

            saveBtn.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            saveBtn.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -8),
            saveBtn.heightAnchor.constraint(equalToConstant: 32)
        ])

        // Build slot views after layout
        layoutSubtreeIfNeeded()
        buildSlots(in: canvasArea)
    }

    private func buildSlots(in area: NSView) {
        let aw = area.bounds.width
        let ah = area.bounds.height
        guard aw > 0, ah > 0 else {
            // Defer to next layout pass
            DispatchQueue.main.async { [weak self, weak area] in
                guard let self, let area else { return }
                self.buildSlots(in: area)
            }
            return
        }

        let padding: CGFloat = 16
        let inner = CGRect(
            x: padding, y: padding,
            width: aw - padding * 2, height: ah - padding * 2
        )

        for slot in template.slots {
            let slotFrame = CGRect(
                x: inner.origin.x + slot.rect.origin.x * inner.width,
                y: inner.origin.y + slot.rect.origin.y * inner.height,
                width: slot.rect.width * inner.width,
                height: slot.rect.height * inner.height
            ).insetBy(dx: 4, dy: 4)

            let assignedBID = assignments[slot.id]
            let appInfo = assignedBID.flatMap { appLibrary.app(bundleID: $0) }

            let slotView = LibrarySlotView(
                frame: slotFrame,
                slotID: slot.id,
                appInfo: appInfo,
                onDrop: { [weak self] bundleID in self?.onDrop(slot.id, bundleID) }
            )
            area.addSubview(slotView)
            slotViews[slot.id] = slotView
        }
    }

    func update(template: LayoutTemplate? = nil, assignments: [Int: String]) {
        if let t = template { self.template = t }
        self.assignments = assignments
        buildCanvas()
    }

    @objc private func applyTapped() { onApply() }
    @objc private func saveTapped() { onSave() }
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
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        registerForDraggedTypes([kLayoutAppPasteboardType])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    func setApp(_ info: AppInfo?) {
        appInfo = info
        updateAppearance()
    }

    private func updateAppearance() {
        subviews.forEach { $0.removeFromSuperview() }
        layer?.borderColor = isDropTarget
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.backgroundColor = isDropTarget
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor

        if let app = appInfo {
            let icon = NSImageView(image: app.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!)
            icon.imageScaling = .scaleProportionallyUpOrDown
            let iconSize: CGFloat = min(bounds.width, bounds.height) * 0.45
            let iconFrame = CGRect(
                x: (bounds.width - iconSize) / 2,
                y: (bounds.height - iconSize) / 2 + 8,
                width: iconSize, height: iconSize
            )
            icon.frame = iconFrame
            addSubview(icon)

            let label = NSTextField(labelWithString: app.name)
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.frame = CGRect(x: 4, y: 6, width: bounds.width - 8, height: 14)
            addSubview(label)
        } else {
            // Empty state — subtle plus hint
            let plusLabel = NSTextField(labelWithString: "+")
            plusLabel.font = .systemFont(ofSize: 24, weight: .ultraLight)
            plusLabel.textColor = NSColor.tertiaryLabelColor
            plusLabel.alignment = .center
            plusLabel.frame = CGRect(x: 0, y: (bounds.height - 30) / 2, width: bounds.width, height: 30)
            addSubview(plusLabel)
        }
    }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.string(forType: kLayoutAppPasteboardType) != nil else { return [] }
        isDropTarget = true
        updateAppearance()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
        updateAppearance()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
        updateAppearance()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bundleID = sender.draggingPasteboard.string(forType: kLayoutAppPasteboardType) else { return false }
        onDrop(bundleID)
        isDropTarget = false
        return true
    }
}

// MARK: - LibraryAppDockView

final class LibraryAppDockView: NSView {
    private var apps: [AppInfo]
    private var searchQuery: String
    private var scrollView: NSScrollView!
    private var stackView: NSStackView!
    private var searchField: NSSearchField!

    init(frame: CGRect, apps: [AppInfo], searchQuery: String) {
        self.apps = apps
        self.searchQuery = searchQuery
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        buildDock()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildDock() {
        subviews.forEach { $0.removeFromSuperview() }

        // Top separator
        let sep = NSView(frame: CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        sep.autoresizingMask = [.width, .minYMargin]
        addSubview(sep)

        // Search field at right
        searchField = NSSearchField(frame: CGRect(x: bounds.width - 180, y: (bounds.height - 24) / 2, width: 160, height: 24))
        searchField.placeholderString = "Search apps…"
        searchField.font = .systemFont(ofSize: 11)
        searchField.autoresizingMask = [.minXMargin]
        searchField.target = self
        searchField.action = #selector(searchChanged)
        addSubview(searchField)

        // Scroll view for app icons
        let scrollFrame = CGRect(x: 8, y: 0, width: bounds.width - 200, height: bounds.height)
        scrollView = NSScrollView(frame: scrollFrame)
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width]

        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.alignment = .centerY

        let filtered = searchQuery.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        for app in filtered.prefix(60) {
            let item = LibraryAppItemView(app: app)
            stackView.addArrangedSubview(item)
        }

        let totalW = CGFloat(min(filtered.count, 60)) * 64 + 16
        stackView.frame = CGRect(x: 0, y: 0, width: max(totalW, scrollFrame.width), height: bounds.height)
        scrollView.documentView = stackView
        addSubview(scrollView)
    }

    @objc private func searchChanged() {
        searchQuery = searchField.stringValue
        let filtered = searchQuery.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for app in filtered.prefix(60) {
            stackView.addArrangedSubview(LibraryAppItemView(app: app))
        }
    }
}

// MARK: - LibraryAppItemView

final class LibraryAppItemView: NSView, NSDraggingSource {
    private let app: AppInfo
    private var isHighlighted = false

    init(app: AppInfo) {
        self.app = app
        super.init(frame: CGRect(x: 0, y: 0, width: 56, height: 72))
        wantsLayer = true
        layer?.cornerRadius = 8
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 56).isActive = true
        heightAnchor.constraint(equalToConstant: 72).isActive = true
        buildView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildView() {
        let iconSize: CGFloat = 40
        let iconView = NSImageView(frame: CGRect(x: (56 - iconSize) / 2, y: 22, width: iconSize, height: iconSize))
        iconView.image = app.icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        let label = NSTextField(labelWithString: app.name)
        label.font = .systemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.frame = CGRect(x: 2, y: 4, width: 52, height: 14)
        addSubview(label)
    }

    override func mouseDown(with event: NSEvent) {
        isHighlighted = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
    }

    override func mouseDragged(with event: NSEvent) {
        isHighlighted = false
        layer?.backgroundColor = nil

        let icon = app.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
        let dragImg = NSImage(size: NSSize(width: 40, height: 40))
        dragImg.lockFocus()
        icon.draw(in: NSRect(x: 0, y: 0, width: 40, height: 40))
        dragImg.unlockFocus()

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(app.id, forType: kLayoutAppPasteboardType)

        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        item.setDraggingFrame(CGRect(x: 8, y: 16, width: 40, height: 40), contents: dragImg)

        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        isHighlighted = false
        layer?.backgroundColor = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }
}
