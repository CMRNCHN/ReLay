# SYSTEM_OVERVIEW.md

## Runtime Flow

`GestureEngine -> SpatialTransitionEngine -> LayoutResolver -> LayoutOrchestrator -> WindowStateStore`

## Core Architectural Position

ReLay is a semantic workspace relayout engine with deterministic transitions and explicit ownership boundaries.

## Current Areas Of Focus

- gesture ingress reliability
- transition determinism
- state-store correctness
- runtime observability

## Source Of Truth

- governance constraints: `.ai/GOVERNANCE/*`
- current repository state: `.ai/REPODOCK/CURRENT/PROJECT_STATE.md`
- current task record: `.ai/REPODOCK/TASKS/CURRENT_TASK.md`
- latest handoff: `.ai/REPODOCK/HANDOFFS/LATEST_HANDOFF.md`
