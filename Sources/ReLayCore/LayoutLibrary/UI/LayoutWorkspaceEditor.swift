import AppKit
import Foundation

// Shared pasteboard type for drag-and-drop within the workspace editor
extension NSPasteboard.PasteboardType {
    static let relayAppItem = NSPasteboard.PasteboardType("com.cameroncohen.relay.appitem")
}

// MARK: - LayoutWorkspaceEditor
// Three-panel workspace builder: open windows | layout diagram + slots | app source

final class LayoutWorkspaceEditor: NSView {
    // MARK: Data
    let template: LayoutTemplate
    var assignment: [Int: LayoutWindowItem]         // slotID → window
    var onAssignmentChanged: (([Int: LayoutWindowItem]) -> Void)?
    var onApply: (([Int: LayoutWindowItem]) -> Void)?
    var onBack: (() -> Void)?
    var onSave: (([Int: LayoutWindowItem]) -> Void)?

    private let openWindows: [LayoutWindowItem]
    private var slotZones: [SlotDropZoneView] = []
    private var assignmentListStack: NSStackView?
    private var searchField: NSSearchField?
    private var allAppsStack: NSStackView?

    // MARK: Init
    init(template: LayoutTemplate,
                assignment: [Int: LayoutWindowItem],
                openWindows: [LayoutWindowItem]) {
        self.template = template
        self.assignment = assignment
        self.openWindows = openWindows
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func buildLayout() {
        // Outer: header + 3-col body + action bar
        let outerStack = NSStackView()
        outerStack.orientation = .vertical; outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerStack.topAnchor.constraint(equalTo: topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Header
        outerStack.addArrangedSubview(buildHeader())
        outerStack.setCustomSpacing(12, after: outerStack.arrangedSubviews.last!)

        // 3-col body
        let body = NSStackView()
        body.orientation = .horizontal; body.spacing = 12
        body.alignment = .top; body.distribution = .fill
        body.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        let leftPanel  = buildLeftPanel()
        let centerPanel = buildCenterPanel()
        let rightPanel = buildRightPanel()

        body.addArrangedSubview(leftPanel)
        body.addArrangedSubview(centerPanel)
        body.addArrangedSubview(rightPanel)

        leftPanel.widthAnchor.constraint(equalToConstant: 160).isActive = true
        rightPanel.widthAnchor.constraint(equalToConstant: 240).isActive = true
        centerPanel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        outerStack.addArrangedSubview(body)
        outerStack.setCustomSpacing(12, after: body)

        // Action bar
        outerStack.addArrangedSubview(buildActionBar())
    }

    // MARK: Header

    private func buildHeader() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal; row.spacing = 10; row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        let backBtn = NSButton(title: "← Templates", target: self, action: #selector(backPressed))
        backBtn.bezelStyle = .inline; backBtn.font = .systemFont(ofSize: 12)
        backBtn.contentTintColor = .secondaryLabelColor
        row.addArrangedSubview(backBtn)

        let title = NSTextField(labelWithString: "\(template.name) Layout")
        title.font = .systemFont(ofSize: 16, weight: .semibold); title.textColor = .labelColor
        row.addArrangedSubview(title)

        let sp = NSView(); sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(sp)

        return row
    }

    // MARK: Left Panel — Open Windows

    private func buildLeftPanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical; panel.spacing = 8; panel.alignment = .leading

        let hdr = sectionLabel("OPEN WINDOWS")
        panel.addArrangedSubview(hdr)

        // Count windows per app for disambiguation
        var appCounts: [String: Int] = [:]
        for w in openWindows { appCounts[w.appName ?? w.title, default: 0] += 1 }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let chipStack = NSStackView()
        chipStack.orientation = .vertical; chipStack.spacing = 6; chipStack.alignment = .leading
        chipStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = chipStack

        NSLayoutConstraint.activate([
            chipStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            chipStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            chipStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            chipStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        let assignedBundleIDs = Set(assignment.values.compactMap { $0.bundleID })
        for w in openWindows {
            let needsLabel = (appCounts[w.appName ?? w.title] ?? 1) > 1
            let isAssigned = w.bundleID.map { assignedBundleIDs.contains($0) } ?? false
            let chip = DraggableWindowChip(windowItem: w, showLabel: needsLabel, dimmed: isAssigned)
            chip.widthAnchor.constraint(equalToConstant: 148).isActive = true
            chipStack.addArrangedSubview(chip)
        }

        panel.addArrangedSubview(scrollView)
        scrollView.widthAnchor.constraint(equalToConstant: 152).isActive = true
        scrollView.heightAnchor.constraint(equalToConstant: 340).isActive = true
        return panel
    }

    // MARK: Center Panel — Diagram + Slot Zones + Assignment List

    private func buildCenterPanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical; panel.spacing = 12; panel.alignment = .leading

        let hdr = sectionLabel("LAYOUT SLOTS")
        panel.addArrangedSubview(hdr)

        // Slot zone grid: proportional to template slot rects
        let diagContainer = NSView()
        diagContainer.wantsLayer = true
        diagContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4).cgColor
        diagContainer.layer?.cornerRadius = 14
        diagContainer.layer?.borderColor = NSColor.separatorColor.cgColor
        diagContainer.layer?.borderWidth = 0.5
        diagContainer.translatesAutoresizingMaskIntoConstraints = false
        diagContainer.heightAnchor.constraint(equalToConstant: 280).isActive = true

        slotZones = []
        for slot in template.slots {
            let zone = SlotDropZoneView(slotID: slot.id, slotRect: slot.rect)
            zone.translatesAutoresizingMaskIntoConstraints = false
            zone.assignment = assignment[slot.id]
            zone.onDrop = { [weak self] slotID, bundleIDOrWindowID in
                self?.handleDrop(slotID: slotID, sourceID: bundleIDOrWindowID)
            }
            zone.onClear = { [weak self] slotID in
                self?.assignment.removeValue(forKey: slotID)
                self?.refreshUI()
            }
            zone.onClick = { [weak self] slotID in
                self?.searchField?.becomeFirstResponder()
            }
            diagContainer.addSubview(zone)
            slotZones.append(zone)
        }

        panel.addArrangedSubview(diagContainer)
        // Constraints for slot zones will be set in layoutSubviews/updateConstraints
        // We use a simple approach: anchor to proportional positions
        diagContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        // Assignment list below diagram
        let assignListHdr = sectionLabel("ASSIGNED")
        panel.addArrangedSubview(assignListHdr)

        let listStack = NSStackView()
        listStack.orientation = .vertical; listStack.spacing = 6; listStack.alignment = .leading
        assignmentListStack = listStack
        panel.addArrangedSubview(listStack)
        listStack.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true

        refreshAssignmentList()

        // We use override to layout slot zones after frame is known
        diagContainer.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: diagContainer, queue: .main
        ) { [weak self, weak diagContainer] _ in
            self?.layoutSlotZones(in: diagContainer)
        }

        return panel
    }

