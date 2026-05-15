# LATEST_HANDOFF.md

**Project:** ReLay
**Last Updated:** 2026-05-15
**Session Type:** naming normalization and stale-material cleanup

---

## Objective

Keep useful historical material, rename stale project references to `ReLay`, and remove legacy content that no longer adds value.

## What Changed

- updated old bundle metadata in `AppBundleContents/Info.plist` from `Swish` to `ReLay`
- removed the unused legacy `Sources/SwishCore` domain-doc scaffold
- normalized remaining useful historical log references from old product names to `ReLay`

## Boundaries Touched

- metadata
- documentation
- unused legacy scaffolding

## Behavioral Impact

- no runtime source behavior changed
- repository naming is less ambiguous
- stale architecture placeholders no longer compete with the actual `Sources/ReLayCore` layout

## Risks Introduced

- `AppBundleContents/Info.plist` may not be part of the active SwiftPM runtime path
- no compile or runtime validation was performed in this cleanup task

## Follow-Up Pressure

- fix the current compile break before doing broader cleanup
- only rename deeper code/module identifiers if there is a concrete product or packaging reason

## Next Recommended Task

Fix the compile failure in `TitleBarInterceptor.swift`, then add focused semantic-core tests.
