# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

XKey is a native Swift/SwiftUI Vietnamese input method for macOS (12.0+), ported from the OpenKey C++ engine. It supports Telex, VNI, and Simple Telex input styles, multiple encodings (Unicode, TCVN3, VNI Windows), spell checking, macros, translation, and smart app-switching. It ships two input delivery modes:

- **XKey** (main app, `com.codetay.XKey`) — CGEvent injection, works everywhere without extra setup.
- **XKeyIM** (`com.codetay.inputmethod.XKey`) — an Input Method Kit (IMKit) bundle for smoother typing in Terminal/IDEs/Spotlight. Installed separately into `~/Library/Input Methods/`.

Both targets share the Vietnamese engine and settings via an App Group (`group.com.codetay.xkey` / `group.com.codetay.inputmethod.XKey`).

## Build & test commands

Xcode project: `XKey.xcodeproj`. Targets/schemes: `XKey`, `XKeyIM`, `XKeyTests`.

```bash
# Build release (app + optional XKeyIM bundling + DMG), output in Release/
./build_release.sh

# Common build_release.sh env toggles (see script header for full list)
ENABLE_CODESIGN=false ./build_release.sh      # skip code signing
ENABLE_XKEYIM=false ./build_release.sh        # skip building XKeyIM
ENABLE_NOTARIZE=true ./build_release.sh       # full release: notarize + auto GitHub release

# Run the full test suite (XKeyTests target)
xcodebuild test -project XKey.xcodeproj -scheme XKeyTests -destination 'platform=macOS'

# Run a single test class or method
xcodebuild test -project XKey.xcodeproj -scheme XKeyTests -destination 'platform=macOS' \
  -only-testing:XKeyTests/VNEngineTests
xcodebuild test -project XKey.xcodeproj -scheme XKeyTests -destination 'platform=macOS' \
  -only-testing:XKeyTests/VNEngineTests/testSomeCase
```

Prefer the XcodeBuildMCP tools over raw `xcodebuild` shell invocations when available (see MCP tool descriptions) — call `session_show_defaults` before the first build/test/run to confirm project/scheme/simulator, and use the macOS-specific workflow tools since this is a macOS app, not iOS.

Version is centralized in `Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) — `build_release.sh` reads it rather than Info.plist directly.

## Architecture

### Directory layout

```
Shared/                   # Code shared between XKey and XKeyIM targets (settings, app detection, logging)
XKey/
├── App/                  # AppDelegate, app entry point, Sparkle update delegate
├── Core/
│   ├── Engine/           # VNEngine and the Vietnamese typing pipeline (see below)
│   ├── Models/           # Preferences, VNCharacter/VNCharacterMap, vowel validation
│   └── Translation/      # TranslationService + provider implementations (Google/Tencent/Volcano)
├── EventHandling/        # CGEventTap capture, injection, secure-input handling
├── InputMethod/          # XKeyInputController — bridges IMKit-style flow into the shared engine
├── UI/                   # SwiftUI settings window, status bar, overlays, toolbars
└── Utilities/            # iCloud sync, input source switching, misc helpers
XKeyIM/                   # Separate IMKit target: main.swift + XKeyIMController (IMKInputController)
XKeyTests/                # XCTest suite (XCTest, not Swift Testing)
```

### Typing pipeline (CGEvent mode)

1. `EventTapManager` installs a `CGEventTap` (HID or session level) and forwards key events to its delegate.
2. `KeyboardEventHandler` (implements `EventTapManager.EventTapDelegate`) owns a `VNEngine` instance and a `CharacterInjector`. It exposes engine settings as `@Published` properties (input method, code table, spell check, quick typing, macros, smart switch, etc.) — each setter calls `updateEngineSettings()` to push state into the engine.
3. `InputProcessor` maps a raw keystroke + input method (Telex/VNI/Simple Telex/Adaptive) to a `KeyAction` (append vowel/consonant, add tone/circumflex/breve/horn, double-letter transform, word break).
4. `VNEngine` (in `Core/Engine/`, split across `VNEngine*.swift` files by concern — Advanced, EnglishDetection, Macro, Settings, SmartSwitch, SpellCheck) holds the typing state machine, ported from OpenKey's C++ `Engine.h`/`DataType.h` (bit-mask constants like `TONE_MASK`, `MARK1_MASK`..`MARK5_MASK` mirror the original). `TypingBuffer` and `VNWordBuffer` are the unified single-source-of-truth buffers for raw keystrokes + processed output; `TypingHistory` backs the undo/restore feature.
5. `CharacterInjector` / `AdvancedInjectionMethods` send the resulting text back to the focused app (Fast/Slow/Selection/Autocomplete/AX-Direct/Passthrough strategies — selectable globally or per app via Window Title Rules).

### XKeyIM (Input Method Kit mode)

`XKeyIM/XKeyIMController.swift` subclasses `IMKInputController` and drives the *same* `VNEngine`/buffer code from `XKey/Core/Engine/` (those files must have XKeyIM target membership in the Xcode project). Settings flow one-way from XKey.app to XKeyIM through the shared App Group `UserDefaults` suite — XKeyIM has no settings UI of its own. See [XKeyIM/README.md](XKeyIM/README.md) for the manual Xcode target setup (App Group entitlements, provisioning profile) required before XKeyIM can build.

### Settings persistence

Dual-storage: primary is App Group `UserDefaults` (shared between XKey and XKeyIM, enables real-time sync), with `UserDefaults.standard` as an automatic backup/restore fallback if the App Group container is ever reset. `SharedSettings.swift` (Shared/ and XKey/Utilities/) centralizes this. Optional iCloud KVS sync layer (`iCloudSyncManager`, `SyncTombstoneStore`) is gated by the `ENABLE_ICLOUD_ENTITLEMENT` build flag and requires a matching Developer ID signing cert (see comment in `build_release.sh`).

### Window Title Rules

Per-app/per-window-title behavior overrides (marked text on/off, injection method, injection delays, text-send method, auto input-source switch) are matched against the frontmost app's bundle ID + window title (contains/starts-with/ends-with/exact/regex). This is how XKey works around problematic web apps (Google Docs/Sheets/Slides, Notion, Figma, etc.) — see `WindowTitleRulesView.swift` and `AppBehaviorDetector.swift`.

### Translation feature

`TranslationService` dispatches to provider implementations in `Core/Translation/` (`GoogleTranslateProvider`, `TencentTransmartProvider`, `VolcanoEngineProvider`) conforming to `TranslationProvider`, with automatic fallback to the next enabled provider on failure/empty result. Two independent directions (source→target, target→source) each have their own replace/clipboard/popup toggles, driven by `TranslationToolbarController`/`TranslationResultOverlay`.

## Notes for making changes

- The bit-mask engine internals (`VNEngine.swift` constants, `VNCharacterMap`) are a direct port from OpenKey's C++ source — preserve the mask semantics when touching tone/mark logic rather than re-deriving them.
- Any file used by the Vietnamese engine that XKeyIM also needs must have its Xcode **Target Membership** checkbox enabled for the `XKeyIM` target, or the IMKit build breaks with "Cannot find VNEngine"-style errors.
- Verbose engine logging (`KeyboardEventHandler.verboseEngineLogging`) is expensive — it's off by default and should stay opt-in for debugging.
- `XKeyTests` uses XCTest (not Swift Testing/`@Test`) — follow the existing `XCTestCase` + `func test...()` convention when adding tests.
