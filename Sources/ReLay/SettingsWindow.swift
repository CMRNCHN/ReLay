import AppKit
import ReLayCore

// MARK: - Settings Tabs

private enum SettingsTab: Int, CaseIterable {
    case general
    case gestures
    case animation
    case advanced

    var title: String {
        switch self {
        case .general:   return "General"
        case .gestures:  return "Gestures"
        case .animation: return "Animation"
        case .advanced:  return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general:   return "gearshape"
        case .gestures:  return "hand.draw"
        case .animation: return "sparkles"
        case .advanced:  return "slider.horizontal.3"
        }
    }

    var headline: String {
        switch self {
        case .general:   return "General"
        case .gestures:  return "Gesture Sensitivity"
        case .animation: return "Animation & Feedback"
        case .advanced:  return "Advanced"
        }
    }

    var caption: String? {
        switch self {
        case .general:
            return "Control whether ReLay is active and manage system permissions."
        case .gestures:
            return "Fine-tune how ReLay recognises your title-bar swipes."
        case .animation:
            return "Snap motion, destination preview, and haptic feedback — all in one place."
        case .advanced:
            return "Reset preferences or pause gesture interception."
        }
    }
}

// MARK: - Slider Definition

private struct SliderSetting {
    let key: String
    let title: String
    let description: String
    let min: Double
    let max: Double
    let defaultValue: Double
    let endpointMin: String
    let endpointMax: String

    var stored: Double {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? v : defaultValue
    }
}

// MARK: - Feel Presets

private struct FeelPreset {
    let label: String
    let values: [String: Double]
}

// MARK: - Settings Window

final class SettingsWindowController: NSWindowController {

    private let gestureSliders: [SliderSetting] = [
        SliderSetting(
            key: ReLaySettings.Key.lockThreshold,
            title: "Gesture Lock",
            description: "How quickly ReLay commits to a swipe direction.",
            min: 5, max: 50, defaultValue: ReLaySettings.Default.lockThreshold,
            endpointMin: "Responsive", endpointMax: "Deliberate"
        ),
        SliderSetting(
            key: ReLaySettings.Key.cancelThreshold,
            title: "Diagonal Tolerance",
            description: "How much sideways drift is allowed before a swipe is ignored.",
            min: 10, max: 60, defaultValue: ReLaySettings.Default.cancelThreshold,
            endpointMin: "Strict", endpointMax: "Forgiving"
        ),
        SliderSetting(
            key: ReLaySettings.Key.actionThreshold,
            title: "Swipe Distance",
            description: "How far you need to swipe before a window moves.",
            min: 30, max: 250, defaultValue: ReLaySettings.Default.actionThreshold,
            endpointMin: "Short swipe", endpointMax: "Long swipe"
        ),
    ]

    private let animationSlider = SliderSetting(
        key: ReLaySettings.Key.snapDuration,
        title: "Snap Duration",
        description: "How long the settle animation lasts after a successful swipe.",
        min: 0.08, max: 0.55, defaultValue: ReLaySettings.Default.snapDuration,
        endpointMin: "Instant", endpointMax: "Cinematic"
    )

    private let animationPresets: [FeelPreset] = [
        FeelPreset(label: "Instant", values: [
            ReLaySettings.Key.snapDuration: 0.10,
        ]),
        FeelPreset(label: "Smooth", values: [
            ReLaySettings.Key.snapDuration: 0.28,
        ]),
        FeelPreset(label: "Cinematic", values: [
            ReLaySettings.Key.snapDuration: 0.45,
        ]),
    ]

    private let presets: [FeelPreset] = [
        FeelPreset(label: "Careful", values: [
            ReLaySettings.Key.lockThreshold: 35,
            ReLaySettings.Key.cancelThreshold: 45,
            ReLaySettings.Key.actionThreshold: 160,
            ReLaySettings.Key.snapDuration: 0.35,
        ]),
        FeelPreset(label: "Balanced", values: [
            ReLaySettings.Key.lockThreshold: 20,
            ReLaySettings.Key.cancelThreshold: 25,
            ReLaySettings.Key.actionThreshold: 100,
            ReLaySettings.Key.snapDuration: 0.28,
        ]),
        FeelPreset(label: "Snappy", values: [
            ReLaySettings.Key.lockThreshold: 8,
            ReLaySettings.Key.cancelThreshold: 12,
            ReLaySettings.Key.actionThreshold: 45,
            ReLaySettings.Key.snapDuration: 0.12,
        ]),
    ]

