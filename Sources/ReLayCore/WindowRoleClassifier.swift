import Foundation
import AppKit

public enum WindowRole: String, CaseIterable, Codable {
    case editor = "Editor"
    case browser = "Browser"
    case terminal = "Terminal"
    case chat = "Chat"
    case notes = "Notes"
    case meeting = "Meeting"
    case mail = "Mail"
    case design = "Design"
    case other = "Other"
}

struct WindowRoleClassifier {
    static func classify(appName: String?, windowTitle: String?) -> WindowRole {
        guard let appName = appName?.lowercased() else { return .other }
        let title = windowTitle?.lowercased() ?? ""

        // Meeting (Check title first as it can be in a browser)
        if title.contains("zoom") || title.contains("facetime") || title.contains("google meet") || title.contains("microsoft teams") {
            return .meeting
        }
        
        if appName.contains("zoom") || appName.contains("facetime") || appName.contains("teams") {
            return .meeting
        }

        // Editor
        if appName.contains("xcode") || appName.contains("cursor") || appName.contains("visual studio code") || 
           appName.contains("code") || appName.contains("intellij") || appName.contains("appcode") || 
           appName.contains("sublime") || appName.contains("textedit") {
            return .editor
        }

        // Browser
        if appName.contains("safari") || appName.contains("chrome") || appName.contains("arc") || 
           appName.contains("firefox") || appName.contains("edge") {
            return .browser
        }

        // Terminal
        if appName.contains("terminal") || appName.contains("iterm") || appName.contains("warp") || 
           appName.contains("ghostty") || appName.contains("kitty") {
            return .terminal
        }

        // Chat
        if appName.contains("slack") || appName.contains("discord") || appName.contains("messages") || 
           appName.contains("whatsapp") || appName.contains("telegram") {
            return .chat
        }

        // Notes
        if appName.contains("notes") || appName.contains("obsidian") || appName.contains("notion") || 
           appName.contains("craft") || appName.contains("bear") {
            return .notes
        }

        // Mail
        if appName.contains("mail") || appName.contains("outlook") || appName.contains("spark") {
            return .mail
        }
        
        // Design
        if appName.contains("figma") || appName.contains("sketch") || appName.contains("photoshop") || 
           appName.contains("illustrator") || appName.contains("canva") {
            return .design
        }

        return .other
    }
}
