import AppKit
import Foundation

final class SettingsWindowController: NSWindowController {

    // MARK: - Slider Setting Definition

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

    private let sliderSettings: [SliderSetting] = [
        SliderSetting(
            key: "lockThreshold",
            title: "Gesture Sensitivity",
            description: "How quickly ReLay commits to a swipe direction.",
            min: 5, max: 50, defaultValue: 20,
            endpointMin: "Responsive", endpointMax: "Deliberate"
        ),
        SliderSetting(
            key: "cancelThreshold",
            title: "Diagonal Tolerance",
            description: "How much sideways drift is allowed before a swipe is ignored.",
            min: 10, max: 60, defaultValue: 25,
            endpointMin: "Strict", endpointMax: "Forgiving"
        ),
        SliderSetting(
            key: "actionThreshold",
            title: "Swipe Distance",
            description: "How far you need to swipe before a window moves.",
            min: 30, max: 250, defaultValue: 100,
            endpointMin: "Short swipe", endpointMax: "Long swipe"
        ),
        SliderSetting(
            key: "flickVelocity",
            title: "Flick Sensitivity",
            description: "How fast a flick must be to snap a window without a full swipe.",
            min: 200, max: 2000, defaultValue: 800,
            endpointMin: "Easy flick", endpointMax: "Hard flick"
        ),
        SliderSetting(
            key: "snapDuration",
            title: "Snap Speed",
            description: "How fast windows animate into position.",
            min: 0.08, max: 0.45, defaultValue: 0.22,
            endpointMin: "Instant", endpointMax: "Smooth"
        ),
    ]

    private struct Preset {
        let label: String
        let values: [String: Double]
    }

    private let presets: [Preset] = [
        Preset(label: "Careful",  values: ["lockThreshold": 35, "cancelThreshold": 45, "actionThreshold": 160, "flickVelocity": 1400, "snapDuration": 0.35]),
        Preset(label: "Balanced", values: ["lockThreshold": 20, "cancelThreshold": 25, "actionThreshold": 100, "flickVelocity": 800,  "snapDuration": 0.22]),
        Preset(label: "Snappy",   values: ["lockThreshold": 8,  "cancelThreshold": 12, "actionThreshold": 45,  "flickVelocity": 350,  "snapDuration": 0.10]),
    ]

    // MARK: - State

    private var sliders: [NSSlider] = []
    private var presetControl: NSSegmentedControl?
    private var hapticsSwitch: NSSwitch?
    private var centerSnapSwitch: NSSwitch?
    private var upSwipePopup: NSPopUpButton?
    private var downSwipePopup: NSPopUpButton?
    private var interceptionSwitch: NSSwitch?

