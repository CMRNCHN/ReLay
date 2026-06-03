/// Schema version embedded in persisted state.
/// Increment when `SpatialState`'s Codable layout changes in a breaking way.
public enum StateVersion {
    public static let current = 1
}
