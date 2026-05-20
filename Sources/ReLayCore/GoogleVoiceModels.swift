import Foundation

public struct GoogleVoiceCredentials: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let phoneNumber: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, phoneNumber: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.phoneNumber = phoneNumber
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}

public struct GoogleVoiceCall: Codable, Identifiable {
    public let id: String
    public let phoneNumber: String
    public let name: String?
    public let timestamp: Date
    public let duration: TimeInterval
    public let type: CallType
    public let read: Bool

    public enum CallType: String, Codable {
        case incoming
        case outgoing
        case missed
    }

    public init(id: String, phoneNumber: String, name: String?, timestamp: Date, duration: TimeInterval, type: CallType, read: Bool) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.name = name
        self.timestamp = timestamp
        self.duration = duration
        self.type = type
        self.read = read
    }
}

public struct GoogleVoiceMessage: Codable, Identifiable {
    public let id: String
    public let phoneNumber: String
    public let name: String?
    public let text: String
    public let timestamp: Date
    public let read: Bool
    public let type: MessageType

    public enum MessageType: String, Codable {
        case incoming
        case outgoing
        case draft
    }

    public init(id: String, phoneNumber: String, name: String?, text: String, timestamp: Date, read: Bool, type: MessageType) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.name = name
        self.text = text
        self.timestamp = timestamp
        self.read = read
        self.type = type
    }
}

public struct GoogleVoiceContact: Codable, Identifiable {
    public let id: String
    public let name: String
    public let phoneNumbers: [String]
    public let email: String?
    public let lastCommunication: Date?
    public let starred: Bool

    public init(id: String, name: String, phoneNumbers: [String], email: String?, lastCommunication: Date?, starred: Bool) {
        self.id = id
        self.name = name
        self.phoneNumbers = phoneNumbers
        self.email = email
        self.lastCommunication = lastCommunication
        self.starred = starred
    }
}

public struct GoogleVoiceConversation: Codable, Identifiable {
    public let id: String
    public let phoneNumber: String
    public let name: String?
    public let lastMessage: String
    public let lastTimestamp: Date
    public let messageCount: Int
    public let unreadCount: Int

    public init(id: String, phoneNumber: String, name: String?, lastMessage: String, lastTimestamp: Date, messageCount: Int, unreadCount: Int) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.name = name
        self.lastMessage = lastMessage
        self.lastTimestamp = lastTimestamp
        self.messageCount = messageCount
        self.unreadCount = unreadCount
    }
}

public enum GoogleVoiceError: LocalizedError {
    case invalidCredentials
    case tokenExpired
    case networkError(Error)
    case decodingError(Error)
    case authenticationFailed
    case rateLimited
    case serverError(Int)
    case invalidPhoneNumber
    case messageFailedToSend
    case contactNotFound
    case unknown

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Google Voice credentials"
        case .tokenExpired:
            return "Authentication token has expired"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .authenticationFailed:
            return "Authentication failed"
        case .rateLimited:
            return "Rate limited by Google Voice API"
        case .serverError(let code):
            return "Server error: \(code)"
        case .invalidPhoneNumber:
            return "Invalid phone number format"
        case .messageFailedToSend:
            return "Failed to send message"
        case .contactNotFound:
            return "Contact not found"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}
