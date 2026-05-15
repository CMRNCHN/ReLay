# CURRENT_TASK.md

## Task Title

Normalize stale project naming to ReLay

## Request Date

2026-05-15

## Status

Completed

## Objective

Keep useful historical material, rename stale project-name references to `ReLay`, and remove legacy material that no longer helps.

## Start-Of-Task Review Summary

- reviewed the required governance and RepoDock task surfaces
- scanned the repository for legacy names including `Swish`, `SwishCore`, `Swish.app`, and `Re-Lay`
- separated active metadata from stale archival scaffolding

## Constraints

- keep the cleanup scoped to naming and stale-material removal
- avoid changing live runtime source behavior
- preserve historical context only where it still adds value

## Files Expected To Change

- `AppBundleContents/Info.plist`
- `.ai/REPODOCK/*`
- stale legacy docs under `Sources/SwishCore/`

## Files Actually Changed

- `AppBundleContents/Info.plist`
- `.ai/REPODOCK/TASKS/CURRENT_TASK.md`
- `.ai/REPODOCK/HANDOFFS/LATEST_HANDOFF.md`
- `.ai/REPODOCK/LOGS/2026-05-07_air-governance-init.md`
- `.ai/REPODOCK/LOGS/2026-05-15_name-normalization.md`
- deleted legacy `Sources/SwishCore/*/DOMAIN.md` files

## Verification Performed

- searched the repo for legacy names
- confirmed the remaining actionable stale references were in bundle metadata and dead legacy scaffolding
- removed the unused `Sources/SwishCore` domain-doc tree and updated name-bearing metadata

## Architecture Boundaries Touched

- documentation and metadata only

## Behavior Changes

- old bundle metadata now presents the app as `ReLay`
- stale `SwishCore` scaffolding is removed so current structure is less ambiguous

## Risks / Follow-Ups

- `AppBundleContents/Info.plist` is legacy bundle material and may not be part of the current SwiftPM launch path
- live source/module names like `ReLayCore` remain unchanged, by design

## Next Task Recommendation

Fix the current `TitleBarInterceptor.swift` compile failure, then add semantic-core tests.
