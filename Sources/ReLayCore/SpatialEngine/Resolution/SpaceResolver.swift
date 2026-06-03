import CoreGraphics

// Placeholder for macOS Spaces integration.
// CGSSpace APIs require private entitlements not available in the App Store sandbox.
// This layer is reserved for future implementation when ReLay gains those entitlements
// or a user-space proxy is introduced.
struct SpaceResolver {
    // Returns nil until space-aware routing is implemented.
    func activeSpaceID() -> Int? { nil }

    // Whether two spatial frames are on the same macOS Space.
    // Always returns true until space awareness is wired in.
    func sameSpace(_ a: SpatialFrame, _ b: SpatialFrame) -> Bool { true }
}