    private func layoutSlotZones(in container: NSView?) {
        guard let container else { return }
        let w = container.bounds.width; let h = container.bounds.height
        let pad: CGFloat = 10
        for zone in slotZones {
            let r = zone.slotRect
            let flippedY = 1.0 - r.minY - r.height
            let gap: CGFloat = 5
            let frame = CGRect(
                x: pad + r.minX * (w - pad*2) + gap,
                y: pad + flippedY * (h - pad*2) + gap,
                width: r.width * (w - pad*2) - gap*2,
                height: r.height * (h - pad*2) - gap*2
            )
            zone.frame = frame
        }
    }

    private func refreshAssignmentList() {
        guard let listStack = assignmentListStack else { return }
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for slot in template.slots {
            let item = assignment[slot.id]
            let row = assignmentRow(slotNumber: slot.id + 1, item: item)
            listStack.addArrangedSubview(row)
        }
    }

    private func assignmentRow(slotNumber: Int, item: LayoutWindowItem?) -> NSView {
        let emojiNumbers = ["1️⃣","2️⃣","3️⃣","4️⃣","5️⃣","6️⃣"]
        let emoji = slotNumber <= emojiNumbers.count ? emojiNumbers[slotNumber - 1] : "\(slotNumber)."

        let numLabel = NSTextField(labelWithString: emoji)
        numLabel.font = .systemFont(ofSize: 14); numLabel.setContentHuggingPriority(.required, for: .horizontal)

        let nameLabel: NSTextField
        if let item = item {
            nameLabel = NSTextField(labelWithString: item.appName ?? item.title)
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium); nameLabel.textColor = .labelColor
        } else {
            nameLabel = NSTextField(labelWithString: "Empty — drag an app here")
            nameLabel.font = .systemFont(ofSize: 12); nameLabel.textColor = .tertiaryLabelColor
        }

