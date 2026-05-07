# Domain: Shared

**Purpose:** Value types and utilities with no domain-specific ownership that are used across multiple SwishCore domains.

## What Belongs Here
- Pure Swift extensions that multiple domains use (e.g., CGRect helpers)
- Shared protocols with no single domain owner
- Type aliases that cross domain boundaries

## Design Constraints
- Must have zero dependencies on other SwishCore domains
- Must contain no AX, Cocoa, or AppKit imports
- If a utility is only used by one domain, it belongs in that domain — not here

## Status
No shared utilities yet. Directory established for Air indexing.
