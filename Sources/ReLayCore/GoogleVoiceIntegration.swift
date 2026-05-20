import Foundation

/// Example usage and integration patterns for Google Voice functionality
public class GoogleVoiceIntegration {
    private let manager: GoogleVoiceManager

    public init() {
        self.manager = GoogleVoiceManager()
        setupCallbacks()
    }

    private func setupCallbacks() {
        Task {
            await manager.onIncomingCall = { [weak self] call in
                self?.handleIncomingCall(call)
            }

            await manager.onNewMessage = { [weak self] message, phoneNumber in
                self?.handleNewMessage(message, from: phoneNumber)
            }

            await manager.onCallEnded = { [weak self] call in
                self?.handleCallEnded(call)
            }
        }
    }

    public func initializeAuthentication(code: String, clientId: String, clientSecret: String) async throws {
        try await manager.authenticate(with: code, clientId: clientId, clientSecret: clientSecret)
    }

    public func startBackgroundPolling() {
        Task {
            await manager.startPolling(interval: 30)
        }
    }

    public func stopBackgroundPolling() {
        Task {
            await manager.stopPolling()
        }
    }

    public func getRecentCallsInfo() async throws -> String {
        let calls = try await manager.getRecentCalls(limit: 5)
        var info = "Recent Calls:\n"
        for call in calls {
            let duration = String(format: "%.0f", call.duration)
            let typeString = call.type.rawValue
            info += "- \(call.name ?? call.phoneNumber) (\(typeString)) - \(duration)s\n"
        }
        return info
    }

    public func makePhoneCall(to phoneNumber: String) async throws {
        try await manager.initiateCall(to: phoneNumber)
    }

    public func getConversationsList() async throws -> String {
        let conversations = try await manager.getConversations()
        var list = "Conversations:\n"
        for conversation in conversations {
            list += "- \(conversation.name ?? conversation.phoneNumber): \(conversation.lastMessage) (\(conversation.unreadCount) unread)\n"
        }
        return list
    }

    public func getMessagesFor(phoneNumber: String) async throws -> [GoogleVoiceMessage] {
        return try await manager.getMessages(for: phoneNumber)
    }

    public func sendTextMessage(to phoneNumber: String, text: String) async throws {
        try await manager.sendMessage(to: phoneNumber, text: text)
    }

    public func getContactsList() async throws -> String {
        let contacts = try await manager.getAllContacts()
        var list = "Contacts:\n"
        for contact in contacts {
            list += "- \(contact.name): \(contact.phoneNumbers.joined(separator: ", "))\n"
        }
        return list
    }

    public func searchContactsByName(_ name: String) async throws -> [GoogleVoiceContact] {
        return try await manager.searchContacts(query: name)
    }

    private func handleIncomingCall(_ call: GoogleVoiceCall) {
        let contactName = call.name ?? call.phoneNumber
        AppLogger.log("Incoming call from \(contactName)", subsystem: "GoogleVoiceIntegration")
    }

    private func handleNewMessage(_ message: GoogleVoiceMessage, from phoneNumber: String) {
        let contactName = message.name ?? phoneNumber
        AppLogger.log("New message from \(contactName): \(message.text)", subsystem: "GoogleVoiceIntegration")
    }

    private func handleCallEnded(_ call: GoogleVoiceCall) {
        let contactName = call.name ?? call.phoneNumber
        let duration = String(format: "%.0f", call.duration)
        AppLogger.log("Call ended with \(contactName) (\(duration)s)", subsystem: "GoogleVoiceIntegration")
    }
}