        let row = NSStackView(views: [numLabel, nameLabel])
        row.spacing = 8; row.alignment = .centerY
        return row
    }

    // MARK: Right Panel — Favorites, Recommended, All Apps

    private func buildRightPanel() -> NSView {
        let panel = NSStackView()
        panel.orientation = .vertical; panel.spacing = 14; panel.alignment = .leading

        // ── Favorites ────────────────────────────────────────────────────
        panel.addArrangedSubview(sectionLabel("FAVORITES ★"))

        let favIDs = LayoutHistoryStore.shared.getFavoriteApps()
        let favApps = favIDs.prefix(10).compactMap { AppLibraryStore.shared.app(bundleID: $0) }
        panel.addArrangedSubview(buildIconGrid(apps: favApps, columns: 5, rows: 2, placeholder: "Add favorites in Preferences"))
        panel.setCustomSpacing(4, after: panel.arrangedSubviews.last!)

        let addFavBtn = NSButton(title: "+ Manage Favorites", target: self, action: #selector(manageFavoritesPressed))
        addFavBtn.bezelStyle = .inline; addFavBtn.font = .systemFont(ofSize: 11)
        addFavBtn.contentTintColor = .controlAccentColor
        panel.addArrangedSubview(addFavBtn)

        // ── Recommended ──────────────────────────────────────────────────
        panel.addArrangedSubview(sectionLabel("RECOMMENDED ✨"))
        let recApps = AppLibraryStore.shared.recommendations(for: template.id)
        panel.addArrangedSubview(buildIconGrid(apps: recApps, columns: 5, rows: 1, placeholder: nil))

        // ── All Apps ────────────────────────────────────────────────────
        panel.addArrangedSubview(sectionLabel("ALL APPLICATIONS 📚"))

        let sf = NSSearchField()
        sf.placeholderString = "Search apps…"
        sf.font = .systemFont(ofSize: 12)
        sf.translatesAutoresizingMaskIntoConstraints = false
        sf.action = #selector(searchChanged(_:)); sf.target = self
        searchField = sf
        sf.widthAnchor.constraint(equalToConstant: 228).isActive = true
        panel.addArrangedSubview(sf)

        let appScroll = NSScrollView()
        appScroll.hasVerticalScroller = true; appScroll.drawsBackground = false
        appScroll.translatesAutoresizingMaskIntoConstraints = false
        appScroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        appScroll.widthAnchor.constraint(equalToConstant: 232).isActive = true

        let appsListStack = NSStackView()
        appsListStack.orientation = .vertical; appsListStack.spacing = 2; appsListStack.alignment = .leading
        appsListStack.translatesAutoresizingMaskIntoConstraints = false
        appsListStack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        appScroll.documentView = appsListStack
        NSLayoutConstraint.activate([
            appsListStack.topAnchor.constraint(equalTo: appScroll.contentView.topAnchor),
            appsListStack.leadingAnchor.constraint(equalTo: appScroll.contentView.leadingAnchor),
            appsListStack.trailingAnchor.constraint(equalTo: appScroll.contentView.trailingAnchor),
            appsListStack.widthAnchor.constraint(equalTo: appScroll.contentView.widthAnchor),
        ])
        allAppsStack = appsListStack
        populateAllApps(query: "")

        panel.addArrangedSubview(appScroll)
        return panel
    }

    private func buildIconGrid(apps: [AppInfo], columns: Int, rows: Int, placeholder: String?) -> NSView {
        guard !apps.isEmpty else {
            let label = NSTextField(labelWithString: placeholder ?? "")
            label.font = .systemFont(ofSize: 11); label.textColor = .tertiaryLabelColor
            return label
        }
        let grid = NSStackView()
        grid.orientation = .vertical; grid.spacing = 6

        var current: [AppInfo] = apps.prefix(columns * rows).map { $0 }
        var rowIndex = 0
        while !current.isEmpty {
            let rowApps = Array(current.prefix(columns)); current.removeFirst(min(columns, current.count))
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal; rowStack.spacing = 8
            for app in rowApps {
                let chip = DraggableAppChip(appInfo: app)
                rowStack.addArrangedSubview(chip)
            }
            // Fill remaining slots with invisible spacers for consistent grid
            for _ in rowApps.count..<columns {
                let sp = NSView(); sp.widthAnchor.constraint(equalToConstant: 36).isActive = true
                rowStack.addArrangedSubview(sp)
            }
            grid.addArrangedSubview(rowStack)
            rowIndex += 1
            if rowIndex >= rows { break }
        }
        return grid
    }

    private func populateAllApps(query: String) {
        guard let stack = allAppsStack else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let apps = AppLibraryStore.shared.search(query).prefix(60)
        for app in apps {
            let row = AppListRow(appInfo: app)
            row.widthAnchor.constraint(equalToConstant: 220).isActive = true
            stack.addArrangedSubview(row)
        }
    }

    // MARK: Action Bar

    private func buildActionBar() -> NSView {
        let bar = NSStackView()
        bar.orientation = .horizontal; bar.spacing = 10; bar.alignment = .centerY
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        let saveBtn = NSButton(title: "💾  Save Layout", target: self, action: #selector(savePressed))
        saveBtn.bezelStyle = .rounded; saveBtn.font = .systemFont(ofSize: 12)
        bar.addArrangedSubview(saveBtn)

        let sp = NSView(); sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(sp)

        let hint = NSTextField(labelWithString: "Drag apps onto slots  ·  Click slot to search  ·  esc to cancel")
        hint.font = .systemFont(ofSize: 10); hint.textColor = .quaternaryLabelColor
        bar.addArrangedSubview(hint)

        let sp2 = NSView(); sp2.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(sp2)

        let applyBtn = NSButton(title: "Apply Layout →", target: self, action: #selector(applyPressed))
        applyBtn.bezelStyle = .rounded
        applyBtn.font = .systemFont(ofSize: 13, weight: .semibold)
        applyBtn.contentTintColor = .controlAccentColor
        bar.addArrangedSubview(applyBtn)

        return bar
    }

    // MARK: - Handle Drop

    func handleDrop(slotID: Int, sourceID: String) {
        // sourceID is either a bundleID (from app library) or a window axID (from open windows)
        // First check open windows by bundleID match
        if let win = openWindows.first(where: { $0.bundleID == sourceID }) {
            assignment[slotID] = win
        } else if let win = openWindows.first(where: { axID($0.element) == sourceID }) {
            assignment[slotID] = win
        } else {
            // App from library — check if running, else mark for launch
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: sourceID).first {
                let axApp = AXUIElementCreateApplication(running.processIdentifier)
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
                   let list = ref as? [AXUIElement], let win = list.first {
                    let info = AppLibraryStore.shared.app(bundleID: sourceID)
                    let item = LayoutWindowItem(
                        id: sourceID, element: win,
                        title: info?.name ?? sourceID,
                        appName: info?.name, bundleID: sourceID,
                        appIcon: running.icon,
                        role: WindowRoleClassifier.classify(appName: info?.name, windowTitle: nil)
                    )
                    assignment[slotID] = item
                }
            } else if let info = AppLibraryStore.shared.app(bundleID: sourceID) {
                // Not running — create a placeholder so the slot shows the app name
                let placeholder = LayoutWindowItem(
                    id: "pending-\(sourceID)",
                    element: AXUIElementCreateSystemWide(),
                    title: info.name, appName: info.name, bundleID: sourceID,
                    appIcon: info.icon,
                    role: WindowRoleClassifier.classify(appName: info.name, windowTitle: nil)
                )
                assignment[slotID] = placeholder
            }
        }
        refreshUI()
        onAssignmentChanged?(assignment)
    }

    // MARK: - Refresh

    public func refreshUI() {
        // Update slot zones
        for zone in slotZones {
            zone.assignment = assignment[zone.slotID]
            zone.setNeedsDisplay(zone.bounds)
        }
        // Update assignment list
        refreshAssignmentList()
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 10, weight: .semibold); l.textColor = .tertiaryLabelColor
        return l
    }

    private func axID(_ element: AXUIElement) -> String { "\(CFHash(element))" }

    // MARK: - Actions

    @objc private func backPressed()  { onBack?() }
    @objc private func applyPressed() { onApply?(assignment) }
    @objc private func savePressed()  { onSave?(assignment) }

    @objc private func searchChanged(_ sf: NSSearchField) {
        populateAllApps(query: sf.stringValue)
    }

    @objc private func manageFavoritesPressed() {
        // TODO: open favorites manager
    }
}

