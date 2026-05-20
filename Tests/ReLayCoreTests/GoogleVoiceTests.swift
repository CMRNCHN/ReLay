import XCTest
@testable import ReLayCore

final class GoogleVoiceModelsTests: XCTestCase {
    func testGoogleVoiceCredentials() {
        let expiresAt = Date().addingTimeInterval(3600)
        let credentials = GoogleVoiceCredentials(
            accessToken: "test_token",
            refreshToken: "refresh_token",
            expiresAt: expiresAt,
            phoneNumber: "+1234567890"
        )

        XCTAssertEqual(credentials.accessToken, "test_token")
        XCTAssertEqual(credentials.phoneNumber, "+1234567890")
        XCTAssertFalse(credentials.isExpired)
    }

    func testGoogleVoiceCredentialsExpired() {
        let expiresAt = Date().addingTimeInterval(-1)
        let credentials = GoogleVoiceCredentials(
            accessToken: "test_token",
            refreshToken: "refresh_token",
            expiresAt: expiresAt,
            phoneNumber: "+1234567890"
        )

        XCTAssertTrue(credentials.isExpired)
    }

    func testGoogleVoiceCallCreation() {
        let timestamp = Date()
        let call = GoogleVoiceCall(
            id: "call_1",
            phoneNumber: "+1234567890",
            name: "John Doe",
            timestamp: timestamp,
            duration: 300,
            type: .incoming,
            read: true
        )

        XCTAssertEqual(call.id, "call_1")
        XCTAssertEqual(call.type, .incoming)
        XCTAssertEqual(call.duration, 300)
    }

    func testGoogleVoiceMessageCreation() {
        let timestamp = Date()
        let message = GoogleVoiceMessage(
            id: "msg_1",
            phoneNumber: "+1234567890",
            name: "Jane Doe",
            text: "Hello!",
            timestamp: timestamp,
            read: false,
            type: .incoming
        )

        XCTAssertEqual(message.text, "Hello!")
        XCTAssertEqual(message.type, .incoming)
        XCTAssertFalse(message.read)
    }

    func testGoogleVoiceContactCreation() {
        let contact = GoogleVoiceContact(
            id: "contact_1",
            name: "John Smith",
            phoneNumbers: ["+1234567890", "+0987654321"],
            email: "john@example.com",
            lastCommunication: Date(),
            starred: true
        )

        XCTAssertEqual(contact.name, "John Smith")
        XCTAssertEqual(contact.phoneNumbers.count, 2)
        XCTAssertTrue(contact.starred)
    }

    func testGoogleVoiceConversationCreation() {
        let conversation = GoogleVoiceConversation(
            id: "conv_1",
            phoneNumber: "+1234567890",
            name: "Support Team",
            lastMessage: "Your ticket has been resolved",
            lastTimestamp: Date(),
            messageCount: 5,
            unreadCount: 0
        )

        XCTAssertEqual(conversation.messageCount, 5)
        XCTAssertEqual(conversation.unreadCount, 0)
    }
}

final class GoogleVoiceClientTests: XCTestCase {
    var mockStore: MockCredentialsStore!

    override func setUp() {
        super.setUp()
        mockStore = MockCredentialsStore()
    }

    func testClientInitialization() {
        let client = GoogleVoiceClient(credentialsStore: mockStore)
        XCTAssertNotNil(client)
    }
}

final class GoogleVoiceManagerTests: XCTestCase {
    var mockStore: MockCredentialsStore!
    var manager: GoogleVoiceManager!

    override func setUp() {
        super.setUp()
        mockStore = MockCredentialsStore()
        let client = GoogleVoiceClient(credentialsStore: mockStore)
        manager = GoogleVoiceManager(client: client)
    }

    override func tearDown() {
        super.tearDown()
        Task {
            await manager.stopPolling()
        }
    }

    func testPollingInitialization() async {
        await manager.startPolling(interval: 1)
        try? await Task.sleep(nanoseconds: 100_000_000)

        await manager.stopPolling()
    }
}

// MARK: - Mock Classes

class MockCredentialsStore: CredentialsStore {
    var credentials: GoogleVoiceCredentials?

    func save(_ credentials: GoogleVoiceCredentials) async throws {
        self.credentials = credentials
    }

    func load() async throws -> GoogleVoiceCredentials? {
        return credentials
    }

    func delete() async throws {
        credentials = nil
    }
}
