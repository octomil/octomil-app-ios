# iOS App Bloat Reduction Track

Reviewer: @tai

## Goal

Make the companion iOS app build against one SDK source and remove duplicated app-local behavior that should be shared with the SDK.

## Findings

- The Xcode project source phase appears stale relative to the Swift files in `OctomilApp/`.
- `Package.swift`, `project.yml`, Xcode project package pins, and lockfiles disagree on Swift version, iOS deployment target, and `octomil-ios` revision.
- App profile logic explicitly says it duplicates SDK profile logic.
- App-local deep-link parsing accepts different URL shapes than the SDK deep-link parser.
- App-local model capability and installed-model state duplicate SDK/generated state.
- Xcode/SwiftPM build output accounts for most local app size.

## Proposed Cleanup

- Regenerate or repair the Xcode project so all referenced Swift files are compiled consistently.
- Pick one package pin source and remove stale lock/pin drift.
- Move profile and deep-link parsing into shared SDK APIs.
- Replace app-local model capability/install records with SDK/generated types where possible.
- Add a documented cleanup path for ignored build output.

## Validation

```bash
rg --files OctomilApp -g '*.swift'
rg -n 'AppProfile|DeepLinkHandler|ModelCapability|StoredModel|revision|branch|SWIFT_VERSION|IPHONEOS_DEPLOYMENT_TARGET' Package.swift project.yml OctomilApp.xcodeproj OctomilApp
xcodebuild -list
```