// MARK: - SlotDropZoneView

final class SlotDropZoneView: NSView {
    let slotID: Int
    let slotRect: CGRect   // normalized template rect

    var assignment: LayoutWindowItem?
    var onDrop:  ((Int, String) -> Void)?
    var onClear: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?

    private var isDropTarget = false
    private var isHovered    = false
    private var trackingArea: NSTrackingArea?

    init(slotID: Int, slotRect: CGRect) {
        self.slotID = slotID; self.slotRect = slotRect
        super.init(frame: .zero)
        wantsLayer = true
        registerForDraggedTypes([.relayAppItem])
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
    override func mouseDown(with event: NSEvent)    { onClick?(slotID) }

    override func rightMouseDown(with event: NSEvent) {
        guard assignment != nil else { return }
        let menu = NSMenu()
        let clear = NSMenuItem(title: "Clear Slot", action: #selector(clearSlot), keyEquivalent: "")
        clear.target = self; menu.addItem(clear)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func clearSlot() { onClear?(slotID) }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDropTarget = true; needsDisplay = true; return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false; needsDisplay = true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false; needsDisplay = true
        guard let str = sender.draggingPasteboard.string(forType: .relayAppItem) else { return false }
        onDrop?(slotID, str)
        return true
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { isDropTarget = false; needsDisplay = true }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds

        // Background
        let bg: NSColor
        if isDropTarget {
            bg = NSColor.controlAccentColor.withAlphaComponent(0.22)
        } else if isHovered {
            bg = NSColor.controlAccentColor.withAlphaComponent(0.08)
        } else if assignment != nil {
            bg = NSColor.controlAccentColor.withAlphaComponent(0.10)
        } else {
            bg = NSColor.controlBackgroundColor.withAlphaComponent(0.55)
        }
        bg.setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()

        // Border
        let border: NSColor = isDropTarget ? .controlAccentColor : (assignment != nil ? NSColor.controlAccentColor.withAlphaComponent(0.4) : NSColor.separatorColor)
        border.setStroke()
        let bp = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
        bp.lineWidth = isDropTarget ? 2 : 1; bp.stroke()

        if let item = assignment {
            // Assigned: show app icon + name
            if let icon = item.appIcon {
                let iconSize = min(r.width * 0.4, r.height * 0.5, 40.0)
                let ir = CGRect(x: r.midX - iconSize/2, y: r.midY, width: iconSize, height: iconSize)
                icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 0.9)
            }
            let name = item.appName ?? item.title
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(9, min(11, r.width / 10))),
                .foregroundColor: NSColor.labelColor
            ]
            let str = NSAttributedString(string: name, attributes: attrs)
            let sz = str.size()
            if sz.width < r.width - 8 {
                let iconOffset: CGFloat = (item.appIcon != nil ? min(r.width * 0.4, 40.0) : 0) + 4
                str.draw(at: CGPoint(x: r.midX - sz.width/2, y: r.minY + 6))
                _ = iconOffset // suppress warning
            }
        } else {
            // Empty: show drag hint
            let hint: NSAttributedString
            if isDropTarget {
                hint = NSAttributedString(string: "Drop Here",
                    attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                 .foregroundColor: NSColor.controlAccentColor])
            } else {
                let bigFont = NSFont.systemFont(ofSize: min(20, r.height * 0.25))
                let small   = NSFont.systemFont(ofSize: max(9, min(10, r.width / 12)))
                let text    = NSMutableAttributedString(string: "+\n",
                    attributes: [.font: bigFont, .foregroundColor: NSColor.tertiaryLabelColor])
                text.append(NSAttributedString(string: "Drag App\nor Click",
                    attributes: [.font: small, .foregroundColor: NSColor.quaternaryLabelColor]))
                hint = text
            }
            let sz = hint.size()
            hint.draw(at: CGPoint(x: r.midX - sz.width/2, y: r.midY - sz.height/2))
        }

        // Slot number badge
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        NSAttributedString(string: "\(slotID + 1)", attributes: numAttrs)
            .draw(at: CGPoint(x: r.minX + 5, y: r.maxY - 14))
    }
}

