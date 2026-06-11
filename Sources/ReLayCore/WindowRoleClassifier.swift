import Foundation

public enum WindowRole: String, CaseIterable, Codable {
    case editor   = "Editor"
    case browser  = "Browser"
    case terminal = "Terminal"
    case chat     = "Chat"
    case notes    = "Notes"
    case meeting  = "Meeting"
    case mail     = "Mail"
    case design   = "Design"
    case media    = "Media"
    case ai       = "AI"
    case other    = "Other"
}

struct WindowRoleClassifier {

    // MARK: - Lookup tables (exact, lowercased app names)

    private static let meetingApps: Set<String> = [
        "zoom", "facetime", "microsoft teams", "google meet", "webex",
        "whereby", "around", "loom"
    ]

    private static let editorApps: Set<String> = [
        "xcode", "cursor", "visual studio code", "intellij idea", "appcode",
        "sublime text", "textedit", "nova", "zed", "windsurf", "fleet",
        "rubymine", "goland", "clion", "pycharm", "webstorm", "rider",
        "android studio", "emacs", "vim", "neovim", "bbedit", "coderunner"
    ]

    private static let browserApps: Set<String> = [
        "safari", "google chrome", "arc", "firefox", "microsoft edge",
        "brave browser", "opera", "vivaldi", "zen browser", "orion",
        "chromium", "min"
    ]

    private static let terminalApps: Set<String> = [
        "terminal", "iterm2", "warp", "ghostty", "kitty", "alacritty",
        "hyper", "tabby"
    ]

    private static let chatApps: Set<String> = [
        "slack", "discord", "messages", "whatsapp", "telegram",
        "signal", "beeper", "mattermost", "microsoft teams"
    ]

    private static let notesApps: Set<String> = [
        "notes", "obsidian", "notion", "craft", "bear", "drafts",
        "ulysses", "ia writer", "logseq", "roam research", "capacities",
        "apple notes"
    ]

    private static let mailApps: Set<String> = [
        "mail", "microsoft outlook", "spark", "airmail 5", "mimestream",
        "hey", "proton mail", "thunderbird", "canary mail"
    ]

    private static let designApps: Set<String> = [
        "figma", "sketch", "adobe photoshop", "adobe illustrator",
        "canva", "affinity designer", "affinity photo", "pixelmator pro",
        "inkscape", "principle", "framer", "origami studio", "rive",
        "adobe xd", "lunacy"
    ]

    private static let mediaApps: Set<String> = [
        "spotify", "apple music", "music", "vlc", "iina", "infuse",
        "plex", "youtube", "quicktime player", "final cut pro",
        "adobe premiere pro", "davinci resolve", "handbrake", "permute 3"
    ]

    private static let aiApps: Set<String> = [
        "chatgpt", "claude", "perplexity", "lm studio", "ollama",
        "jan", "msty", "diffusion bee", "draw things", "invoke ai",
        "copilot", "raycast"
    ]

    // MARK: - Title-based context signals

    private static let mediaTitleKeywords: [String] = [
        "youtube", "netflix", "twitch", "spotify", "hulu", "disney+",
        "apple tv", "prime video", "soundcloud"
    ]

    private static let meetingTitleKeywords: [String] = [
        "zoom", "google meet", "microsoft teams", "facetime", "webex"
    ]

    // MARK: - Classification

    static func classify(appName: String?, windowTitle: String?) -> WindowRole {
        let title = windowTitle?.lowercased() ?? ""

        // Title-based overrides first — a browser showing YouTube is media, not browser
        if meetingTitleKeywords.contains(where: { title.contains($0) }) { return .meeting }
        if mediaTitleKeywords.contains(where: { title.contains($0) })   { return .media   }

        guard let name = appName?.lowercased() else { return .other }

        if meetingApps.contains(name)  { return .meeting  }
        if editorApps.contains(name)   { return .editor   }
        if browserApps.contains(name)  { return .browser  }
        if terminalApps.contains(name) { return .terminal }
        if aiApps.contains(name)       { return .ai       }
        if chatApps.contains(name)     { return .chat     }
        if notesApps.contains(name)    { return .notes    }
        if mailApps.contains(name)     { return .mail     }
        if designApps.contains(name)   { return .design   }
        if mediaApps.contains(name)    { return .media    }

        return .other
    }
}
