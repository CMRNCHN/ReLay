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

    /// A scoring rule owned by the template. When all `requiredRoles` are
    /// present in the current window set, `bonus` points are added and
    /// `reason` appears in the suggestion label.
    struct ScoringHint {
        let requiredRoles: Set<WindowRole>
        let activeRole:    WindowRole?      // extra bonus if the active window has this role
        let bonus:         Double
        let activeBonus:   Double
        let reason:        String

        init(requiredRoles: Set<WindowRole>,
             activeRole:    WindowRole? = nil,
             bonus:         Double,
             activeBonus:   Double = 15,
             reason:        String) {
            self.requiredRoles = requiredRoles
            self.activeRole    = activeRole
            self.bonus         = bonus
            self.activeBonus   = activeBonus
            self.reason        = reason
        }
    }

    let id:           String
    let name:         String
    let isSuggested:  Bool
    let slots:        [Slot]
    let scoringHints: [ScoringHint]

    init(id: String, name: String, isSuggested: Bool, slots: [Slot], scoringHints: [ScoringHint] = []) {
        self.id           = id
        self.name         = name
        self.isSuggested  = isSuggested
        self.slots        = slots
        self.scoringHints = scoringHints
    }

    static let all: [LayoutTemplate] = [
        LayoutTemplate(
            id: "coding",
            name: "Coding",
            isSuggested: true,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.68, height: 1.00), preferredRoles: [.editor]),
                Slot(id: 1, rect: CGRect(x: 0.68, y: 0.00, width: 0.32, height: 0.50), preferredRoles: [.browser, .notes]),
                Slot(id: 2, rect: CGRect(x: 0.68, y: 0.50, width: 0.32, height: 0.50), preferredRoles: [.terminal, .chat])
            ],
            scoringHints: [
                ScoringHint(requiredRoles: [.editor, .terminal], activeRole: .editor, bonus: 30, reason: "IDE + Terminal"),
                ScoringHint(requiredRoles: [.editor, .browser],  activeRole: .editor, bonus: 20, reason: "IDE + Browser"),
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
            ],
            scoringHints: [
                ScoringHint(requiredRoles: [.browser, .notes], activeRole: .browser, bonus: 25, reason: "Browser + Notes"),
                ScoringHint(requiredRoles: [.browser, .ai],    activeRole: .browser, bonus: 25, reason: "Browser + AI"),
            ]
        ),
        LayoutTemplate(
            id: "meeting",
            name: "Meeting",
            isSuggested: true,
            slots: [
                Slot(id: 0, rect: CGRect(x: 0.00, y: 0.00, width: 0.70, height: 1.00), preferredRoles: [.meeting]),
                Slot(id: 1, rect: CGRect(x: 0.70, y: 0.00, width: 0.30, height: 1.00), preferredRoles: [.notes, .chat])
            ],
            scoringHints: [
                ScoringHint(requiredRoles: [.meeting], activeRole: .meeting, bonus: 50, activeBonus: 25, reason: "Meeting active"),
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
                Slot(id: 0, rect: CGRect(x: 0.00,  y: 0.00, width: 0.333, height: 1.00)),
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