// MARK: - DraggableWindowChip  (open windows panel)

final class DraggableWindowChip: NSView, NSDraggingSource {
    let windowItem: LayoutWindowItem
    let showLabel: Bool

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(windowItem: LayoutWindowItem, showLabel: Bool, dimmed: Bool) {
        self.windowItem = windowItem; self.showLabel = showLabel
        super.init(frame: .zero)
        wantsLayer = true
        layer?.opacity = dimmed ? 0.45 : 1.0
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: showLabel ? 54 : 42).isActive = true
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

    // MARK: Drag source

    override func mouseDragged(with event: NSEvent) {
        let sourceID = windowItem.bundleID ?? "\(CFHash(windowItem.element))"
        let pbItem = NSPasteboardItem()
        pbItem.setString(sourceID, forType: .relayAppItem)

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let dragImg  = windowItem.appIcon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        dragItem.setDraggingFrame(CGRect(origin: .zero, size: CGSize(width: 32, height: 32)), contents: dragImg)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    // MARK: Draw

    override func draw(_ dirtyRect: NSRect) {
        let bg = isHovered ? NSColor.controlAccentColor.withAlphaComponent(0.12)
                           : NSColor.controlBackgroundColor.withAlphaComponent(0.6)
        bg.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        NSColor.separatorColor.withAlphaComponent(0.4).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()

        // Icon
        let iconSize: CGFloat = 24
        let iconY: CGFloat = showLabel ? bounds.height - iconSize - 6 : (bounds.height - iconSize) / 2
        if let icon = windowItem.appIcon {
            let ir = CGRect(x: (bounds.width - iconSize)/2, y: iconY, width: iconSize, height: iconSize)
            icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 0.9)
        }

        // Short label (only when multiple windows of same app)
        if showLabel {
            let raw = windowItem.title.prefix(10)
            let short = raw.count < windowItem.title.count ? "\(raw)…" : String(raw)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            let str = NSAttributedString(string: short, attributes: attrs)
            let sz = str.size()
            str.draw(at: CGPoint(x: (bounds.width - sz.width)/2, y: 4))
        }
    }
}

