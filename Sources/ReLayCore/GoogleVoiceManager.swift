import Foundation

public actor GoogleVoiceManager {
    private let client: GoogleVoiceClient
    private var callHistoryCache: [GoogleVoiceCall] = []
    private var conversationsCache: [GoogleVoiceConversation] = []
    private var contactsCache: [GoogleVoiceContact] = []
    private var pollTask: Task<Void, Never>?
    private var isPolling = false

    public var onIncomingCall: ((GoogleVoiceCall) -> Void)?
    public var onNewMessage: ((GoogleVoiceMessage, String) -> Void)?
    public var onCallEnded: ((GoogleVoiceCall) -> Void)?

    public init(client: GoogleVoiceClient? = nil) {
        self.client = client ?? GoogleVoiceClient()
    }

    deinit {
        pollTask?.cancel()
    }

    public func authenticate(with code: String, clientId: String, clientSecret: String) async throws {
        try await client.authenticate(with: code, clientId: clientId, clientSecret: clientSecret)
        AppLogger.log("GoogleVoiceManager authenticated successfully", subsystem: "GoogleVoiceManager")
    }

    public func startPolling(interval: TimeInterval = 30) {
        guard !isPolling else { return }
        isPolling = true

        pollTask = Task {
            while !Task.isCancelled {
                do {
                    try await pollForUpdates()
                } catch {
                    AppLogger.log("Polling error: \(error.localizedDescription)", subsystem: "GoogleVoiceManager")
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }

        AppLogger.log("Started polling for updates every \(interval) seconds", subsystem: "GoogleVoiceManager")
    }

    public func stopPolling() {
        isPolling = false
        pollTask?.cancel()
        pollTask = nil
        AppLogger.log("Stopped polling for updates", subsystem: "GoogleVoiceManager")
    }

    public func getRecentCalls(limit: Int = 10) async throws -> [GoogleVoiceCall] {
        let calls = try await client.getCallHistory()
        return Array(calls.prefix(limit))
    }

    public func initiateCall(to phoneNumber: String) async throws {
        try await client.makeCall(to: phoneNumber)
        AppLogger.log("Initiated call to \(phoneNumber)", subsystem: "GoogleVoiceManager")
    }

    public func terminateCall(_ callId: String) async throws {
        try await client.endCall(callId: callId)
        AppLogger.log("Terminated call: \(callId)", subsystem: "GoogleVoiceManager")
    }

    public func getConversations() async throws -> [GoogleVoiceConversation] {
        let conversations = try await client.getConversations()
        self.conversationsCache = conversations
        return conversations
    }

    public func getMessages(for phoneNumber: String) async throws -> [GoogleVoiceMessage] {
        return try await client.getMessages(for: phoneNumber)
    }

    public func sendMessage(to phoneNumber: String, text: String) async throws {
        try await client.sendMessage(to: phoneNumber, text: text)
        AppLogger.log("Message sent to \(phoneNumber)", subsystem: "GoogleVoiceManager")
    }

    public func markMessageAsRead(_ messageId: String) async throws {
        try await client.markMessageAsRead(messageId)
    }

    public func getAllContacts() async throws -> [GoogleVoiceContact] {
        let contacts = try await client.getContacts()
        self.contactsCache = contacts
        return contacts
    }

    public func getContact(byId contactId: String) async throws -> GoogleVoiceContact {
        return try await client.getContact(byId: contactId)
    }

    public func searchContacts(query: String) async throws -> [GoogleVoiceContact] {
        return try await client.searchContacts(query: query)
    }

    public func findOrCreateContact(phoneNumber: String) async throws -> GoogleVoiceContact? {
        let contacts = try await getAllContacts()
        if let existing = contacts.first(where: { $0.phoneNumbers.contains(phoneNumber) }) {
            return existing
        }
        return nil
    }

    private func pollForUpdates() async throws {
        let newCalls = try await client.getCallHistory()
        let oldCallIds = Set(callHistoryCache.map { $0.id })
        let newCallIds = Set(newCalls.map { $0.id })

        let incomingCalls = newCalls.filter { call in
            !oldCallIds.contains(call.id) && call.type == .incoming
        }

        for call in incomingCalls {
            AppLogger.log("Detected incoming call from \(call.phoneNumber)", subsystem: "GoogleVoiceManager")
            onIncomingCall?(call)
        }

        callHistoryCache = newCalls

        let conversations = try await client.getConversations()
        for conversation in conversations where conversation.unreadCount > 0 {
            if let oldConversation = conversationsCache.first(where: { $0.id == conversation.id }) {
                if oldConversation.unreadCount < conversation.unreadCount {
                    let messages = try await client.getMessages(for: conversation.phoneNumber)
                    if let lastMessage = messages.last {
                        AppLogger.log("New message from \(conversation.phoneNumber)", subsystem: "GoogleVoiceManager")
                        onNewMessage?(lastMessage, conversation.phoneNumber)
                    }
                }
            }
        }

        conversationsCache = conversations
    }
}