    // MARK: - Init

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Relay"
        panel.titlebarAppearsTransparent = true
        panel.center()
        panel.isReleasedWhenClosed = false
        self.init(window: panel)
        buildUI()
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }

        let fx = NSVisualEffectView()
        fx.material = .sidebar
        fx.blendingMode = .behindWindow
        fx.state = .active
        window.contentView = fx

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: fx.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 0
        outer.edgeInsets = NSEdgeInsets(top: 52, left: 28, bottom: 24, right: 28)
        outer.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = outer
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            // Bottom is intentionally not pinned — lets the stack grow and scroll.
            outer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        // Preset strip
        let seg = NSSegmentedControl(labels: presets.map { $0.label }, trackingMode: .selectOne, target: self, action: #selector(presetSelected(_:)))
        seg.selectedSegment = 1 // Balanced
        presetControl = seg
        outer.addArrangedSubview(seg)
        outer.setCustomSpacing(20, after: seg)

        // Slider rows
        for (i, setting) in sliderSettings.enumerated() {
            let sep = NSBox(); sep.boxType = .separator
            outer.addArrangedSubview(sep)
            outer.setCustomSpacing(0, after: sep)
            let row = buildSliderRow(for: setting, index: i)
            outer.addArrangedSubview(row)
            outer.setCustomSpacing(0, after: row)
        }

        // Section: Behavior toggles
        let sep1 = NSBox(); sep1.boxType = .separator
        outer.addArrangedSubview(sep1)
        outer.setCustomSpacing(16, after: sep1)

        outer.addArrangedSubview(buildToggleRow(
            title: "Snap Haptics",
            description: "Feel a click when a window snaps into place.",
            key: "snapHapticsEnabled",
            defaultOn: true,
            switchRef: { [weak self] sw in self?.hapticsSwitch = sw }
        ))
        outer.setCustomSpacing(12, after: outer.arrangedSubviews.last!)

        outer.addArrangedSubview(buildToggleRow(
            title: "Center Snap",
            description: "Swipe left or right from an unmanaged window to land in the center first.",
            key: "centerSnapEnabled",
            defaultOn: false,
            switchRef: { [weak self] sw in self?.centerSnapSwitch = sw }
        ))
        outer.setCustomSpacing(16, after: outer.arrangedSubviews.last!)

        // Swipe Actions
        let sep2 = NSBox(); sep2.boxType = .separator
        outer.addArrangedSubview(sep2)
        outer.setCustomSpacing(16, after: sep2)
        outer.addArrangedSubview(buildSwipeActionsRow())
        outer.setCustomSpacing(20, after: outer.arrangedSubviews.last!)

        // Section: Developer / Advanced
        let sep3 = NSBox(); sep3.boxType = .separator
        outer.addArrangedSubview(sep3)
        outer.setCustomSpacing(16, after: sep3)

        let devHeader = NSTextField(labelWithString: "Advanced")
        devHeader.font = .systemFont(ofSize: 11, weight: .semibold)
        devHeader.textColor = .tertiaryLabelColor
        outer.addArrangedSubview(devHeader)
        outer.setCustomSpacing(10, after: devHeader)

        outer.addArrangedSubview(buildToggleRow(
            title: "Enable Gesture Interception",
            description: "When off, ReLay stops watching for gestures entirely. All title-bar swipes and Layout Exposé triggers are paused until you turn this back on. The app stays open in the menu bar so you can re-enable it without relaunching.",
            key: "interceptionEnabled",
            defaultOn: true,
            switchRef: { [weak self] sw in self?.interceptionSwitch = sw }
        ))
        outer.setCustomSpacing(8, after: outer.arrangedSubviews.last!)

        // Warning callout
        let warningBox = NSView()
        warningBox.wantsLayer = true
        warningBox.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        warningBox.layer?.cornerRadius = 8
        warningBox.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.25).cgColor
        warningBox.layer?.borderWidth = 1
        warningBox.translatesAutoresizingMaskIntoConstraints = false

        let warningLabel = NSTextField(wrappingLabelWithString: "⚠️  Disabling interception will make ReLay invisible to your gestures. Re-enable it here or use the ⌥⇧⌘K shortcut from any app.")
        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.textColor = NSColor.systemOrange
        warningLabel.translatesAutoresizingMaskIntoConstraints = false
        warningBox.addSubview(warningLabel)
        NSLayoutConstraint.activate([
            warningLabel.leadingAnchor.constraint(equalTo: warningBox.leadingAnchor, constant: 10),
            warningLabel.trailingAnchor.constraint(equalTo: warningBox.trailingAnchor, constant: -10),
            warningLabel.topAnchor.constraint(equalTo: warningBox.topAnchor, constant: 8),
            warningLabel.bottomAnchor.constraint(equalTo: warningBox.bottomAnchor, constant: -8),
        ])
        outer.addArrangedSubview(warningBox)
        warningBox.widthAnchor.constraint(equalTo: outer.widthAnchor, constant: -56).isActive = true
        outer.setCustomSpacing(20, after: warningBox)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        outer.addArrangedSubview(spacer)
        outer.setCustomSpacing(12, after: spacer)

        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded
        resetBtn.font = .systemFont(ofSize: 13)
        outer.addArrangedSubview(resetBtn)
    }

    private func buildSliderRow(for setting: SliderSetting, index: Int) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: setting.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let descLabel = NSTextField(labelWithString: setting.description)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let slider = NSSlider(value: setting.stored, minValue: setting.min, maxValue: setting.max, target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true
        slider.tag = index
        sliders.append(slider)

        let minLbl = NSTextField(labelWithString: setting.endpointMin)
        minLbl.font = .systemFont(ofSize: 10)
        minLbl.textColor = .quaternaryLabelColor
        minLbl.setContentHuggingPriority(.required, for: .horizontal)

        let maxLbl = NSTextField(labelWithString: setting.endpointMax)
        maxLbl.font = .systemFont(ofSize: 10)
        maxLbl.textColor = .quaternaryLabelColor
        maxLbl.alignment = .right
        maxLbl.setContentHuggingPriority(.required, for: .horizontal)

        let endpointRow = NSStackView(views: [minLbl, NSView(), maxLbl])
        endpointRow.distribution = .fill
        endpointRow.spacing = 4
        (endpointRow.arrangedSubviews[1] as NSView).setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, descLabel, slider, endpointRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            slider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            endpointRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            descLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return container
    }

    private func buildToggleRow(title: String, description: String, key: String, defaultOn: Bool, switchRef: (NSSwitch) -> Void) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let sw = NSSwitch()
        let storedObj = UserDefaults.standard.object(forKey: key)
        sw.state = (storedObj == nil ? defaultOn : UserDefaults.standard.bool(forKey: key)) ? .on : .off
        sw.target = self
        sw.action = #selector(toggleChanged(_:))
        sw.tag = key.hashValue
        // Store key on the switch via identifier
        sw.identifier = NSUserInterfaceItemIdentifier(key)
        switchRef(sw)

        let labelStack = NSStackView(views: [titleLabel, descLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labelStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [labelStack, sw])
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            descLabel.widthAnchor.constraint(lessThanOrEqualTo: labelStack.widthAnchor),
        ])

        return container
    }

    private func buildSwipeActionsRow() -> NSView {
        let header = NSTextField(labelWithString: "Swipe Actions")
        header.font = .systemFont(ofSize: 13, weight: .semibold)

        let descLabel = NSTextField(labelWithString: "What happens when you swipe up or down on a window title bar.")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.lineBreakMode = .byWordWrapping
        descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let upLabel = NSTextField(labelWithString: "↑  Up swipe")
        upLabel.font = .systemFont(ofSize: 12)
        upLabel.setContentHuggingPriority(.required, for: .horizontal)

        let upPopup = NSPopUpButton()
        upPopup.addItems(withTitles: ["Fullscreen", "Center", "Nothing"])
        let upStored = UserDefaults.standard.string(forKey: "upSwipeAction") ?? "fullscreen"
        switch upStored {
        case "center":  upPopup.selectItem(withTitle: "Center")
        case "nothing": upPopup.selectItem(withTitle: "Nothing")
        default:        upPopup.selectItem(withTitle: "Fullscreen")
        }
        upPopup.target = self
        upPopup.action = #selector(upSwipeChanged(_:))
        upSwipePopup = upPopup

        let downLabel = NSTextField(labelWithString: "↓  Down swipe")
        downLabel.font = .systemFont(ofSize: 12)
        downLabel.setContentHuggingPriority(.required, for: .horizontal)

        let downPopup = NSPopUpButton()
        downPopup.addItems(withTitles: ["Minimize", "Center", "Nothing"])
        let downStored = UserDefaults.standard.string(forKey: "downSwipeAction") ?? "minimize"
        switch downStored {
        case "center":  downPopup.selectItem(withTitle: "Center")
        case "nothing": downPopup.selectItem(withTitle: "Nothing")
        default:        downPopup.selectItem(withTitle: "Minimize")
        }
        downPopup.target = self
        downPopup.action = #selector(downSwipeChanged(_:))
        downSwipePopup = downPopup

        let upRow = NSStackView(views: [upLabel, upPopup])
        upRow.spacing = 8
        upRow.alignment = .centerY

        let downRow = NSStackView(views: [downLabel, downPopup])
        downRow.spacing = 8
        downRow.alignment = .centerY

        let popupStack = NSStackView(views: [upRow, downRow])
        popupStack.orientation = .vertical
        popupStack.alignment = .leading
        popupStack.spacing = 8

        let container = NSStackView(views: [header, descLabel, popupStack])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        descLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor).isActive = true

        return container
    }

    // MARK: - Actions

    @objc private func presetSelected(_ seg: NSSegmentedControl) {
        let preset = presets[seg.selectedSegment]
        for (i, setting) in sliderSettings.enumerated() {
            if let v = preset.values[setting.key] {
                sliders[i].doubleValue = v
                UserDefaults.standard.set(v, forKey: setting.key)
            }
        }
        postSettingsChanged()
    }

    @objc private func sliderChanged(_ slider: NSSlider) {
        UserDefaults.standard.set(slider.doubleValue, forKey: sliderSettings[slider.tag].key)
        presetControl?.selectedSegment = -1
        postSettingsChanged()
    }

    @objc private func toggleChanged(_ sw: NSSwitch) {
        guard let key = sw.identifier?.rawValue else { return }
        UserDefaults.standard.set(sw.state == .on, forKey: key)
        postSettingsChanged()
        // Interception toggle needs special handling beyond the settings notification
        if key == "interceptionEnabled" {
            NotificationCenter.default.post(
                name: NSNotification.Name("ReLayInterceptionToggled"),
                object: nil,
                userInfo: ["enabled": sw.state == .on]
            )
        }
    }

    @objc private func upSwipeChanged(_ popup: NSPopUpButton) {
        let map = ["Fullscreen": "fullscreen", "Center": "center", "Nothing": "nothing"]
        UserDefaults.standard.set(map[popup.titleOfSelectedItem ?? ""] ?? "fullscreen", forKey: "upSwipeAction")
        postSettingsChanged()
    }

    @objc private func downSwipeChanged(_ popup: NSPopUpButton) {
        let map = ["Minimize": "minimize", "Center": "center", "Nothing": "nothing"]
        UserDefaults.standard.set(map[popup.titleOfSelectedItem ?? ""] ?? "minimize", forKey: "downSwipeAction")
        postSettingsChanged()
    }

    @objc private func resetAll() {
        for (i, setting) in sliderSettings.enumerated() {
            sliders[i].doubleValue = setting.defaultValue
            UserDefaults.standard.set(setting.defaultValue, forKey: setting.key)
        }
        hapticsSwitch?.state = .on
        UserDefaults.standard.set(true, forKey: "snapHapticsEnabled")
        centerSnapSwitch?.state = .off
        UserDefaults.standard.set(false, forKey: "centerSnapEnabled")
        upSwipePopup?.selectItem(withTitle: "Fullscreen")
        UserDefaults.standard.set("fullscreen", forKey: "upSwipeAction")
        downSwipePopup?.selectItem(withTitle: "Minimize")
        UserDefaults.standard.set("minimize", forKey: "downSwipeAction")
        presetControl?.selectedSegment = 1
        postSettingsChanged()
    }

    private func postSettingsChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("ReLaySettingsChanged"), object: nil)
    }
}