// MARK: - DraggableAppChip  (favorites / recommended panels)

final class DraggableAppChip: NSView, NSDraggingSource {
    let appInfo: AppInfo
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(appInfo: AppInfo) {
        self.appInfo = appInfo
        super.init(frame: .zero)
        wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 36).isActive = true
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        toolTip = appInfo.name
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // toolTip is a property, set it in init instead


    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    override func mouseEntered(with event: NSEvent) { isHovered = true;  needsDisplay = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false; needsDisplay = true }

    override func mouseDragged(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(appInfo.id, forType: .relayAppItem)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let img = appInfo.icon ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        dragItem.setDraggingFrame(CGRect(origin: .zero, size: CGSize(width: 32, height: 32)), contents: img)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        if let icon = appInfo.icon {
            let pad: CGFloat = 3
            icon.draw(in: bounds.insetBy(dx: pad, dy: pad), from: .zero, operation: .sourceOver, fraction: 0.95)
        }
    }
}

// MARK: - AppListRow  (all-apps list)

final class AppListRow: NSView, NSDraggingSource {
    let appInfo: AppInfo
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(appInfo: AppInfo) {
        self.appInfo = appInfo
        super.init(frame: .zero)
        wantsLayer = true; translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true
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

    override func mouseDragged(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(appInfo.id, forType: .relayAppItem)
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let img = appInfo.icon ?? NSImage()
        dragItem.setDraggingFrame(CGRect(origin: .zero, size: CGSize(width: 24, height: 24)), contents: img)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor.controlAccentColor.withAlphaComponent(0.1).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
        if let icon = appInfo.icon {
            let ir = CGRect(x: 4, y: (bounds.height - 18)/2, width: 18, height: 18)
            icon.draw(in: ir, from: .zero, operation: .sourceOver, fraction: 0.9)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor
        ]
        NSAttributedString(string: appInfo.name, attributes: attrs)
            .draw(at: CGPoint(x: 28, y: (bounds.height - 13) / 2))
    }
}
