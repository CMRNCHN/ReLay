# Google Voice Wrapper Setup and Usage Guide

This guide explains how to set up and use the Google Voice wrapper for ReLay.

## Components

The Google Voice wrapper consists of four main components:

### 1. **GoogleVoiceModels.swift**
Defines all data models and types:
- `GoogleVoiceCredentials`: OAuth credentials management
- `GoogleVoiceCall`: Call history records
- `GoogleVoiceMessage`: SMS/text messages
- `GoogleVoiceContact`: Contact information
- `GoogleVoiceConversation`: Message conversations
- `GoogleVoiceError`: Error handling

### 2. **GoogleVoiceClient.swift**
Low-level API client that handles:
- OAuth 2.0 authentication and token refresh
- Call history management
- Message sending and retrieval
- Contact management
- Direct Google Voice API calls
- Automatic credential persistence

**Key Features:**
- Actor-based thread safety
- Automatic token refresh
- Credential storage with file persistence
- Comprehensive error handling

### 3. **GoogleVoiceManager.swift**
High-level manager providing:
- Simplified interface to common operations
- Real-time polling for calls and messages
- Event callbacks for incoming calls and messages
- Conversation management
- Contact searching and retrieval

**Callbacks:**
- `onIncomingCall`: Triggered when a new incoming call is detected
- `onNewMessage`: Triggered when a new message arrives
- `onCallEnded`: Triggered when a call ends

### 4. **GoogleVoiceIntegration.swift**
Helper class demonstrating integration patterns and providing convenient methods for:
- Authentication initialization
- Starting/stopping background polling
- Retrieving and displaying information
- Sending calls and messages

## Setup Instructions

### Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable the Google Voice API
4. Create OAuth 2.0 credentials (Desktop application)
5. Note your Client ID and Client Secret

### Step 2: Initialize Authentication

```swift
let integration = GoogleVoiceIntegration()

// Get authorization code from user (via browser)
let authCode = "authorization_code_from_oauth_flow"

try await integration.initializeAuthentication(
    code: authCode,
    clientId: "YOUR_CLIENT_ID",
    clientSecret: "YOUR_CLIENT_SECRET"
)
```

### Step 3: Start Using the API

```swift
// Start background polling for new calls and messages
integration.startBackgroundPolling()

// Get recent calls
let recentCalls = try await integration.getRecentCallsInfo()
print(recentCalls)

// Get conversations
let conversations = try await integration.getConversationsList()
print(conversations)

// Get contacts
let contacts = try await integration.getContactsList()
print(contacts)
```

## Usage Examples

### Making a Call

```swift
try await integration.makePhoneCall(to: "+1-800-555-1234")
```

### Sending a Text Message

```swift
try await integration.sendTextMessage(
    to: "+1-800-555-1234",
    text: "Hello! How are you?"
)
```

### Retrieving Messages

```swift
let messages = try await integration.getMessagesFor(phoneNumber: "+1-800-555-1234")
for message in messages {
    print("\(message.name ?? message.phoneNumber): \(message.text)")
}
```

### Searching Contacts

```swift
let contacts = try await integration.searchContactsByName("John")
for contact in contacts {
    print("\(contact.name): \(contact.phoneNumbers)")
}
```

### Setting Up Event Handlers

```swift
let manager = GoogleVoiceManager()

await manager.onIncomingCall = { call in
    print("Incoming call from \(call.name ?? call.phoneNumber)")
}

await manager.onNewMessage = { message, phoneNumber in
    print("New message from \(phoneNumber): \(message.text)")
}

await manager.startPolling(interval: 30)
```

## Credential Storage

Credentials are automatically saved to:
```
~/Library/Application Support/ReLay/gvoice_credentials.json
```

The file contains:
- Access token
- Refresh token
- Expiration timestamp
- Associated phone number

**Security Note:** Ensure this file is protected with appropriate file permissions.

## Error Handling

All API calls may throw `GoogleVoiceError`:

