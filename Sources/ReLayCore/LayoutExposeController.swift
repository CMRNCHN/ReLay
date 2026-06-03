import AppKit
import ApplicationServices

// MARK: - LayoutExposeController
// NON-GESTURE EXECUTION PATH — this controller initiates layout actions directly,
// bypassing GestureEngine and SpatialTransitionEngine. It calls LayoutOrchestrator
// directly and writes state back to SpatialTransitionEngine via registerExposeState/Undo.

public final class LayoutExposeController: NSWindowController {
    public static let shared = LayoutExposeController()

    private let orchestrator = LayoutOrchestrator.shared

    // MARK: Shared state
    private var triggerWindow: AXUIElement?
    private var screenFrame: CGRect = .zero
    private var currentWindows: [LayoutWindowItem] = []
    private var stageManagerWasEnabled: Bool = false

    public private(set) var isPresented: Bool = false

    // MARK: Step 1 — template selection
    private var suggestions: [LayoutSuggestionEngine.Suggestion] = []
    private var selectedIndex: Int = 0 { didSet { updateCardSelection() } }
    private var cards: [TemplateCardView] = []
    private var gridCols: Int = 3

    // MARK: Step 2 — assignment
    private var pendingTemplate: LayoutTemplate?
    private var pendingAssignment: [Int: LayoutWindowItem] = [:]  // slot id → window
    private var pendingLaunchBundleIDs: [Int: String] = [:]       // slot id → bundle to launch

