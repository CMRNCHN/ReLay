# Task Log - Name Normalization

**Date:** 2026-05-15
**Type:** Cleanup / Documentation

---

## Objective

Normalize stale legacy names to `ReLay` where the material is still useful and remove legacy scaffolding that no longer serves the current repository.

## Changes

- updated legacy app bundle metadata from `Swish` to `ReLay`
- removed the stale `Sources/SwishCore` domain-doc tree
- cleaned remaining useful historical log references to use the current product name

## Boundaries Touched

- metadata and documentation only

## Risks Introduced

- none to live runtime behavior

## Verification

- searched the repository for stale product-name references
- confirmed the cleanup targets were metadata or unused legacy docs
