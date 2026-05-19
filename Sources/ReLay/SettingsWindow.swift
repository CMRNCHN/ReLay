import AppKit
import Foundation

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "ReLay Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        setupView()
    }

    private func setupView() {
        guard let window = window else { return }
        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 20
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // Lock Threshold
        let lockStack = NSStackView()
        lockStack.spacing = 10
        let lockLabel = NSTextField(labelWithString: "Gesture Lock Threshold (px):")
        let lockField = NSTextField(string: String(format: "%.0f", UserDefaults.standard.double(forKey: "lockThreshold") != 0 ? UserDefaults.standard.double(forKey: "lockThreshold") : 20.0))
        lockField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        lockStack.addArrangedSubview(lockLabel)
        lockStack.addArrangedSubview(lockField)
        stackView.addArrangedSubview(lockStack)

        // Action Threshold
        let actionStack = NSStackView()
        actionStack.spacing = 10
        let actionLabel = NSTextField(labelWithString: "Layout Action Threshold (px):")
        let actionField = NSTextField(string: String(format: "%.0f", UserDefaults.standard.double(forKey: "actionThreshold") != 0 ? UserDefaults.standard.double(forKey: "actionThreshold") : 100.0))
        actionField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        actionStack.addArrangedSubview(actionLabel)
        actionStack.addArrangedSubview(actionField)
        stackView.addArrangedSubview(actionStack)

        // Flick Velocity
        let flickStack = NSStackView()
        flickStack.spacing = 10
        let flickLabel = NSTextField(labelWithString: "Flick Velocity (px/s):")
        let flickField = NSTextField(string: String(format: "%.0f", UserDefaults.standard.double(forKey: "flickVelocity") != 0 ? UserDefaults.standard.double(forKey: "flickVelocity") : 800.0))
        flickField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        flickStack.addArrangedSubview(flickLabel)
        flickStack.addArrangedSubview(flickField)
        stackView.addArrangedSubview(flickStack)

        // Cancel Threshold
        let cancelStack = NSStackView()
        cancelStack.spacing = 10
        let cancelLabel = NSTextField(labelWithString: "Cancel Threshold (px):")
        let cancelField = NSTextField(string: String(format: "%.0f", UserDefaults.standard.double(forKey: "cancelThreshold") != 0 ? UserDefaults.standard.double(forKey: "cancelThreshold") : 25.0))
        cancelField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        cancelStack.addArrangedSubview(cancelLabel)
        cancelStack.addArrangedSubview(cancelField)
        stackView.addArrangedSubview(cancelStack)

        // Save Button
        let saveButton = NSButton(title: "Save & Apply", target: self, action: #selector(saveSettings))
        saveButton.keyEquivalent = "\r"
        stackView.addArrangedSubview(saveButton)

        self.lockField = lockField
        self.actionField = actionField
        self.flickField = flickField
        self.cancelField = cancelField
    }

    private var lockField: NSTextField?
    private var actionField: NSTextField?
    private var flickField: NSTextField?
    private var cancelField: NSTextField?

    @objc private func saveSettings() {
        if let lockText = lockField?.stringValue, let lockVal = Double(lockText) {
            UserDefaults.standard.set(lockVal, forKey: "lockThreshold")
        }
        if let actionText = actionField?.stringValue, let actionVal = Double(actionText) {
            UserDefaults.standard.set(actionVal, forKey: "actionThreshold")
        }
        if let flickText = flickField?.stringValue, let flickVal = Double(flickText) {
            UserDefaults.standard.set(flickVal, forKey: "flickVelocity")
        }
        if let cancelText = cancelField?.stringValue, let cancelVal = Double(cancelText) {
            UserDefaults.standard.set(cancelVal, forKey: "cancelThreshold")
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("ReLaySettingsChanged"), object: nil)
        window?.close()
    }
}