    // MARK: Init
    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 500),
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
        stageManagerWasEnabled = orchestrator.isStageManagerEnabled()
        if stageManagerWasEnabled {
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
        selectedIndex = 0
        pendingTemplate = nil
        pendingAssignment = [:]
        pendingLaunchBundleIDs = [:]

        buildStep1UI()
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
        if stageManagerWasEnabled {
            orchestrator.setStageManager(true)
            stageManagerWasEnabled = false
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window?.animator().alphaValue = 0
        }) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    // MARK: - Keyboard

    public func handleKeyCode(_ keyCode: UInt16) {
        switch keyCode {
        case 53:     close()
        case 36, 76: pendingTemplate == nil ? applySelected() : commitAssignment(clean: false)
        case 123:    if pendingTemplate == nil { navigate(-1, axis: .horizontal) }
        case 124:    if pendingTemplate == nil { navigate( 1, axis: .horizontal) }
        case 125:    if pendingTemplate == nil { navigate( 1, axis: .vertical) }
        case 126:    if pendingTemplate == nil { navigate(-1, axis: .vertical) }
        default:     break
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Step 1: Template Selection
    // ─────────────────────────────────────────────────────────────────────────

    private func buildStep1UI() {
        guard let window else { return }
        window.setContentSize(NSSize(width: 860, height: 500))
        cards = []

        let fx = makePanel()
        window.contentView = fx

        let outer = makeOuter(in: fx)

        // Header
        addHeader("Choose a Layout", subtitle: "Select a template to arrange your windows", to: outer)
        outer.setCustomSpacing(18, after: outer.arrangedSubviews.last!)

        // Rank suggestions
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

        // Saved layouts row
        let saved = LayoutHistoryStore.shared.getSavedLayouts()
        if !saved.isEmpty {
            let savedRow = NSStackView()
            savedRow.orientation = .horizontal
            savedRow.spacing = 10
            for sl in saved.prefix(4) {
                let card = SavedLayoutCard(savedLayout: sl)
                card.onActivate = { [weak self] in self?.applySavedLayout(sl) }
                card.onDelete   = { [weak self] in
                    LayoutHistoryStore.shared.deleteSavedLayout(id: sl.id)
                    self?.buildStep1UI()
                }
                savedRow.addArrangedSubview(card)
            }
            let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            savedRow.addArrangedSubview(spacer)

            let savedLabel = sectionLabel("Saved Layouts")
            outer.addArrangedSubview(savedLabel)
            outer.setCustomSpacing(6, after: savedLabel)
            outer.addArrangedSubview(savedRow)
            outer.setCustomSpacing(16, after: savedRow)
        }

        // Template grid
        gridCols = suggestions.count <= 4 ? min(max(suggestions.count, 1), 2) : 3
        var idx = 0
        while idx < suggestions.count {
            let row = NSStackView()
            row.orientation = .horizontal; row.spacing = 12; row.distribution = .fillEqually
            for _ in 0..<gridCols where idx < suggestions.count {
                let s = suggestions[idx]
                let icons = autoFillIcons(for: s.template)
                let card = TemplateCardView(template: s.template, assignedIcons: icons, reason: s.reason)
                card.onActivate = { [weak self] in self?.templateSelected(s.template) }
                row.addArrangedSubview(card); cards.append(card); idx += 1
            }
            while row.arrangedSubviews.count < gridCols { row.addArrangedSubview(NSView()) }
            outer.addArrangedSubview(row)
            outer.setCustomSpacing(10, after: row)
        }

        // Footer
        let footer = makeFooter(canUndo: SpatialTransitionEngine.shared.canUndo)
        outer.addArrangedSubview(NSView())  // flex spacer
        outer.addArrangedSubview(footer)

        updateCardSelection()
    }

    private func templateSelected(_ template: LayoutTemplate) {
        pendingTemplate = template
        pendingAssignment = autoAssign(template: template, from: currentWindows)
        pendingLaunchBundleIDs = [:]
        buildStep2UI()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MARK: - Step 2: Assignment UI
    // ─────────────────────────────────────────────────────────────────────────

    private func buildStep2UI() {
        guard let window, let template = pendingTemplate else { return }
        window.setContentSize(NSSize(width: 1100, height: 660))
        centerOnScreen()

        let fx = makePanel()
        window.contentView = fx

        let editor = LayoutWorkspaceEditor(
            template: template,
            assignment: pendingAssignment,
            openWindows: currentWindows
        )
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.onBack = { [weak self] in self?.backToStep1() }
        editor.onApply = { [weak self] assignment in
            self?.pendingAssignment = assignment
            self?.commitAssignment(clean: true)
        }
        editor.onSave = { [weak self] assignment in
            self?.pendingAssignment = assignment
            self?.saveLayoutPressed()
        }
        editor.onAssignmentChanged = { [weak self] assignment in
            self?.pendingAssignment = assignment
        }

        fx.addSubview(editor)
        NSLayoutConstraint.activate([
            editor.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            editor.topAnchor.constraint(equalTo: fx.topAnchor, constant: 24),
            editor.bottomAnchor.constraint(equalTo: fx.bottomAnchor, constant: -16),
        ])
    }

    private func buildSlotChip(for slot: LayoutTemplate.Slot, template: LayoutTemplate) -> NSView {
        let item = pendingAssignment[slot.id]

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 0.5
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // Slot number badge
        let badge = NSTextField(labelWithString: "Slot \(slot.id + 1)")
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .tertiaryLabelColor
        badge.translatesAutoresizingMaskIntoConstraints = false

        // App icon
        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyDown
        iconView.image = item?.appIcon ?? NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: nil)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // App name
        let nameLabel = NSTextField(labelWithString: item.map { $0.appName ?? $0.title } ?? "Empty")
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textColor = item != nil ? .labelColor : .secondaryLabelColor
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Change button
        let changeBtn = NSButton(title: "⊕ Assign", target: self, action: #selector(assignSlotPressed(_:)))
        changeBtn.bezelStyle = .inline
        changeBtn.font = .systemFont(ofSize: 11)
        changeBtn.tag = slot.id
        changeBtn.contentTintColor = .controlAccentColor
        changeBtn.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(badge)
        container.addSubview(iconView)
        container.addSubview(nameLabel)
        container.addSubview(changeBtn)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            badge.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            iconView.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            changeBtn.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            changeBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            changeBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        return container
    }

    /// Icon chip for the "open windows" row in step 2.
    /// `showLabel` = true when multiple windows from same app are open (disambiguation).
    /// `dimmed` = true when already assigned to a slot.
    private func openWindowChip(for item: LayoutWindowItem, showLabel: Bool, dimmed: Bool) -> NSView {
        let chip = NSView()
        chip.wantsLayer = true
        let alpha: CGFloat = dimmed ? 0.35 : 1.0
        chip.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(dimmed ? 0.04 : 0.07).cgColor
        chip.layer?.cornerRadius = 10
        chip.layer?.opacity = Float(alpha)
        chip.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = item.appIcon
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        chip.addSubview(icon)
        var constraints: [NSLayoutConstraint] = [
            icon.topAnchor.constraint(equalTo: chip.topAnchor, constant: 6),
            icon.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -6),
            icon.centerXAnchor.constraint(equalTo: chip.centerXAnchor),
        ]

        if showLabel {
            // Shorten window title to ~12 chars
            let raw = item.title.prefix(14)
            let shortTitle = raw.count < item.title.count ? "\(raw)…" : String(raw)
            let label = NSTextField(labelWithString: shortTitle)
            label.font = .systemFont(ofSize: 9)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(label)
            constraints += [
                icon.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 6),
                icon.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -6),
                label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -4),
                label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 2),
                label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -4),
            ]
        } else {
            constraints += [
                icon.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 6),
                icon.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -6),
            ]
        }

        NSLayoutConstraint.activate(constraints)
        if dimmed {
            let badge = NSTextField(labelWithString: "✓")
            badge.font = .systemFont(ofSize: 8, weight: .bold)
            badge.textColor = .controlAccentColor
            badge.translatesAutoresizingMaskIntoConstraints = false
            chip.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -2),
                badge.topAnchor.constraint(equalTo: chip.topAnchor, constant: 2),
            ])
        }
        return chip
    }

    // MARK: - Step 2 Actions

    @objc private func backToStep1() {
        pendingTemplate = nil
        pendingAssignment = [:]
        window?.setContentSize(NSSize(width: 860, height: 500))
        buildStep1UI()
        centerOnScreen()
    }

    @objc private func assignSlotPressed(_ sender: NSButton) {
        guard let template = pendingTemplate else { return }
        let slotID = sender.tag
        showAppPicker(forSlot: slotID, template: template, relativeTo: sender)
    }

    @objc private func applyBtnPressed() { commitAssignment(clean: true) }

    @objc private func saveLayoutPressed() {
        guard let template = pendingTemplate else { return }
        promptSaveLayout(template: template)
    }

    private func showAppPicker(forSlot slotID: Int, template: LayoutTemplate, relativeTo view: NSView) {
        let menu = NSMenu()

        // Currently assigned → show at top as "Clear"
        if let current = pendingAssignment[slotID] {
            let clearItem = NSMenuItem(title: "✕  Clear \"\(current.appName ?? current.title)\"", action: nil, keyEquivalent: "")
            clearItem.representedObject = ("clear", slotID, nil as LayoutWindowItem?)
            clearItem.target = self
            clearItem.action = #selector(appPickerItemSelected(_:))
            menu.addItem(clearItem)
            menu.addItem(.separator())
        }

        // Running windows
        let running = currentWindows
        if !running.isEmpty {
            menu.addItem(sectionHeader("Open Windows"))
            for item in running {
                let mi = NSMenuItem(title: (item.appName ?? item.title), action: #selector(appPickerItemSelected(_:)), keyEquivalent: "")
                mi.image = item.appIcon.flatMap { img -> NSImage? in
                    let copy = img.copy() as! NSImage; copy.size = NSSize(width: 16, height: 16); return copy
                }
                mi.representedObject = ("assign-window", slotID, item) as (String, Int, LayoutWindowItem?)
                mi.target = self
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        // Favorites
        let favBundleIDs = LayoutHistoryStore.shared.getFavoriteApps()
        let favApps = favBundleIDs.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
            ?? installedApp(bundleID: $0) }
        if !favApps.isEmpty {
            menu.addItem(sectionHeader("Favorites ★"))
            for app in favApps.prefix(5) {
                let mi = NSMenuItem(title: app.localizedName ?? app.bundleIdentifier ?? "App",
                                    action: #selector(appPickerItemSelected(_:)), keyEquivalent: "")
                if let icon = app.icon {
                    let copy = icon.copy() as! NSImage; copy.size = NSSize(width: 16, height: 16)
                    mi.image = copy
                }
                let bid = app.bundleIdentifier ?? ""
                mi.representedObject = ("launch", slotID, bid) as (String, Int, String)
                mi.target = self
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        // Recommended / recent apps
        let recentIDs = LayoutHistoryStore.shared.getHistory()
            .flatMap { $0.visibleAppBundleIDs }
            .prefix(20)
        var seen = Set<String>(favBundleIDs)
        var recommended: [(String, String)] = []  // (name, bundleID)
        for bid in recentIDs {
            guard !seen.contains(bid) else { continue }
            seen.insert(bid)
            if let name = installedAppName(bundleID: bid) {
                recommended.append((name, bid))
            }
            if recommended.count >= 4 { break }
        }
        if !recommended.isEmpty {
            menu.addItem(sectionHeader("Suggested"))
            for (name, bid) in recommended {
                let mi = NSMenuItem(title: name, action: #selector(appPickerItemSelected(_:)), keyEquivalent: "")
                mi.representedObject = ("launch", slotID, bid) as (String, Int, String)
                mi.target = self
                menu.addItem(mi)
            }
            menu.addItem(.separator())
        }

        // Browse all apps
        let browseItem = NSMenuItem(title: "Browse All Apps…", action: #selector(browseAllAppsPressed(_:)), keyEquivalent: "")
        browseItem.representedObject = slotID
        browseItem.target = self
        menu.addItem(browseItem)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height), in: view)
    }

    @objc private func appPickerItemSelected(_ sender: NSMenuItem) {
        guard let rep = sender.representedObject else { return }
        if let tuple = rep as? (String, Int, LayoutWindowItem?) {
            let (action, slotID, item) = tuple
            if action == "clear" {
                pendingAssignment.removeValue(forKey: slotID)
            } else if action == "assign-window", let item {
                pendingAssignment[slotID] = item
            }
            buildStep2UI(); centerOnScreen()
        } else if let tuple = rep as? (String, Int, String) {
            let (_, slotID, bundleID) = tuple
            // If app is running, assign its frontmost window
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                let axApp = AXUIElementCreateApplication(running.processIdentifier)
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                   let list = ref as? [AXUIElement], let win = list.first {
                    let item = LayoutWindowItem(
                        id: bundleID, element: win, title: running.localizedName ?? bundleID,
                        appName: running.localizedName, bundleID: bundleID,
                        appIcon: running.icon,
                        role: WindowRoleClassifier.classify(appName: running.localizedName, windowTitle: nil)
                    )
                    pendingAssignment[slotID] = item
                }
            } else {
                // Mark for launch-on-apply
                pendingLaunchBundleIDs[slotID] = bundleID
            }
            buildStep2UI(); centerOnScreen()
        }
    }

    @objc private func browseAllAppsPressed(_ sender: NSMenuItem) {
        guard let slotID = sender.representedObject as? Int else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose an App"
        panel.prompt = "Assign to Slot"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            let bid = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
            let appName = url.deletingPathExtension().lastPathComponent
            let item = LayoutWindowItem(
                id: bid, element: AXUIElementCreateSystemWide(),
                title: appName, appName: appName, bundleID: bid,
                appIcon: NSWorkspace.shared.icon(forFile: url.path),
                role: .other
            )
            DispatchQueue.main.async {
                self?.pendingLaunchBundleIDs[slotID] = bid
                // Use a placeholder in the assignment for display
                self?.pendingAssignment[slotID] = item
                self?.buildStep2UI()
                self?.centerOnScreen()
            }
        }
    }

    // MARK: - Commit assignment (Apply)

    private func commitAssignment(clean: Bool) {
        guard let template = pendingTemplate else { return }

        // Launch any pending apps first
        for (_, bundleID) in pendingLaunchBundleIDs {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = false
                NSWorkspace.shared.openApplication(at: appURL, configuration: cfg)
            }
        }

        // If we launched apps, wait briefly then re-enumerate windows
        let hasLaunches = !pendingLaunchBundleIDs.isEmpty
        let delay: TimeInterval = hasLaunches ? 1.2 : 0

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }

            // Re-resolve windows for launched apps
            if hasLaunches {
                let updated = self.makeWindowItems()
                for (slotID, bundleID) in self.pendingLaunchBundleIDs {
                    if let win = updated.first(where: { $0.bundleID == bundleID }) {
                        self.pendingAssignment[slotID] = win
                    }
                }
            }

            self.applyFinalLayout(template: template, assignments: self.pendingAssignment, clean: clean)
        }

        // Close immediately (apply happens asynchronously for launched apps)
        close()
    }

    private func applyFinalLayout(template: LayoutTemplate,
                                  assignments: [Int: LayoutWindowItem],
                                  clean: Bool) {
        AppLogger.log("expose: applying \(template.name) assigned=\(assignments.count) clean=\(clean) screenFrame=\(screenFrame)", subsystem: "expose")

        // Capture undo state for ALL windows (assigned + stragglers)
        var originalFrames: [AXUIElement: CGRect] = [:]
        for item in currentWindows {
            if let frame = orchestrator.getWindowFrame(item.element) {
                originalFrames[item.element] = frame
            }
        }
        SpatialTransitionEngine.shared.registerExposeUndo(frames: originalFrames)

        let assignedElements = Set(assignments.values.map { axID($0.element) })

        // Push non-assigned windows off the right edge (clean screen)
        if clean {
            for item in currentWindows {
                guard !assignedElements.contains(axID(item.element)) else { continue }
                if let frame = orchestrator.getWindowFrame(item.element) {
                    let offscreen = CGRect(x: screenFrame.maxX + 40,
                                          y: frame.minY, width: frame.width, height: frame.height)
                    orchestrator.animateWindowFrame(item.element, to: offscreen, duration: 0.25)
                }
            }
        }

        // Animate assigned windows into their slots
        let orderedWindows = template.slots.compactMap { assignments[$0.id]?.element }
        SpatialTransitionEngine.shared.registerExposeState(template: template,
                                                            windows: orderedWindows,
                                                            screenFrame: screenFrame)

        for slot in template.slots {
            guard let item = assignments[slot.id] else { continue }
            let target = template.frame(for: slot, in: screenFrame)
            AppLogger.log("expose: slot \(slot.id) → \(item.appName ?? item.title) target=\(target)", subsystem: "expose")
            orchestrator.animateWindowFrame(item.element, to: target)
        }

        LayoutHistoryStore.shared.recordApply(event: AppliedLayoutEvent(
            layoutTemplateID: template.id,
            workspacePresetID: nil,
            visibleWindowRoles: currentWindows.map { $0.role },
            visibleAppBundleIDs: currentWindows.compactMap { $0.bundleID },
            screenAspectRatio: screenFrame.width / max(1, screenFrame.height),
            displayCount: NSScreen.screens.count
        ))
    }

    // MARK: - Save Layout

    /// Called from menu bar "Save Current Layout…" — saves whatever template was last applied.
    public func promptSaveCurrentFromMenu() {
        // Use the last applied template from history if available
        let lastID = LayoutHistoryStore.shared.getRecentTemplateIDs().first
        let template = lastID.flatMap { id in LayoutTemplate.all.first(where: { $0.id == id }) }
            ?? LayoutTemplate.all.first!
        // Build assignment from current windows
        pendingAssignment = autoAssign(template: template, from: makeWindowItems())
        promptSaveLayout(template: template)
    }

    private func promptSaveLayout(template: LayoutTemplate) {
        let alert = NSAlert()
        alert.messageText = "Save Layout"
        alert.informativeText = "Give this layout a name. It will appear as a saved layout in Exposé."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        input.placeholderString = "\(template.name) — \(formattedDate())"
        alert.accessoryView = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        let finalName = name.isEmpty ? (input.placeholderString ?? template.name) : name

        var slotBundleIDs: [Int: String] = [:]
        for (slotID, item) in pendingAssignment {
            if let bid = item.bundleID { slotBundleIDs[slotID] = bid }
        }

        let layout = SavedLayout(name: finalName, templateID: template.id, slotBundleIDs: slotBundleIDs)
        LayoutHistoryStore.shared.saveSavedLayout(layout)
        AppLogger.log("expose: saved layout '\(finalName)' templateID=\(template.id)", subsystem: "expose")
    }

    private func applySavedLayout(_ saved: SavedLayout) {
        guard let template = LayoutTemplate.all.first(where: { $0.id == saved.templateID }) else { return }

        // Build assignment from bundle IDs
        var assignments: [Int: LayoutWindowItem] = [:]
        for (slotID, bundleID) in saved.slotBundleIDs {
            if let item = currentWindows.first(where: { $0.bundleID == bundleID }) {
                assignments[slotID] = item
            }
        }
        // Fill remaining with auto-assign
        let partialAssignment = autoAssign(template: template, from: currentWindows,
                                            excludingSlots: Set(assignments.keys))
        for (k, v) in partialAssignment { if assignments[k] == nil { assignments[k] = v } }

        LayoutHistoryStore.shared.touchSavedLayout(id: saved.id)
        applyFinalLayout(template: template, assignments: assignments, clean: true)
        close()
    }

    // MARK: - Helpers

    private func autoAssign(template: LayoutTemplate,
                             from windows: [LayoutWindowItem],
                             excludingSlots: Set<Int> = []) -> [Int: LayoutWindowItem] {
        var assignments: [Int: LayoutWindowItem] = [:]
        var remaining = windows
        for slot in template.slots where !excludingSlots.contains(slot.id) {
            if let idx = remaining.firstIndex(where: { slot.preferredRoles.contains($0.role) }) {
                assignments[slot.id] = remaining.remove(at: idx)
            }
        }
        for slot in template.slots where assignments[slot.id] == nil && !excludingSlots.contains(slot.id) && !remaining.isEmpty {
            assignments[slot.id] = remaining.remove(at: 0)
        }
        return assignments
    }

    private func axID(_ element: AXUIElement) -> String {
        "\(CFHash(element))"
    }

    private func autoFillIcons(for template: LayoutTemplate) -> [Int: NSImage] {
        var result: [Int: NSImage] = [:]
        var remaining = currentWindows
        for slot in template.slots {
            if let idx = remaining.firstIndex(where: { slot.preferredRoles.contains($0.role) }) {
                result[slot.id] = remaining.remove(at: idx).appIcon
            }
        }
        for slot in template.slots where result[slot.id] == nil && !remaining.isEmpty {
            result[slot.id] = remaining.remove(at: 0).appIcon
        }
        return result.compactMapValues { $0 }
    }

    private func installedApp(bundleID: String) -> NSRunningApplication? { nil }

    private func installedAppName(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }

    private func formattedDate() -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none
        return f.string(from: Date())
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        return item
    }

    // MARK: - UI Helpers

    private func makePanel() -> NSVisualEffectView {
        let fx = NSVisualEffectView(frame: window?.contentView?.bounds ?? .zero)
        fx.autoresizingMask = [.width, .height]
        fx.material = .underWindowBackground
        fx.blendingMode = .behindWindow
        fx.state = .active
        fx.wantsLayer = true
        fx.layer?.cornerRadius = 20
        fx.layer?.masksToBounds = true
        return fx
    }

    private func makeOuter(in fx: NSView) -> NSStackView {
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
            outer.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
            outer.widthAnchor.constraint(equalTo: fx.widthAnchor),
        ])
        return outer
    }

    private func addHeader(_ title: String, subtitle: String, to stack: NSStackView) {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 18, weight: .semibold)
        t.textColor = .labelColor
        stack.addArrangedSubview(t)
        stack.setCustomSpacing(3, after: t)
        let s = NSTextField(labelWithString: subtitle)
        s.font = .systemFont(ofSize: 12)
        s.textColor = .secondaryLabelColor
        stack.addArrangedSubview(s)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = .tertiaryLabelColor
        return l
    }

    private func makeFooter(canUndo: Bool) -> NSStackView {
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 12
        if canUndo {
            let btn = footerButton("↩  Undo Last Layout", action: #selector(undoPressed))
            footer.addArrangedSubview(btn)
        }
        let sp = NSView(); sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footer.addArrangedSubview(sp)
        let hint = NSTextField(labelWithString: "↑↓←→ navigate  ·  ↵ apply  ·  esc close")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .quaternaryLabelColor
        footer.addArrangedSubview(hint)
        return footer
    }

    private func footerButton(_ title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    // MARK: - Keyboard navigation (Step 1)

    private enum NavAxis { case horizontal, vertical }

    private func navigate(_ delta: Int, axis: NavAxis) {
        let cols = gridCols; let count = cards.count
        guard count > 0 else { return }
        let row = selectedIndex / cols; let col = selectedIndex % cols
        switch axis {
        case .horizontal:
            let rowStart = row * cols; let rowEnd = min(rowStart + cols, count) - 1
            selectedIndex = max(rowStart, min(rowEnd, rowStart + col + delta))
        case .vertical:
            let rows = (count + cols - 1) / cols; let newRow = max(0, min(rows - 1, row + delta))
            selectedIndex = min(count - 1, newRow * cols + col)
        }
    }

    private func applySelected() {
        guard selectedIndex < suggestions.count else { return }
        templateSelected(suggestions[selectedIndex].template)
    }

    private func updateCardSelection() {
        for (i, card) in cards.enumerated() { card.setSelected(i == selectedIndex) }
    }

    // MARK: - Actions

    @objc private func undoPressed() { SpatialTransitionEngine.shared.performExposeUndo(); close() }

    // MARK: - Screen helpers

    private func centerOnScreen() {
        guard let window else { return }
        let screen = nsScreenForScreenFrame() ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame; let wf = window.frame
        window.setFrameOrigin(CGPoint(x: sf.midX - wf.width / 2, y: sf.midY - wf.height / 2))
    }

    private func nsScreenForScreenFrame() -> NSScreen? {
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryH = primary.frame.height
        var best: NSScreen?; var bestArea: CGFloat = -1
        for screen in NSScreen.screens {
            let axY = primaryH - (screen.frame.origin.y + screen.frame.height)
            let axFrame = CGRect(x: screen.frame.origin.x, y: axY,
                                 width: screen.frame.width, height: screen.frame.height)
            let area = axFrame.intersection(screenFrame).width * axFrame.intersection(screenFrame).height
            if area > bestArea { bestArea = area; best = screen }
        }
        return best
    }

    private func mainScreenFrame() -> CGRect {
        guard let primary = NSScreen.screens.first else { return .zero }
        let target = NSScreen.main ?? primary; let vf = target.visibleFrame
        let flipped = primary.frame.height - (vf.origin.y + vf.height)
        return CGRect(x: vf.origin.x, y: flipped, width: vf.width, height: vf.height)
    }

    private func makeWindowItems() -> [LayoutWindowItem] {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return orchestrator.getAllVisibleWindows().enumerated().map { i, element in
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let app = NSRunningApplication(processIdentifier: pid)
            let title = orchestrator.windowTitle(for: element)
            var item = LayoutWindowItem(
                id: "\(i)-\(title)", element: element, title: title,
                appName: app?.localizedName, bundleID: app?.bundleIdentifier,
                appIcon: app?.icon,
                role: WindowRoleClassifier.classify(appName: app?.localizedName, windowTitle: title)
            )
            item.isActive = (pid == frontmostPID)
            return item
        }
    }
}

// MARK: - AssignmentDiagramView
// Large layout diagram showing slot zones with assigned app icons.

private final class AssignmentDiagramView: NSView {
    let template: LayoutTemplate
    var assignment: [Int: LayoutWindowItem]

    init(template: LayoutTemplate, assignment: [Int: LayoutWindowItem]) {
        self.template = template
        self.assignment = assignment
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 0.5
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let pad: CGFloat = 10
        let canvas = bounds.insetBy(dx: pad, dy: pad)
        for slot in template.slots {
            let flippedY = 1.0 - slot.rect.minY - slot.rect.height
            let gap: CGFloat = 5
            let slotRect = CGRect(
                x: canvas.minX + slot.rect.minX * canvas.width + gap,
                y: canvas.minY + flippedY * canvas.height + gap,
                width: slot.rect.width * canvas.width - gap * 2,
                height: slot.rect.height * canvas.height - gap * 2
            )
            guard slotRect.width > 8, slotRect.height > 8 else { continue }

            // Background
            NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: slotRect, xRadius: 8, yRadius: 8).fill()
            NSColor.controlAccentColor.withAlphaComponent(0.25).setStroke()
            let path = NSBezierPath(roundedRect: slotRect.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7)
            path.lineWidth = 1.5; path.stroke()

            // App icon
            if let icon = assignment[slot.id]?.appIcon {
                let maxIcon = min(slotRect.width * 0.45, slotRect.height * 0.55, 40.0)
                let ir = CGRect(x: slotRect.midX - maxIcon / 2,
                                y: slotRect.midY - maxIcon / 2,
                                width: maxIcon, height: maxIcon)
                icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 0.9)
            }

            // Slot label
            let label = assignment[slot.id].flatMap { $0.appName } ?? "Slot \(slot.id + 1)"
            let font = NSFont.systemFont(ofSize: max(9, min(11, slotRect.width / 8)))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let str = NSAttributedString(string: label, attributes: attrs)
            let sz = str.size()
            if sz.width < slotRect.width - 8 {
                str.draw(at: CGPoint(x: slotRect.midX - sz.width / 2,
                                     y: slotRect.minY + 5))
            }
        }
    }
}

