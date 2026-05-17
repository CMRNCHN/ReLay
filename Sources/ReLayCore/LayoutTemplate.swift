import Cocoa

struct LayoutTemplate: Identifiable {
    struct Slot: Identifiable {
        let id: Int
        let rect: CGRect
        let preferredRoles: [WindowRole]
        
        init(id: Int, rect: CGRect, preferredRoles: [WindowRole] = []) {
            self.id = id
            self.rect = rect
            self.preferredRoles = preferredRoles
        }
    }

    let id: String
    let name: String
    let isSuggested: Bool
    let slots: [Slot]

    static let all: [LayoutTemplate] = [
        LayoutTemplate(
            id: "coding",
            name: "Coding",
            isSuggested: true,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.68, height: 1.00), preferredRoles: [.editor]),
                Slot(id: 1, rect: CGRect(x: 0.68, y: 0.00, width: 0.32, height: 0.50), preferredRoles: [.browser, .notes]),
                Slot(id: 2, rect: CGRect(x: 0.68, y: 0.50, width: 0.32, height: 0.50), preferredRoles: [.terminal, .chat])
            ]
        ),
        LayoutTemplate(
            id: "research",
            name: "Research",
            isSuggested: true,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.50, height: 1.00), preferredRoles: [.browser]),
                Slot(id: 1, rect: CGRect(x: 0.50, y: 0.00, width: 0.50, height: 0.50), preferredRoles: [.notes]),
                Slot(id: 2, rect: CGRect(x: 0.50, y: 0.50, width: 0.50, height: 0.50), preferredRoles: [.chat, .mail])
            ]
        ),
        LayoutTemplate(
            id: "meeting",
            name: "Meeting",
            isSuggested: true,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.70, height: 1.00), preferredRoles: [.meeting]),
                Slot(id: 1, rect: CGRect(x: 0.70, y: 0.00, width: 0.30, height: 1.00), preferredRoles: [.notes, .chat])
            ]
        ),
        LayoutTemplate(
            id: "split",
            name: "Split",
            isSuggested: false,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.50, height: 1.00)),
                Slot(id: 1, rect: CGRect(x: 0.50, y: 0.00, width: 0.50, height: 1.00))
            ]
        ),
        LayoutTemplate(
            id: "thirds",
            name: "Thirds",
            isSuggested: false,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.333, height: 1.00)),
                Slot(id: 1, rect: CGRect(x: 0.333, y: 0.00, width: 0.334, height: 1.00)),
                Slot(id: 2, rect: CGRect(x: 0.667, y: 0.00, width: 0.333, height: 1.00))
            ]
        ),
        LayoutTemplate(
            id: "grid4",
            name: "Grid",
            isSuggested: false,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.50, height: 0.50)),
                Slot(id: 1, rect: CGRect(x: 0.50, y: 0.00, width: 0.50, height: 0.50)),
                Slot(id: 2, rect: CGRect(x: 0.00, y: 0.50, width: 0.50, height: 0.50)),
                Slot(id: 3, rect: CGRect(x: 0.50, y: 0.50, width: 0.50, height: 0.50))
            ]
        )
    ]


    func frame(for slot: Slot, in screen: CGRect, gap: CGFloat = 8) -> CGRect {
        CGRect(
            x: screen.minX + slot.rect.minX * screen.width + gap / 2,
            y: screen.minY + slot.rect.minY * screen.height + gap / 2,
            width: max(1, slot.rect.width * screen.width - gap),
            height: max(1, slot.rect.height * screen.height - gap)
        )
    }
}

struct LayoutWindowItem: Identifiable {
    let id: String
    let element: AXUIElement
    let title: String
    let appName: String?
    let bundleID: String?
    let appIcon: NSImage?
    let role: WindowRole
}