    private var selectedTab: SettingsTab = .animation
    private var sidebarButtons: [SettingsTab: SidebarItemView] = [:]
    private var contentHost: NSView!
    private var sliders: [NSSlider] = []
    private var sliderKeys: [String] = []
    private var presetControl: NSSegmentedControl?
    private var animationPresetControl: NSSegmentedControl?
    private var hapticsSwitch: NSSwitch?
    private var interceptionSwitch: NSSwitch?
    private var previewSwitch: NSSwitch?
    private var animateSwitch: NSSwitch?
    private var statusBadge: NSTextField?

    // MARK: - Init

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "ReLay Settings"
        panel.titlebarAppearsTransparent = true
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 640, height: 440)
        self.init(window: panel)
        buildUI()
        showTab(.animation)
    }

    // MARK: - Layout

    private func buildUI() {
        guard let window else { return }

        let chrome = NSVisualEffectView()
        chrome.material = .sidebar
        chrome.blendingMode = .behindWindow
        chrome.state = .active
        window.contentView = chrome

        let split = NSStackView()
        split.orientation = .horizontal
        split.spacing = 0
        split.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(split)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 28),
            split.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])

        split.addArrangedSubview(buildSidebar())
        split.addArrangedSubview(buildDivider())
        split.addArrangedSubview(buildContentArea())
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .underWindowBackground
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.widthAnchor.constraint(equalToConstant: 196).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
        ])

        let brand = NSTextField(labelWithString: "ReLay")
        brand.font = .systemFont(ofSize: 15, weight: .semibold)
        brand.textColor = .labelColor
        stack.addArrangedSubview(brand)
        stack.setCustomSpacing(14, after: brand)

        for tab in SettingsTab.allCases {
            let item = SidebarItemView(tab: tab)
            item.target = self
            item.action = #selector(tabSelected(_:))
            sidebarButtons[tab] = item
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }

        return sidebar
    }

    private func buildDivider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    private func buildContentArea() -> NSView {
        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        contentHost = host
        return host
    }

    // MARK: - Tab Content

    private func showTab(_ tab: SettingsTab) {
        selectedTab = tab
        for (key, button) in sidebarButtons {
            button.isSelected = (key == tab)
        }

        if tab == .gestures || tab == .animation {
            sliders.removeAll()
            sliderKeys.removeAll()
        }

        contentHost.subviews.forEach { $0.removeFromSuperview() }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: contentHost.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 20
        outer.alignment = .leading
        outer.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 28, right: 28)
        outer.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = outer

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            outer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        outer.addArrangedSubview(buildPageHeader(tab))
        paneContent(for: tab).forEach { outer.addArrangedSubview($0) }
    }

    private func buildPageHeader(_ tab: SettingsTab) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        let title = NSTextField(labelWithString: tab.headline)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)

        if let caption = tab.caption {
            let cap = NSTextField(wrappingLabelWithString: caption)
            cap.font = .systemFont(ofSize: 13)
            cap.textColor = .secondaryLabelColor
            cap.preferredMaxLayoutWidth = 440
            stack.addArrangedSubview(cap)
            cap.widthAnchor.constraint(equalToConstant: 440).isActive = true
        }

        return stack
    }

    private func paneContent(for tab: SettingsTab) -> [NSView] {
        switch tab {
        case .general:   return [generalPane()]
        case .gestures:  return gesturesPane()
        case .animation: return animationPane()
        case .advanced:  return advancedPane()
        }
    }

    // MARK: - Panes

    private func generalPane() -> NSView {
        let status = NSTextField(labelWithString: ReLaySettings.interceptionEnabled ? "Active" : "Paused")
        status.font = .systemFont(ofSize: 12, weight: .semibold)
        status.textColor = ReLaySettings.interceptionEnabled ? .systemGreen : .systemOrange
        statusBadge = status

        let statusRow = NSStackView(views: [
            NSTextField(labelWithString: "Status"),
            NSView(),
            status,
        ])
        statusRow.distribution = .fill
        statusRow.alignment = .centerY

        let interceptRow = buildToggleRow(
            title: "Enable Gesture Interception",
            description: "Turn off to pause all gesture tracking without quitting ReLay.",
            key: ReLaySettings.Key.interceptionEnabled,
            defaultOn: ReLaySettings.Default.interceptionEnabled,
            switchRef: { [weak self] sw in
                self?.interceptionSwitch = sw
                sw.target = self
                sw.action = #selector(self?.interceptionToggled(_:))
            }
        )

        let accessibilityBtn = NSButton(title: "Open Accessibility Settings…", target: self, action: #selector(openAccessibilitySettings))
        accessibilityBtn.bezelStyle = .rounded

        return cardBody(rows: [
            statusRow,
            interceptRow,
            accessibilityBtn,
        ])
    }

    private func gesturesPane() -> [NSView] {
        let seg = NSSegmentedControl(
            labels: presets.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(presetSelected(_:))
        )
        seg.selectedSegment = 1
        presetControl = seg

        let sliderRows = gestureSliders.enumerated().map { index, setting in
            buildSliderRow(for: setting, index: index)
        }

        return [
            settingsCard(title: "Feel Preset", caption: "Quick presets that tune all gesture sliders at once.", rows: [seg]),
            settingsCard(title: "Fine Tuning", caption: nil, rows: sliderRows),
        ]
    }

    private func animationPane() -> [NSView] {
        let motionSeg = NSSegmentedControl(
            labels: animationPresets.map(\.label),
            trackingMode: .selectOne,
            target: self,
            action: #selector(animationPresetSelected(_:))
        )
        motionSeg.selectedSegment = matchedAnimationPresetIndex()
        animationPresetControl = motionSeg

        let durationRow = buildSliderRow(for: animationSlider, index: 0)

        let animateRow = buildToggleRow(
            title: "Animate Snap Settle",
            description: "Fade the destination hint smoothly when a swipe commits.",
            key: ReLaySettings.Key.snapAnimateEnabled,
            defaultOn: ReLaySettings.Default.snapAnimateEnabled,
            switchRef: { [weak self] sw in self?.animateSwitch = sw }
        )

        let previewRow = buildToggleRow(
            title: "Show Destination Preview",
            description: "While swiping, show a soft silhouette of where the window will land. Off by default — the old traveling ghost is gone.",
            key: ReLaySettings.Key.snapPreviewEnabled,
            defaultOn: ReLaySettings.Default.snapPreviewEnabled,
            switchRef: { [weak self] sw in self?.previewSwitch = sw }
        )

        let hapticsRow = buildToggleRow(
            title: "Haptic Feedback",
            description: "Feel a click when a window snaps into place.",
            key: ReLaySettings.Key.snapHapticsEnabled,
            defaultOn: ReLaySettings.Default.snapHapticsEnabled,
            switchRef: { [weak self] sw in self?.hapticsSwitch = sw }
        )

        return [
            settingsCard(
                title: "Motion",
                caption: "How quickly windows settle after a successful snap.",
                rows: [motionSeg, durationRow, animateRow]
            ),
            settingsCard(
                title: "Destination Preview",
                caption: "Optional on-screen hint during a title-bar swipe — not a second window.",
                rows: [previewRow]
            ),
            settingsCard(
                title: "Feedback",
                caption: nil,
                rows: [hapticsRow]
            ),
        ]
    }

    private func matchedAnimationPresetIndex() -> Int {
        let duration = ReLaySettings.snapDuration
        if let idx = animationPresets.firstIndex(where: {
            abs(($0.values[ReLaySettings.Key.snapDuration] ?? -1) - duration) < 0.02
        }) {
            return idx
        }
        return -1
    }

    private func advancedPane() -> [NSView] {
        let warning = buildWarningBanner(
            "Disabling interception pauses all gestures. Re-enable in General or press ⌥⇧⌘K from any app."
        )
        let resetBtn = NSButton(title: "Reset All Settings to Defaults", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded
        resetBtn.font = .systemFont(ofSize: 13)

        return [
            settingsCard(title: "Emergency Stop", caption: nil, rows: [warning]),
            resetBtn,
        ]
    }

    // MARK: - Card Builders

    private func settingsCard(title: String? = nil, caption: String? = nil, rows: [NSView]) -> NSView {
        let wrapper = NSStackView()
        wrapper.orientation = .vertical
        wrapper.spacing = 8
        wrapper.alignment = .leading

        if let title {
            let hdr = NSTextField(labelWithString: title.uppercased())
            hdr.font = .systemFont(ofSize: 11, weight: .semibold)
            hdr.textColor = .secondaryLabelColor
            wrapper.addArrangedSubview(hdr)
        }

        if let caption {
            let cap = NSTextField(wrappingLabelWithString: caption)
            cap.font = .systemFont(ofSize: 12)
            cap.textColor = .tertiaryLabelColor
            cap.preferredMaxLayoutWidth = 420
            wrapper.addArrangedSubview(cap)
            cap.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }

        wrapper.addArrangedSubview(cardBody(rows: rows))
        return wrapper
    }

    private func cardBody(rows: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        card.layer?.borderWidth = 0.5
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: 440).isActive = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        for (index, row) in rows.enumerated() {
            let padded = paddedRow(row)
            stack.addArrangedSubview(padded)
            padded.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

            if index < rows.count - 1 {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                stack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        return card
    }

    private func paddedRow(_ view: NSView) -> NSView {
        let pad = NSView()
        pad.translatesAutoresizingMaskIntoConstraints = false
        view.translatesAutoresizingMaskIntoConstraints = false
        pad.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: pad.leadingAnchor, constant: 16),
            view.trailingAnchor.constraint(equalTo: pad.trailingAnchor, constant: -16),
            view.topAnchor.constraint(equalTo: pad.topAnchor, constant: 12),
            view.bottomAnchor.constraint(equalTo: pad.bottomAnchor, constant: -12),
        ])
        return pad
    }

    private func buildSliderRow(for setting: SliderSetting, index: Int) -> NSView {
        let titleLabel = NSTextField(labelWithString: setting.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let descLabel = NSTextField(wrappingLabelWithString: setting.description)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor

        let slider = NSSlider(
            value: setting.stored,
            minValue: setting.min,
            maxValue: setting.max,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        slider.isContinuous = true
        slider.tag = index
        sliders.append(slider)
        sliderKeys.append(setting.key)

        let minLbl = endpointLabel(setting.endpointMin, align: .left)
        let maxLbl = endpointLabel(setting.endpointMax, align: .right)
        let epRow = NSStackView(views: [minLbl, NSView(), maxLbl])
        epRow.distribution = .fill

        let stack = NSStackView(views: [titleLabel, descLabel, slider, epRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        slider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        epRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        descLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func endpointLabel(_ text: String, align: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .quaternaryLabelColor
        label.alignment = align
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func buildToggleRow(
        title: String,
        description: String,
        key: String,
        defaultOn: Bool,
        switchRef: (NSSwitch) -> Void
    ) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let descLabel = NSTextField(wrappingLabelWithString: description)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor

        let toggle = NSSwitch()
        let stored = UserDefaults.standard.object(forKey: key)
        toggle.state = (stored == nil ? defaultOn : UserDefaults.standard.bool(forKey: key)) ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggleChanged(_:))
        toggle.identifier = NSUserInterfaceItemIdentifier(key)
        switchRef(toggle)

        let labelStack = NSStackView(views: [titleLabel, descLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labelStack, toggle])
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func buildWarningBanner(_ text: String) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        box.layer?.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemOrange
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])
        return box
    }

    // MARK: - Actions

    @objc private func tabSelected(_ sender: SidebarItemView) {
        showTab(sender.tab)
    }

    @objc private func presetSelected(_ seg: NSSegmentedControl) {
        let preset = presets[seg.selectedSegment]
        applyPresetValues(preset.values)
    }

    @objc private func animationPresetSelected(_ seg: NSSegmentedControl) {
        guard seg.selectedSegment >= 0, seg.selectedSegment < animationPresets.count else { return }
        applyPresetValues(animationPresets[seg.selectedSegment].values)
    }

    private func applyPresetValues(_ values: [String: Double]) {
        for (key, value) in values {
            ReLaySettings.set(value, forKey: key)
            if let idx = sliderKeys.firstIndex(of: key), idx < sliders.count {
                sliders[idx].doubleValue = value
            }
        }
    }

    @objc private func sliderChanged(_ slider: NSSlider) {
        guard slider.tag < sliderKeys.count else { return }
        let key = sliderKeys[slider.tag]
        ReLaySettings.set(slider.doubleValue, forKey: key)
        if key == ReLaySettings.Key.snapDuration {
            animationPresetControl?.selectedSegment = matchedAnimationPresetIndex()
        } else {
            presetControl?.selectedSegment = -1
        }
    }

    @objc private func toggleChanged(_ sw: NSSwitch) {
        guard let key = sw.identifier?.rawValue else { return }
        ReLaySettings.set(sw.state == .on, forKey: key)
    }

    @objc private func interceptionToggled(_ sw: NSSwitch) {
        toggleChanged(sw)
        statusBadge?.stringValue = sw.state == .on ? "Active" : "Paused"
        statusBadge?.textColor = sw.state == .on ? .systemGreen : .systemOrange
        NotificationCenter.default.post(
            name: ReLaySettings.interceptionToggled,
            object: nil,
            userInfo: ["enabled": sw.state == .on]
        )
    }

    @objc private func resetAll() {
        ReLaySettings.resetAll()

        for (index, key) in sliderKeys.enumerated() where index < sliders.count {
            switch key {
            case ReLaySettings.Key.lockThreshold:
                sliders[index].doubleValue = ReLaySettings.Default.lockThreshold
            case ReLaySettings.Key.cancelThreshold:
                sliders[index].doubleValue = ReLaySettings.Default.cancelThreshold
            case ReLaySettings.Key.actionThreshold:
                sliders[index].doubleValue = ReLaySettings.Default.actionThreshold
            case ReLaySettings.Key.snapDuration:
                sliders[index].doubleValue = ReLaySettings.Default.snapDuration
            default:
                break
            }
        }

        hapticsSwitch?.state = .on
        interceptionSwitch?.state = .on
        previewSwitch?.state = ReLaySettings.Default.snapPreviewEnabled ? .on : .off
        animateSwitch?.state = ReLaySettings.Default.snapAnimateEnabled ? .on : .off
        presetControl?.selectedSegment = 1
        animationPresetControl?.selectedSegment = matchedAnimationPresetIndex()
        statusBadge?.stringValue = "Active"
        statusBadge?.textColor = .systemGreen

        NotificationCenter.default.post(
            name: ReLaySettings.interceptionToggled,
            object: nil,
            userInfo: ["enabled": true]
        )
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Sidebar Item

private final class SidebarItemView: NSControl {
    let tab: SettingsTab
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    init(tab: SettingsTab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let bg = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18)
            : NSColor.clear
        bg.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 6, yRadius: 6).fill()

        let icon = NSImage(
            systemSymbolName: tab.icon,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular),
            .foregroundColor: isSelected ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let title = NSAttributedString(string: "  \(tab.title)", attributes: attrs)

        if let icon {
            let iconRect = NSRect(x: 12, y: (bounds.height - 14) / 2, width: 14, height: 14)
            icon.draw(in: iconRect)
        }
        title.draw(at: NSPoint(x: 30, y: (bounds.height - 16) / 2))
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }
}