// MARK: - SavedLayoutCard

private final class SavedLayoutCard: NSView {
    let savedLayout: SavedLayout
    var onActivate: (() -> Void)?
    var onDelete: (() -> Void)?

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(savedLayout: SavedLayout) {
        self.savedLayout = savedLayout
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 56).isActive = true
        widthAnchor.constraint(equalToConstant: 140).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onActivate?() }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let del = NSMenuItem(title: "Delete Layout", action: #selector(deletePressed), keyEquivalent: "")
        del.target = self
        menu.addItem(del)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func deletePressed() { onDelete?() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10).stroke()

        // Star badge
        let starAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemYellow
        ]
        NSAttributedString(string: "★", attributes: starAttrs).draw(at: CGPoint(x: 8, y: bounds.height - 20))

        // Name
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let name = NSAttributedString(string: savedLayout.name, attributes: nameAttrs)
        let nameSz = name.size()
        name.draw(at: CGPoint(x: (bounds.width - min(nameSz.width, bounds.width - 16)) / 2, y: bounds.midY - nameSz.height / 2))
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
        self.template = template; self.assignedIcons = assignedIcons; self.reason = reason
        super.init(frame: .zero)
        wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 130).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setSelected(_ selected: Bool) {
        guard selected != isSelected else { return }
        isSelected = selected; needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onActivate?() }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.14)
            : isHovered ? NSColor.labelColor.withAlphaComponent(0.07)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.65)
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        let borderColor: NSColor = isSelected ? .controlAccentColor : .separatorColor
        borderColor.withAlphaComponent(isSelected ? 0.85 : 0.6).setStroke()
        let bp = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        bp.lineWidth = isSelected ? 1.5 : 0.5; bp.stroke()

        let nameH: CGFloat = 24; let reasonH: CGFloat = reason.isEmpty ? 4 : 18; let pad: CGFloat = 10
        let diagramRect = CGRect(x: pad, y: reasonH, width: bounds.width - pad*2,
                                 height: bounds.height - nameH - reasonH - pad/2)
        drawName(at: bounds.height - nameH, height: nameH)
        drawSlots(in: diagramRect)
        if !reason.isEmpty { drawReason(height: reasonH) }
    }

    private func drawName(at yOffset: CGFloat, height: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: template.name, attributes: attrs)
        str.draw(at: CGPoint(x: 10, y: yOffset + (height - str.size().height) / 2))
    }

    private func drawSlots(in dr: CGRect) {
        let fill = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.25)
            : NSColor.secondaryLabelColor.withAlphaComponent(0.18)
        for slot in template.slots {
            let flippedY = 1.0 - slot.rect.minY - slot.rect.height; let gap: CGFloat = 3
            let sr = CGRect(x: dr.minX + slot.rect.minX * dr.width + gap,
                            y: dr.minY + flippedY * dr.height + gap,
                            width: slot.rect.width * dr.width - gap*2,
                            height: slot.rect.height * dr.height - gap*2)
            guard sr.width > 4, sr.height > 4 else { continue }
            fill.setFill(); NSBezierPath(roundedRect: sr, xRadius: 5, yRadius: 5).fill()
            if let icon = assignedIcons[slot.id] {
                let s = min(22, sr.width*0.42, sr.height*0.55)
                let ir = CGRect(x: sr.midX-s/2, y: sr.midY-s/2, width: s, height: s)
                icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 0.85)
            }
        }
    }

    private func drawReason(height: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let str = NSAttributedString(string: reason, attributes: attrs)
        str.draw(at: CGPoint(x: 10, y: (height - str.size().height) / 2))
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
        wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }
    override func mouseDown(with event: NSEvent)    { onActivate?() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.withAlphaComponent(isHovered ? 0.12 : 0.07).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: workspace.name, attributes: attrs)
        let sz = str.size()
        str.draw(at: CGPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }

    override var intrinsicContentSize: NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]
        return NSSize(width: workspace.name.size(withAttributes: attrs).width + 24, height: 28)
    }
}
