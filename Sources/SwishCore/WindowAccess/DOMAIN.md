# Domain: WindowAccess

**Purpose:** Event interception and input capture at the macOS input layer.

## What Belongs Here
- `TitleBarInterceptor` (currently at app layer in Sources/Swish/)
- NSEvent monitoring and gesture input parsing
- Delegate protocol definitions for gesture dispatch

## What Does NOT Belong Here
- Any gesture semantics beyond raw event parsing
- Layout states or frame math
- AX frame manipulation

## Boundary Rule
This domain captures input and emits raw gesture signals. It has no opinions about what those signals mean.

## Note
TitleBarInterceptor currently lives at the app layer. If it contains no app-specific logic, it belongs here. Evaluate at migration time.
