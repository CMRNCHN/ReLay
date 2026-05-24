import AppKit
import Foundation

final class SettingsWindowController: NSWindowController {

    // MARK: - Definitions

    private struct Setting {
        let key: String
        let title: String
        let description: String
        let min: Double
        let max: Double
        let defaultValue: Double
        let unit: String

        var stored: Double {
            let v = UserDefaults.standard.double(forKey: key)
            return v > 0 ? v : defaultValue
        }
    }

    private let settings: [Setting] = [
        Setting(
            key: "lockThreshold",
            title: "Direction Lock",
            description: "How far to move before Relay picks a direction. Lower = more responsive.",
            min: 5, max: 50, defaultValue: 20, unit: "pt"
        ),
        Setting(
            key: "cancelThreshold",
            title: "Diagonal Forgiveness",
            description: "How diagonal a swipe can be before Relay ignores it.",
            min: 10, max: 60, defaultValue: 25, unit: "pt"
        ),
        Setting(
            key: "actionThreshold",
            title: "Snap Distance",
            description: "How far to swipe before a window snaps into place.",
            min: 30, max: 250, defaultValue: 100, unit: "pt"
        ),
        Setting(
            key: "flickVelocity",
            title: "Quick Flick Speed",
            description: "Flick faster than this to snap instantly without reaching the full distance.",
            min: 200, max: 2000, defaultValue: 800, unit: "pt/s"
        )
    ]

    // MARK: - State

    private var sliders: [NSSlider] = []
    private var valueLabels: [NSTextField] = []

    // MARK: - Init

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 410),
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

        let outer = NSStackView()
        outer.orientation = .vertical
        outer.spacing = 0
        outer.edgeInsets = NSEdgeInsets(top: 52, left: 28, bottom: 24, right: 28)
        outer.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(outer)
        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: fx.topAnchor),
            outer.leadingAnchor.constraint(equalTo: fx.leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: fx.bottomAnchor)
        ])

        for (i, setting) in settings.enumerated() {
            if i > 0 {
                let sep = NSBox()
                sep.boxType = .separator
                outer.addArrangedSubview(sep)
                outer.setCustomSpacing(0, after: sep)
            }
            let row = buildRow(for: setting, index: i)
            outer.addArrangedSubview(row)
            outer.setCustomSpacing(0, after: row)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        outer.addArrangedSubview(spacer)

        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetAll))
        resetBtn.bezelStyle = .rounded
        resetBtn.font = .systemFont(ofSize: 13)
        outer.addArrangedSubview(resetBtn)
        outer.setCustomSpacing(12, after: spacer)
    }

    private func buildRow(for setting: Setting, index: Int) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let titleLabel = NSTextField(labelWithString: setting.title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)

        let valueLbl = NSTextField(labelWithString: displayText(setting.stored, unit: setting.unit))
        valueLbl.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLbl.textColor = .secondaryLabelColor
        valueLbl.alignment = .right
        valueLbl.setContentHuggingPriority(.required, for: .horizontal)
        valueLabels.append(valueLbl)

        let titleRow = NSStackView(views: [titleLabel, valueLbl])
        titleRow.distribution = .fill
        titleRow.spacing = 8

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

        let desc = NSTextField(labelWithString: setting.description)
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = .tertiaryLabelColor
        desc.lineBreakMode = .byWordWrapping
        desc.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleRow, slider, desc])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            slider.widthAnchor.constraint(equalTo: stack.widthAnchor),
            desc.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return container
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ slider: NSSlider) {
        let i = slider.tag
        let v = slider.doubleValue
        valueLabels[i].stringValue = displayText(v, unit: settings[i].unit)
        UserDefaults.standard.set(v, forKey: settings[i].key)
        NotificationCenter.default.post(name: NSNotification.Name("ReLaySettingsChanged"), object: nil)
    }

    @objc private func resetAll() {
        for (i, setting) in settings.enumerated() {
            sliders[i].doubleValue = setting.defaultValue
            valueLabels[i].stringValue = displayText(setting.defaultValue, unit: setting.unit)
            UserDefaults.standard.set(setting.defaultValue, forKey: setting.key)
        }
        NotificationCenter.default.post(name: NSNotification.Name("ReLaySettingsChanged"), object: nil)
    }

    private func displayText(_ v: Double, unit: String) -> String {
        "\(Int(v)) \(unit)"
    }
}
