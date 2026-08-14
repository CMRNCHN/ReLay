import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - LayoutAssignment
// Pure helpers for Layout Library slot fill + geometry. No AX writes.

enum LayoutAssignment {

    /// Assign visible windows to template slots by preferred role, then fill
    /// leftovers in window order. Returns slotID → bundleID.
    static func autoFill(template: LayoutTemplate, windows: [LayoutWindowItem]) -> [Int: String] {
        var assignments: [Int: String] = [:]
        var remaining = windows.filter { $0.bundleID != nil }

        for slot in template.slots {
            guard !slot.preferredRoles.isEmpty,
                  let index = remaining.firstIndex(where: { slot.preferredRoles.contains($0.role) }),
                  let bundleID = remaining[index].bundleID
            else { continue }
            assignments[slot.id] = bundleID
            remaining.removeAll { $0.bundleID == bundleID }
        }

        for slot in template.slots {
            guard assignments[slot.id] == nil,
                  let next = remaining.first,
                  let bundleID = next.bundleID
            else { continue }
            assignments[slot.id] = bundleID
            remaining.removeAll { $0.bundleID == bundleID }
        }

        return assignments
    }

    /// Normalized slot rect → pixel frame in `screen`, with padding inset.
    static func frameForSlot(
        _ slot: LayoutTemplate.Slot,
        in screen: CGRect,
        gap: CGFloat = ReLaySettings.layoutPadding
    ) -> CGRect {
        CGRect(
            x: screen.minX + slot.rect.minX * screen.width + gap / 2,
            y: screen.minY + slot.rect.minY * screen.height + gap / 2,
            width: max(1, slot.rect.width * screen.width - gap),
            height: max(1, slot.rect.height * screen.height - gap)
        )
    }

    /// Trigger / frontmost-matching window first, then remaining in list order.
    static func orderForQuickApply(windows: [AXUIElement], trigger: AXUIElement?) -> [AXUIElement] {
        guard let trigger else { return windows }
        var rest = windows
        if let idx = rest.firstIndex(where: { CFEqual($0, trigger) }) {
            let first = rest.remove(at: idx)
            return [first] + rest
        }
        var triggerPID: pid_t = 0
        AXUIElementGetPid(trigger, &triggerPID)
        if triggerPID != 0,
           let idx = rest.firstIndex(where: {
               var pid: pid_t = 0
               AXUIElementGetPid($0, &pid)
               return pid == triggerPID
           }) {
            let first = rest.remove(at: idx)
            return [first] + rest
        }
        return windows
    }
}

extension Notification.Name {
    /// Posted after Layout Library successfully moves one or more windows.
    /// WindowRuntime observes this to suspend AutoLayoutWatcher briefly.
    static let relayLayoutApplied = Notification.Name("ReLayLayoutApplied")
}
