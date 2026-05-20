import Foundation

public actor GoogleVoiceClient {
    private let baseURL = "https://www.googleapis.com/voice/v1"
    private let authBaseURL = "https://oauth2.googleapis.com"

    private var credentials: GoogleVoiceCredentials?
    private let urlSession: URLSession
    private let credentialsStore: CredentialsStore

    public init(credentialsStore: CredentialsStore = FileCredentialsStore()) {
        self.credentialsStore = credentialsStore
        self.urlSession = URLSession(configuration: .default)
        Task {
            await loadStoredCredentials()
        }
    }

    public func authenticate(with code: String, clientId: String, clientSecret: String) async throws {
        let params = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "grant_type": "authorization_code"
        ]

        let body = try JSONSerialization.data(withJSONObject: params)
        var request = URLRequest(url: URL(string: "\(authBaseURL)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleVoiceError.authenticationFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw GoogleVoiceError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        let newCredentials = GoogleVoiceCredentials(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? "",
            expiresAt: expiresAt,
            phoneNumber: "" // Will be set when fetching profile
        )

        self.credentials = newCredentials
        try await credentialsStore.save(newCredentials)

        AppLogger.log("Successfully authenticated with Google Voice", subsystem: "GoogleVoiceClient")
    }

    public func refreshToken() async throws {
        guard let credentials = credentials else {
            throw GoogleVoiceError.invalidCredentials
        }

        let params = [
            "client_id": "YOUR_CLIENT_ID",
            "client_secret": "YOUR_CLIENT_SECRET",
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token"
        ]

        let body = try JSONSerialization.data(withJSONObject: params)
        var request = URLRequest(url: URL(string: "\(authBaseURL)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw GoogleVoiceError.authenticationFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

        let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        let updatedCredentials = GoogleVoiceCredentials(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? credentials.refreshToken,
            expiresAt: expiresAt,
            phoneNumber: credentials.phoneNumber
        )

        self.credentials = updatedCredentials
        try await credentialsStore.save(updatedCredentials)

        AppLogger.log("Successfully refreshed authentication token", subsystem: "GoogleVoiceClient")
    }

    public func getCallHistory() async throws -> [GoogleVoiceCall] {
        let endpoint = "\(baseURL)/me/calls"
        let response = try await makeRequest(endpoint, method: "GET")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct CallResponse: Decodable {
            let calls: [GoogleVoiceCall]?
        }

        let callResponse = try decoder.decode(CallResponse.self, from: response)

        AppLogger.log("Retrieved \(callResponse.calls?.count ?? 0) calls from history", subsystem: "GoogleVoiceClient")
        return callResponse.calls ?? []
    }

    public func makeCall(to phoneNumber: String) async throws {
        guard isValidPhoneNumber(phoneNumber) else {
            throw GoogleVoiceError.invalidPhoneNumber
        }

        let endpoint = "\(baseURL)/me/calls"
        let params = ["phone_number": phoneNumber]
        let body = try JSONSerialization.data(withJSONObject: params)

        let _ = try await makeRequest(endpoint, method: "POST", body: body)

        AppLogger.log("Initiated call to \(phoneNumber)", subsystem: "GoogleVoiceClient")
    }

    public func endCall(callId: String) async throws {
        let endpoint = "\(baseURL)/me/calls/\(callId)"
        let _ = try await makeRequest(endpoint, method: "DELETE")

        AppLogger.log("Ended call: \(callId)", subsystem: "GoogleVoiceClient")
    }

    public func getConversations() async throws -> [GoogleVoiceConversation] {
        let endpoint = "\(baseURL)/me/conversations"
        let response = try await makeRequest(endpoint, method: "GET")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct ConversationResponse: Decodable {
            let conversations: [GoogleVoiceConversation]?
        }

        let conversationResponse = try decoder.decode(ConversationResponse.self, from: response)

        AppLogger.log("Retrieved \(conversationResponse.conversations?.count ?? 0) conversations", subsystem: "GoogleVoiceClient")
        return conversationResponse.conversations ?? []
    }

    public func getMessages(for phoneNumber: String) async throws -> [GoogleVoiceMessage] {
        let endpoint = "\(baseURL)/me/conversations/\(phoneNumber)"
        let response = try await makeRequest(endpoint, method: "GET")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct MessageResponse: Decodable {
            let messages: [GoogleVoiceMessage]?
        }

        let messageResponse = try decoder.decode(MessageResponse.self, from: response)

        AppLogger.log("Retrieved \(messageResponse.messages?.count ?? 0) messages for \(phoneNumber)", subsystem: "GoogleVoiceClient")
        return messageResponse.messages ?? []
    }

    public func sendMessage(to phoneNumber: String, text: String) async throws {
        guard isValidPhoneNumber(phoneNumber) else {
            throw GoogleVoiceError.invalidPhoneNumber
        }

        let endpoint = "\(baseURL)/me/messages"
        let params = [
            "phone_number": phoneNumber,
            "text": text
        ]
        let body = try JSONSerialization.data(withJSONObject: params)

        let _ = try await makeRequest(endpoint, method: "POST", body: body)

        AppLogger.log("Sent message to \(phoneNumber)", subsystem: "GoogleVoiceClient")
    }

    public func markMessageAsRead(_ messageId: String) async throws {
        let endpoint = "\(baseURL)/me/messages/\(messageId)/read"
        let _ = try await makeRequest(endpoint, method: "POST")

        AppLogger.log("Marked message as read: \(messageId)", subsystem: "GoogleVoiceClient")
    }

    public func getContacts() async throws -> [GoogleVoiceContact] {
        let endpoint = "\(baseURL)/me/contacts"
        let response = try await makeRequest(endpoint, method: "GET")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct ContactResponse: Decodable {
            let contacts: [GoogleVoiceContact]?
        }

        let contactResponse = try decoder.decode(ContactResponse.self, from: response)

        AppLogger.log("Retrieved \(contactResponse.contacts?.count ?? 0) contacts", subsystem: "GoogleVoiceClient")
        return contactResponse.contacts ?? []
    }

    public func getContact(byId contactId: String) async throws -> GoogleVoiceContact {
        let endpoint = "\(baseURL)/me/contacts/\(contactId)"
        let response = try await makeRequest(endpoint, method: "GET")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let contact = try decoder.decode(GoogleVoiceContact.self, from: response)

        AppLogger.log("Retrieved contact: \(contact.name)", subsystem: "GoogleVoiceClient")
        return contact
    }

    public func searchContacts(query: String) async throws -> [GoogleVoiceContact] {
        let endpoint = "\(baseURL)/me/contacts?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let response = try await makeRequest(endpoint, method: "GET")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct ContactResponse: Decodable {
            let contacts: [GoogleVoiceContact]?
        }

        let contactResponse = try decoder.decode(ContactResponse.self, from: response)

        AppLogger.log("Search found \(contactResponse.contacts?.count ?? 0) contacts matching '\(query)'", subsystem: "GoogleVoiceClient")
        return contactResponse.contacts ?? []
    }

    private func makeRequest(_ endpoint: String, method: String, body: Data? = nil) async throws -> Data {
        guard var credentials = credentials else {
            throw GoogleVoiceError.invalidCredentials
        }

        if credentials.isExpired {
            try await refreshToken()
            credentials = self.credentials!
        }

        guard let url = URL(string: endpoint) else {
            throw GoogleVoiceError.unknown
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GoogleVoiceError.unknown
            }

            switch httpResponse.statusCode {
            case 200...299:
                return data
            case 401:
                throw GoogleVoiceError.authenticationFailed
            case 429:
                throw GoogleVoiceError.rateLimited
            case 400...499:
                throw GoogleVoiceError.serverError(httpResponse.statusCode)
            case 500...599:
                throw GoogleVoiceError.serverError(httpResponse.statusCode)
            default:
                throw GoogleVoiceError.serverError(httpResponse.statusCode)
            }
        } catch let error as URLError {
            throw GoogleVoiceError.networkError(error)
        } catch let error as GoogleVoiceError {
            throw error
        } catch {
            throw GoogleVoiceError.unknown
        }
    }

    private func loadStoredCredentials() async {
        do {
            if let stored = try await credentialsStore.load() {
                self.credentials = stored
                AppLogger.log("Loaded stored credentials", subsystem: "GoogleVoiceClient")
            }
        } catch {
            AppLogger.log("Failed to load stored credentials: \(error)", subsystem: "GoogleVoiceClient")
        }
    }

    private func isValidPhoneNumber(_ phoneNumber: String) -> Bool {
        let phoneRegex = "^[+]?[(]?[0-9]{3}[)]?[-\\s.]?[0-9]{3}[-\\s.]?[0-9]{4,6}$"
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phoneTest.evaluate(with: phoneNumber)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

public protocol CredentialsStore {
    func save(_ credentials: GoogleVoiceCredentials) async throws
    func load() async throws -> GoogleVoiceCredentials?
    func delete() async throws
}

public actor FileCredentialsStore: CredentialsStore {
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let reLayFolder = appSupport.appendingPathComponent("ReLay")
            try? FileManager.default.createDirectory(at: reLayFolder, withIntermediateDirectories: true)
            self.fileURL = reLayFolder.appendingPathComponent("gvoice_credentials.json")
        }
    }

    public func save(_ credentials: GoogleVoiceCredentials) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(credentials)
        try data.write(to: fileURL, options: .atomic)
        AppLogger.log("Saved credentials to \(fileURL.path)", subsystem: "GoogleVoiceClient")
    }

    public func load() async throws -> GoogleVoiceCredentials? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GoogleVoiceCredentials.self, from: data)
    }

    public func delete() async throws {
        try FileManager.default.removeItem(at: fileURL)
        AppLogger.log("Deleted credentials file", subsystem: "GoogleVoiceClient")
    }
}
