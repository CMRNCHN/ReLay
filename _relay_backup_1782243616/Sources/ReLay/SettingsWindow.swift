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
        fx.material = .sidebar; fx.blendingMode = .behindWindow; fx.state = .active
        window.contentView = fx

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: fx.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: fx.bottomAnchor),
        ])

        let outer = NSStackView()
        outer.orientation = .vertical; outer.spacing = 22
        outer.edgeInsets = NSEdgeInsets(top: 56, left: 24, bottom: 28, right: 24)
        outer.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = outer
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            outer.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            outer.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])

        // ── Feel preset ─────────────────────────────────────────────────────
        let seg = NSSegmentedControl(labels: presets.map { $0.label },
                                     trackingMode: .selectOne, target: self,
                                     action: #selector(presetSelected(_:)))
        seg.selectedSegment = 1
        presetControl = seg

        outer.addArrangedSubview(settingsSection(
            title: "Feel",
            caption: "Quick presets that tune all gesture sliders at once.",
            rows: [seg]
        ))

        // ── Gesture Sensitivity ─────────────────────────────────────────────
        let gestureRows = sliderSettings.prefix(4).enumerated().map { (i, s) in
            buildSliderRow(for: s, index: i)
        }
        outer.addArrangedSubview(settingsSection(
            title: "Gesture Sensitivity",
            caption: "Fine-tune how ReLay recognises your swipes.",
            rows: Array(gestureRows)
        ))

        // ── Animation & Feedback ────────────────────────────────────────────
        let animSlider = buildSliderRow(for: sliderSettings[4], index: 4)
        let hapticsRow = buildToggleRow(
            title: "Haptic Feedback",
            description: "Feel a click when a window snaps into place.",
            key: "snapHapticsEnabled", defaultOn: true,
            switchRef: { [weak self] sw in self?.hapticsSwitch = sw }
        )
        outer.addArrangedSubview(settingsSection(
            title: "Animation & Feedback",
            caption: "Control how windows move and how they feel.",
            rows: [animSlider, hapticsRow]
        ))

        // ── Advanced ────────────────────────────────────────────────────────
        let interceptRow = buildToggleRow(
            title: "Enable Gesture Interception",
            description: "Turn off to pause all gesture tracking without quitting ReLay.",
            key: "interceptionEnabled", defaultOn: true,
            switchRef: { [weak self] sw in self?.interceptionSwitch = sw }
        )
        let warning = buildWarningBanner("Disabling interception pauses all gestures. Re-enable here or press ⌥⇧⌘K from any app.")
        outer.addArrangedSubview(settingsSection(
            title: "Advanced",
            caption: nil,
            rows: [interceptRow, warning]
        ))

        // ── Reset ───────────────────────────────────────────────────────────
        let resetBtn = NSButton(title: "Reset All Settings to Defaults", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded; resetBtn.font = .systemFont(ofSize: 13)
        outer.addArrangedSubview(resetBtn)
    }

    // MARK: - Section card builder

    private func settingsSection(title: String, caption: String?, rows: [NSView]) -> NSView {
        let wrapper = NSStackView()
        wrapper.orientation = .vertical; wrapper.spacing = 6; wrapper.alignment = .leading

        // Section title
        let hdr = NSTextField(labelWithString: title.uppercased())
        hdr.font = .systemFont(ofSize: 11, weight: .semibold)
        hdr.textColor = .secondaryLabelColor
        wrapper.addArrangedSubview(hdr)

        if let cap = caption {
            let capLabel = NSTextField(wrappingLabelWithString: cap)
            capLabel.font = .systemFont(ofSize: 12)
            capLabel.textColor = .tertiaryLabelColor
            wrapper.addArrangedSubview(capLabel)
            capLabel.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true
        }

        // Card
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        card.layer?.borderWidth = 0.5
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalTo: wrapper.widthAnchor).isActive = true

        let cardStack = NSStackView()
        cardStack.orientation = .vertical; cardStack.spacing = 0
        cardStack.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        for (i, row) in rows.enumerated() {
            let padded = paddedRow(row)
            cardStack.addArrangedSubview(padded)
            padded.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

            if i < rows.count - 1 {
                let sep = NSView()
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
                sep.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
                cardStack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
            }
        }

        wrapper.addArrangedSubview(card)
        return wrapper
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

    private func buildWarningBanner(_ text: String) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.08).cgColor
        box.layer?.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "⚠️  \(text)")
        label.font = .systemFont(ofSize: 11); label.textColor = .systemOrange
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

    // MARK: - Row builders

    private func buildSliderRow(for setting: SliderSetting, index: Int) -> NSView {
        let titleLabel = NSTextField(labelWithString: setting.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let descLabel = NSTextField(wrappingLabelWithString: setting.description)
        descLabel.font = .systemFont(ofSize: 12); descLabel.textColor = .secondaryLabelColor

        let slider = NSSlider(value: setting.stored, minValue: setting.min, maxValue: setting.max,
                              target: self, action: #selector(sliderChanged(_:)))
        slider.isContinuous = true; slider.tag = index
        sliders.append(slider)

        let minLbl = endpointLabel(setting.endpointMin, align: .left)
        let maxLbl = endpointLabel(setting.endpointMax, align: .right)
        let epRow  = NSStackView(views: [minLbl, NSView(), maxLbl])
        epRow.distribution = .fill; epRow.spacing = 4
        (epRow.arrangedSubviews[1]).setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleLabel, descLabel, slider, epRow])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
        slider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        epRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        descLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func endpointLabel(_ text: String, align: NSTextAlignment) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 10); l.textColor = .quaternaryLabelColor
        l.alignment = align; l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }

    private func buildToggleRow(title: String, description: String, key: String,
                                defaultOn: Bool, switchRef: (NSSwitch) -> Void) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let descLabel = NSTextField(wrappingLabelWithString: description)
        descLabel.font = .systemFont(ofSize: 12); descLabel.textColor = .secondaryLabelColor

        let sw = NSSwitch()
        let stored = UserDefaults.standard.object(forKey: key)
        sw.state = (stored == nil ? defaultOn : UserDefaults.standard.bool(forKey: key)) ? .on : .off
        sw.target = self; sw.action = #selector(toggleChanged(_:))
        sw.identifier = NSUserInterfaceItemIdentifier(key)
        switchRef(sw)

        let labelStack = NSStackView(views: [titleLabel, descLabel])
        labelStack.orientation = .vertical; labelStack.alignment = .leading; labelStack.spacing = 2
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        labelStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        descLabel.widthAnchor.constraint(lessThanOrEqualTo: labelStack.widthAnchor).isActive = true

        let row = NSStackView(views: [labelStack, sw])
        row.distribution = .fill; row.alignment = .centerY; row.spacing = 16
        return row
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

    @objc private func resetAll() {
        for (i, setting) in sliderSettings.enumerated() {
            sliders[i].doubleValue = setting.defaultValue
            UserDefaults.standard.set(setting.defaultValue, forKey: setting.key)
        }
        hapticsSwitch?.state = .on
        UserDefaults.standard.set(true, forKey: "snapHapticsEnabled")
        presetControl?.selectedSegment = 1
        postSettingsChanged()
    }

    private func postSettingsChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("ReLaySettingsChanged"), object: nil)
    }
}