```swift
do {
    try await integration.sendTextMessage(to: phoneNumber, text: message)
} catch let error as GoogleVoiceError {
    switch error {
    case .invalidPhoneNumber:
        print("Phone number format is invalid")
    case .tokenExpired:
        print("Need to re-authenticate")
    case .rateLimited:
        print("Rate limited - wait before retrying")
    case .networkError(let underlying):
        print("Network error: \(underlying)")
    default:
        print("Error: \(error.localizedDescription)")
    }
}
```

## Threading and Concurrency

All components use Swift's actor model for thread safety:

- `GoogleVoiceClient` is an actor
- `GoogleVoiceManager` is an actor
- `FileCredentialsStore` is an actor

This ensures thread-safe access to shared state. Always use `await` when calling methods:

```swift
let manager = GoogleVoiceManager()
let calls = try await manager.getRecentCalls()
```

## Testing

Unit tests are provided in `GoogleVoiceTests.swift`:

```bash
swift test
```

Tests cover:
- Data model creation and validation
- Credentials management
- Manager initialization
- Event polling setup

## Logging

All operations are logged using the ReLay `AppLogger`:

```
[2026-05-20T12:34:56.789Z] [GoogleVoiceClient] Successfully authenticated with Google Voice
[2026-05-20T12:34:57.123Z] [GoogleVoiceManager] Detected incoming call from +1-800-555-1234
[2026-05-20T12:34:58.456Z] [GoogleVoiceIntegration] New message from Support Team: Your ticket has been resolved
```

## Troubleshooting

### "Invalid credentials" error
- Verify the OAuth flow completed successfully
- Check that Client ID and Client Secret are correct
- Ensure credentials file has proper permissions

### "Rate Limited" error
- Implement exponential backoff
- Reduce polling frequency
- Contact Google Cloud support if limits are too restrictive

### "Token Expired" error
- The wrapper automatically handles token refresh
- If this error persists, re-authenticate

### "Network Error"
- Check internet connectivity
- Verify Google Voice API is not experiencing outages
- Check firewall/proxy settings

## API Reference

### GoogleVoiceManager Methods

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `authenticate` | code, clientId, clientSecret | Void | Authenticate with OAuth |
| `startPolling` | interval (optional) | Void | Start listening for updates |
| `stopPolling` | none | Void | Stop listening for updates |
| `getRecentCalls` | limit (optional) | [GoogleVoiceCall] | Get call history |
| `initiateCall` | phoneNumber | Void | Make a phone call |
| `getConversations` | none | [GoogleVoiceConversation] | Get all conversations |
| `getMessages` | phoneNumber | [GoogleVoiceMessage] | Get messages for contact |
| `sendMessage` | phoneNumber, text | Void | Send a text message |
| `getAllContacts` | none | [GoogleVoiceContact] | Get all contacts |
| `searchContacts` | query | [GoogleVoiceContact] | Search contacts by name |

## Advanced Usage

### Custom Credentials Store

Implement the `CredentialsStore` protocol for custom storage:

```swift
actor MyCustomStore: CredentialsStore {
    func save(_ credentials: GoogleVoiceCredentials) async throws {
        // Custom save logic
    }

    func load() async throws -> GoogleVoiceCredentials? {
        // Custom load logic
    }

    func delete() async throws {
        // Custom delete logic
    }
}

let customStore = MyCustomStore()
let client = GoogleVoiceClient(credentialsStore: customStore)
```

### Rate Limiting Handling

Implement retry logic with exponential backoff:

```swift
func callWithRetry(_ operation: () async throws -> Void, maxAttempts: Int = 3) async throws {
    var lastError: Error?
    
    for attempt in 0..<maxAttempts {
        do {
            try await operation()
            return
        } catch let error as GoogleVoiceError {
            if case .rateLimited = error {
                if attempt < maxAttempts - 1 {
                    let delay = pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = error
                    continue
                }
            }
            throw error
        }
    }
    
    if let error = lastError {
        throw error
    }
}
```

## Contributing

When modifying the Google Voice wrapper:

1. Update models in `GoogleVoiceModels.swift`
2. Update client methods in `GoogleVoiceClient.swift`
3. Update manager interface in `GoogleVoiceManager.swift`
4. Add tests in `GoogleVoiceTests.swift`
5. Update this documentation

## License

This wrapper is part of the ReLay project.
