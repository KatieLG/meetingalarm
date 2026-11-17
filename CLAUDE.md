# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MeetingAlarm: a macOS 15+ menu bar app (SwiftUI + AppKit, Swift 6, no third-party dependencies) that reads Google Calendars directly via the Calendar API and escalates alerts for meetings that have a video link: overlay at 10 min, Join button at 2 min, full-screen takeover on every display at 30 s (thresholds configurable in Settings).

## Commands

The Xcode project is **generated** from `project.yml` by XcodeGen (`brew install xcodegen`); `MeetingAlarm.xcodeproj` is not committed. All Make targets run `xcodegen generate` first. Add new source files by dropping them under `MeetingAlarm/Sources` or `MeetingAlarm/Tests` (globbed by `project.yml`); don't edit the xcodeproj.

```sh
make build   # Debug build into ./build
make test    # unit tests (Swift Testing)
make run     # build, kill running instance, launch
make clean
```

Run a single test class/case:
```sh
xcodegen generate && xcodebuild -project MeetingAlarm.xcodeproj -scheme MeetingAlarm -destination 'platform=macOS' -derivedDataPath build test -only-testing:MeetingAlarmTests/AlertPlannerTests
```

Google OAuth credentials (only needed for the direct Google source; the Mac Calendar source needs none, just the `NSCalendarsFullAccessUsageDescription` Info.plist key set in `project.yml`): copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` (gitignored). `Config/App.xcconfig` includes it and injects `GOOGLE_CLIENT_ID/SECRET` into Info.plist (`GoogleClientID`/`GoogleClientSecret`), which `OAuthConfig.fromBundle` reads. Without them the app builds but cannot sign in. README.md has the Google Cloud setup steps.

Fake meetings for testing alerts (Debug builds): the **+11m / +2:10 / +0:40** buttons in the popover, or launch with `--args -debugMeetings 40,130,660` (seconds from now).

## Architecture

Data flows one way: **calendar sources → `MeetingStore` → `AlertCoordinator` → windows**. There are two interchangeable sources, usable together or separately: direct Google API (own OAuth client) and the macOS Calendar database via EventKit (`Calendar/SystemCalendarSource.swift`, no Google Cloud setup; accounts come from System Settings → Internet Accounts). Both normalise into `Meeting`, and `EventMapper.dedupe` merges duplicates by `alertKey`.

- `Auth/`: OAuth 2.0 with PKCE and a loopback HTTP server (`LoopbackServer`) for the redirect; refresh tokens stored per account in the login Keychain (`KeychainStore`). Multiple Google accounts are supported.
- `Calendar/`: `GoogleCalendarClient` fetches events; `EventMapper` converts Google models to `Meeting` (filters all-day, declined, OOO, focus-time) and dedupes the same event appearing across accounts; `JoinLinkExtractor` finds Meet/Zoom/Teams/etc. links. Only meetings with a `joinURL` ever alert.
- `Core/MeetingStore`: `@Observable`; owns accounts and the merged meeting list. Refreshes every 5 min, on wake (after a 5 s delay), and when `NWPathMonitor` reports the network returned. `allMeetings` = real + debug meetings.
- `Core/AlertPlanner`: **pure, nonisolated** logic (`phase(for:)`, `plan(...)`, `menuBarText`). Keep it free of UI/side effects, since it's the unit-tested core. `AlertSettings.current` reads thresholds from `UserDefaults` (keys in `Prefs`).
- `Core/AlertCoordinator`: 1 s timer tick that calls `AlertPlanner.plan` and pushes the result into `OverlayController` / `TakeoverController` (`UI/OverlayPanel.swift`, `UI/TakeoverWindow.swift`). The `clock` closure is injectable for tests. Dismissals are keyed by `Meeting.alertKey` (which changes when the meeting's start time changes, so moved meetings re-alert) and persisted in UserDefaults; overlay "×" hiding is in-memory only and does not suppress the takeover.
- `App/MeetingAlarmApp.swift`: `@main` plus app delegate wiring; it's an `LSUIElement` agent app (no Dock icon).

## Conventions

- `project.yml` sets `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, so types are MainActor-isolated by default. Pure/background types (e.g. `AlertPlanner`, `AlertSettings`) are explicitly marked `nonisolated`; do the same for new logic that must be usable off the main actor or from tests.
- Builds are ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`, hardened runtime off), so after rebuilds macOS may re-prompt for Keychain access.
- Tests use Swift Testing, with shared builders in `MeetingAlarm/Tests/Fixtures.swift`.
