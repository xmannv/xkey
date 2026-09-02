# Tap Host Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cho tầng tap một hợp đồng host tường minh — thiếu một mảnh là lỗi biên dịch, không phải bug report — và dời máy móc hỗ trợ tap ra khỏi `AppDelegate` để cả XKey.app lẫn XKeyIM dùng chung một bản duy nhất.

**Architecture:** Hai kiểu mới. `TapEnvironment` gom mọi thứ tầng tap ĐỌC, bắt buộc khi khởi tạo. `TapEventSource` gom mọi thứ host ĐẨY vào (app switch, AX focus/title, mouse click, overlay), **dời cơ học** từ `AppDelegate` sang tầng dùng chung. `AppDelegate` và `TapController` cùng cung cấp cả hai.

**Tech Stack:** Swift, AppKit, Accessibility API, CoreGraphics event taps, InputMethodKit, XCTest.

**Spec:** `docs/superpowers/specs/2026-08-29-tap-host-contract-design.md`

## Global Constraints

- Branch `feat/xkeyim-event-tap` (tiếp tục nhánh hiện có, HEAD `e3d4a92`). Commit message: English, Conventional Commits, **KHÔNG** AI attribution trailer.
- **KHÔNG** ⌘R/⌘B target XKeyIM trong Xcode GUI — bundle DerivedData trùng `InputMethodConnectionName` với bản đã cài làm macOS dựng lại toàn bộ enabled input sources.
- `IMBUILD` = `xcodebuild build -project XKey.xcodeproj -target XKeyIM -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5` → phải in `** BUILD SUCCEEDED **`.
- `APPBUILD` = như trên với `-target XKey`.
- `XCTEST` = `xcodebuild test -project XKey.xcodeproj -scheme XKeyTests -configuration Debug CODE_SIGNING_ALLOWED=NO` (Bash timeout 600000). Đỏ môi trường **được phép bỏ qua, chỉ đúng hai nhóm này**: `TranslationProviderTests.*` (4), `iCloudSyncManagerTests.*` (4). `ScreenSimulationTests` in "recorded an expected failure" hai lần là bình thường (rào `XCTExpectFailure`), các test đó PASS.
- File trong thư mục `XKeyIM/` **tự động** vào target XKeyIM (`PBXFileSystemSynchronizedRootGroup`) — **không** thêm entry pbxproj cho chúng. File ngoài thư mục đó phải thêm tay, theo khuôn `IMTAP01`…`IMTAP06` đã có. Sau mỗi lần sửa: `plutil -lint XKey.xcodeproj/project.pbxproj` phải OK.
- **Luật vàng của mọi task dời code (T4–T7): dời CƠ HỌC, giữ nguyên hành vi từng dòng.** Không đổi tên, không gộp, không "tiện tay cải tiến", không sửa bug nhìn thấy dọc đường — ghi vào báo cáo thay vì sửa. Mọi thay đổi hành vi trong bước dời là lỗi.
- Sau **mỗi** task dời: `APPBUILD` + `IMBUILD` + `XCTEST` phải xanh trước khi commit.
- `Version.xcconfig` có thay đổi uncommitted từ trước (build number) — **không đụng, không commit**.

---

### Task 1: Dọn code đo tạm

**Files:**
- Modify: `XKey/EventHandling/EventTapManager.swift` (uncommitted), `XKeyIM/TapController.swift`

**Interfaces:**
- Produces: cây làm việc sạch, không còn log đo tạm. Không API mới.

Bối cảnh: đợt đo thực địa đã thêm log tạm. Log trong `EventTapManager.swift` còn uncommitted; log trong `TapController.swift` đã lỡ đi kèm commit `f920cb6` vì nằm chung file với một fix.

- [ ] **Step 1: Bỏ log tạm trong `EventTapManager.swift`**

```bash
git checkout XKey/EventHandling/EventTapManager.swift
git status --short | grep -v "^??"
```
Expected: chỉ còn `M Version.xcconfig`.

- [ ] **Step 2: Bỏ 3 dòng log ACTIVATION trong `TapController.swift`**

Xoá ba dòng `IMKitDebugger.shared.log(...)` có `category: "ACTIVATION"` trong `imeDidActivate()`, `imeDidDeactivate(stillSelected:)`, `inputSourceChanged(isXKeyIM:)`. **Giữ** các log `category: "TAP"` (`Tap ARMED` / `Tap DISARMED` / `Tap failed to start`) — chúng là log vận hành, không phải đo tạm.

Verify: `grep -c 'category: "ACTIVATION"' XKeyIM/TapController.swift` → `0`; `grep -c 'category: "TAP"' XKeyIM/TapController.swift` → `3`.

- [ ] **Step 3: Build + commit**

Run: `IMBUILD` → BUILD SUCCEEDED.

```bash
git add XKeyIM/TapController.swift
git commit -m "chore(xkeyim): remove temporary activation measurement logging"
```

---

### Task 2: `TapEnvironment` — hợp đồng đọc

**Files:**
- Create: `Shared/TapEnvironment.swift`
- Modify: `XKey.xcodeproj/project.pbxproj`
- Test: `XKeyTests/TapEnvironmentTests.swift` (Create)

**Interfaces:**
- Produces:
  ```swift
  struct TapEnvironment {
      let preferences: Preferences
      let overlayAppName: () -> String?
      let remoteDesktopInjectMode: () -> Bool
      let windowTitleRulesEnabled: Bool
      let vietnameseEnabled: Bool
      let axMessagingTimeout: Double
      let hotkeys: TapHotkeys
      init(preferences:overlayAppName:remoteDesktopInjectMode:windowTitleRulesEnabled:vietnameseEnabled:axMessagingTimeout:hotkeys:)
  }

  struct TapHotkeys {
      enum Action { case supported(() -> Void), unsupportedInThisHost(reason: String) }
      let toggleVietnamese: Action
      let undoTyping: Action
      let convertTool: Action
      let translate: Action
      let translateToSource: Action
      let toolbar: Action
      let toggleExclusion: Action
      let toggleWindowRules: Action
      let debugWindow: Action
  }
  ```
  T3 (AppDelegate) và T4 (TapController) cùng dựng nó. Không trường nào có giá trị mặc định — thiếu là lỗi biên dịch, đó là toàn bộ mục đích.

Ghi chú: `preferences` dùng thẳng `Preferences` (đã có, `SharedSettings.loadPreferences()` trả về nó) vì `KeyboardEventHandler.applyAllSettings` nhận đúng bộ trường đó. Không dựng kiểu mới song song.

- [ ] **Step 1: Viết test fail trước**

Tạo `XKeyTests/TapEnvironmentTests.swift`:

```swift
import XCTest
@testable import XKey

/// TapEnvironment exists so a host that forgets a dependency fails to COMPILE
/// rather than shipping a silently-wrong default. These tests pin the two
/// properties that carry that guarantee: every field is populated from the
/// caller, and an unsupported hotkey action is a stated decision rather than nil.
final class TapEnvironmentTests: XCTestCase {

    private func makeEnvironment(vietnameseEnabled: Bool = true) -> TapEnvironment {
        TapEnvironment(
            preferences: Preferences(),
            overlayAppName: { "Raycast" },
            remoteDesktopInjectMode: { true },
            windowTitleRulesEnabled: true,
            vietnameseEnabled: vietnameseEnabled,
            axMessagingTimeout: 0.25,
            hotkeys: TapHotkeys(
                toggleVietnamese: .supported({}),
                undoTyping: .supported({}),
                convertTool: .unsupportedInThisHost(reason: "test"),
                translate: .unsupportedInThisHost(reason: "test"),
                translateToSource: .unsupportedInThisHost(reason: "test"),
                toolbar: .unsupportedInThisHost(reason: "test"),
                toggleExclusion: .supported({}),
                toggleWindowRules: .supported({}),
                debugWindow: .unsupportedInThisHost(reason: "test")
            )
        )
    }

    func testProvidersAreCalledNotDefaulted() {
        let env = makeEnvironment()
        XCTAssertEqual(env.overlayAppName(), "Raycast")
        XCTAssertTrue(env.remoteDesktopInjectMode())
    }

    func testCarriesVietnameseStateVerbatim() {
        XCTAssertFalse(makeEnvironment(vietnameseEnabled: false).vietnameseEnabled)
        XCTAssertTrue(makeEnvironment(vietnameseEnabled: true).vietnameseEnabled)
    }

    /// An action a host cannot perform must say so, with a reason a maintainer can
    /// read — the failure this whole type exists to prevent is a nil closure that
    /// looks like an oversight and behaves like a feature gap.
    func testUnsupportedActionCarriesAReason() {
        let env = makeEnvironment()
        guard case .unsupportedInThisHost(let reason) = env.hotkeys.convertTool else {
            return XCTFail("expected an explicitly unsupported action")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testSupportedActionRuns() {
        var fired = false
        let action = TapHotkeys.Action.supported({ fired = true })
        if case .supported(let run) = action { run() }
        XCTAssertTrue(fired)
    }
}
```

- [ ] **Step 2: Chạy test — phải FAIL**

Run: `XCTEST 2>&1 | grep -E "TapEnvironment|error:" | head -5`
Expected: lỗi biên dịch "cannot find 'TapEnvironment' in scope".

- [ ] **Step 3: Viết `Shared/TapEnvironment.swift`**

```swift
//
//  TapEnvironment.swift
//
//  Everything the event-tap layer READS from whichever process hosts it.
//
//  The tap layer runs in two processes — XKey.app (CGEvent mode) and XKeyIM
//  (the input method). It was originally written against XKey.app's AppDelegate
//  and reached for that host's state through optional providers and mutable
//  singletons. When XKeyIM began hosting the same code, every one of those
//  optionals silently took a default instead of failing: wrong input method,
//  wrong code table, excluded apps ignored, user rules dead, and a per-keystroke
//  AX snapshot on the tap thread that froze typing.
//
//  So: no field here has a default. A host that forgets one does not compile.
//  A dependency a host genuinely cannot satisfy is stated as such, with a reason.
//

import Foundation

struct TapHotkeys {
    /// A hotkey action, or an explicit statement that this host cannot perform it.
    /// XKeyIM has no settings window, no toolbar and no translation UI; saying so
    /// here keeps "XKeyIM lacks the convert tool" a decision a reader can find,
    /// rather than a nil closure that looks like an oversight.
    enum Action {
        case supported(() -> Void)
        case unsupportedInThisHost(reason: String)
    }

    let toggleVietnamese: Action
    let undoTyping: Action
    let convertTool: Action
    let translate: Action
    let translateToSource: Action
    let toolbar: Action
    let toggleExclusion: Action
    let toggleWindowRules: Action
    let debugWindow: Action
}

struct TapEnvironment {
    /// Everything KeyboardEventHandler.applyAllSettings needs: input method, code
    /// table, macro, spell-check, custom consonants, excluded apps, undo.
    let preferences: Preferences

    /// Name of the visible overlay launcher (Spotlight/Raycast/Alfred), or nil.
    /// Left unprovided this returns nil forever, which is not merely "no overlay":
    /// it stops AppBehaviorDetector ever producing an overlay method, so the
    /// injection method is re-detected — a full AX snapshot — on every keystroke.
    let overlayAppName: () -> String?

    /// Whether the user opted into injecting Vietnamese into remote desktop
    /// clients via clipboard paste rather than passing through.
    let remoteDesktopInjectMode: () -> Bool

    /// Master switch for Window Title Rules.
    let windowTitleRulesEnabled: Bool

    /// Vietnamese on/off at the moment the tap arms.
    let vietnameseEnabled: Bool

    /// Ceiling for every AX call the tap thread makes. Without it the system
    /// default (seconds) applies and one hung app is enough for macOS to disable
    /// the tap — the primitive behind every freeze we have chased.
    let axMessagingTimeout: Double

    let hotkeys: TapHotkeys

    init(preferences: Preferences,
         overlayAppName: @escaping () -> String?,
         remoteDesktopInjectMode: @escaping () -> Bool,
         windowTitleRulesEnabled: Bool,
         vietnameseEnabled: Bool,
         axMessagingTimeout: Double,
         hotkeys: TapHotkeys) {
        self.preferences = preferences
        self.overlayAppName = overlayAppName
        self.remoteDesktopInjectMode = remoteDesktopInjectMode
        self.windowTitleRulesEnabled = windowTitleRulesEnabled
        self.vietnameseEnabled = vietnameseEnabled
        self.axMessagingTimeout = axMessagingTimeout
        self.hotkeys = hotkeys
    }
}
```

- [ ] **Step 4: Thêm vào pbxproj**

`Shared/TapEnvironment.swift` phải vào **cả bốn** target (XKey, XKeyIM, XKeyTests, và target thứ tư nếu có — đối chiếu bằng `grep -c "AXHelper.swift in Sources" XKey.xcodeproj/project.pbxproj`, phải ra cùng số). Test file vào XKeyTests. Dùng tiền tố ID mới, ví dụ `TAPENV`.

Verify: `plutil -lint XKey.xcodeproj/project.pbxproj` OK; `grep -c "TapEnvironment.swift in Sources" XKey.xcodeproj/project.pbxproj` bằng đúng số của `AXHelper.swift`.

- [ ] **Step 5: Chạy test — phải PASS**

Run: `XCTEST 2>&1 | tail -5` → `** TEST SUCCEEDED **` (trừ hai nhóm môi trường).

- [ ] **Step 6: Commit**

```bash
git add Shared/TapEnvironment.swift XKeyTests/TapEnvironmentTests.swift XKey.xcodeproj/project.pbxproj
git commit -m "feat(tap): add an explicit environment contract for the event tap layer"
```

---

### Task 3: `TapEnvironment` được áp dụng — một hàm apply duy nhất

**Files:**
- Modify: `Shared/TapEnvironment.swift`
- Modify: `XKey/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `TapEnvironment` (T2).
- Produces:
  ```swift
  extension TapEnvironment {
      func apply(to handler: KeyboardEventHandler, tap: EventTapManager)
  }
  ```
  T4 (TapController) gọi đúng hàm này. Đây là chỗ DUY NHẤT biết cách nối environment vào tầng tap — hai host không được tự nối tay.

- [ ] **Step 1: Viết `apply(to:tap:)`**

Thêm vào `Shared/TapEnvironment.swift`:

```swift
extension TapEnvironment {
    /// The single place that wires an environment into the tap layer. Both hosts
    /// call this and nothing else, so the two can never drift apart by wiring
    /// different subsets — the failure this whole contract exists to end.
    func apply(to handler: KeyboardEventHandler, tap: EventTapManager) {
        // Bound every AX call the tap thread makes before anything can make one.
        AXHelper.setGlobalMessagingTimeout(axMessagingTimeout)

        let detector = AppBehaviorDetector.shared
        detector.overlayAppNameProvider = overlayAppName
        detector.remoteDesktopInjectModeProvider = remoteDesktopInjectMode
        detector.windowTitleRulesEnabled = windowTitleRulesEnabled
        detector.loadCustomRules()

        handler.applyAllSettings(
            inputMethod: preferences.inputMethod,
            codeTable: preferences.codeTable,
            modernStyle: preferences.modernStyle,
            spellCheckEnabled: preferences.spellCheckEnabled,
            quickTelexEnabled: preferences.quickTelexEnabled,
            quickStartConsonantEnabled: preferences.quickStartConsonantEnabled,
            quickEndConsonantEnabled: preferences.quickEndConsonantEnabled,
            upperCaseFirstChar: preferences.upperCaseFirstChar,
            capitalizeOnlyAfterSpace: preferences.capitalizeOnlyAfterSpace,
            restoreIfWrongSpelling: preferences.restoreIfWrongSpelling,
            skipRestoreForUppercaseVietnameseAbbreviations: preferences.skipRestoreForUppercaseVietnameseAbbreviations,
            customConsonants: preferences.customConsonants,
            macroEnabled: preferences.macroEnabled,
            macroInEnglishMode: preferences.macroInEnglishMode,
            autoCapsMacro: preferences.autoCapsMacro,
            addSpaceAfterMacro: preferences.addSpaceAfterMacro,
            yieldMacroToSystemReplacement: preferences.yieldMacroToSystemReplacement,
            smartSwitchEnabled: preferences.smartSwitchEnabled,
            excludedApps: preferences.excludedApps,
            undoTypingEnabled: preferences.undoTypingEnabled
        )
        handler.setVietnamese(vietnameseEnabled)

        applyHotkeys(to: tap)
    }

    private func applyHotkeys(to tap: EventTapManager) {
        func callback(_ action: TapHotkeys.Action) -> (() -> Void)? {
            if case .supported(let run) = action { return run }
            return nil
        }
        tap.onToggleHotkey = callback(hotkeys.toggleVietnamese)
        tap.onToolbarHotkey = callback(hotkeys.toolbar)
        tap.onConvertToolHotkey = callback(hotkeys.convertTool)
        tap.onTranslationHotkey = callback(hotkeys.translate)
        tap.onTranslateToSourceHotkey = callback(hotkeys.translateToSource)
        tap.onDebugHotkey = callback(hotkeys.debugWindow)
        tap.onToggleExclusionHotkey = callback(hotkeys.toggleExclusion)
    }
}
```

Nếu tên trường trong `Preferences` khác với danh sách trên, dùng tên thật (`grep -n "var " XKey/Core/Models/Preferences.swift`) và ghi lại trong báo cáo. Nếu `EventTapManager` còn callback hotkey khác (`onUndoTypingHotkey` trả `Bool`), nối nó theo đúng chữ ký thật; `undoTyping` trong `TapHotkeys` khai báo `() -> Void` nên nếu chữ ký thật là `() -> Bool` thì đổi kiểu trường đó trong T2 và cập nhật test cho khớp — ghi rõ trong báo cáo.

- [ ] **Step 2: `AppDelegate` dựng và áp dụng environment**

Trong `setupKeyboardHandling()`, sau khi `keyboardHandler` và `eventTapManager` đã tồn tại, thay các lời gọi rời rạc đang thiết lập những thứ này (`AXHelper.setGlobalMessagingTimeout` ở `:192`, `loadCustomRules()` ở `:201`, hai provider ở `:216-223`) bằng một environment duy nhất:

```swift
        let environment = TapEnvironment(
            preferences: SharedSettings.shared.loadPreferences(),
            overlayAppName: { OverlayAppDetector.shared.getVisibleOverlayAppName() },
            remoteDesktopInjectMode: { SharedSettings.shared.remoteDesktopInjectMode },
            windowTitleRulesEnabled: SharedSettings.shared.loadPreferences().windowTitleRulesEnabled,
            vietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
            axMessagingTimeout: 0.25,
            hotkeys: TapHotkeys(
                toggleVietnamese: .supported({ [weak self] in self?.toggleVietnameseFromHotkey() }),
                undoTyping: .supported({ [weak self] in _ = self?.undoTypingFromHotkey() }),
                convertTool: .supported({ [weak self] in self?.openConvertTool() }),
                translate: .supported({ [weak self] in self?.triggerTranslation() }),
                translateToSource: .supported({ [weak self] in self?.triggerTranslateToSource() }),
                toolbar: .supported({ [weak self] in self?.toggleTempOffToolbar() }),
                toggleExclusion: .supported({ [weak self] in self?.toggleExclusionRules() }),
                toggleWindowRules: .supported({ [weak self] in self?.toggleWindowTitleRules() }),
                debugWindow: .supported({ [weak self] in self?.toggleDebugWindowFromMenu() })
            )
        )
        environment.apply(to: keyboardHandler!, tap: eventTapManager!)
```

Tên hành động ở trên là **chỗ dành sẵn**: dùng đúng tên hàm mà `AppDelegate` hiện đang gán cho `onToggleHotkey`, `onUndoTypingHotkey`, `onConvertToolHotkey`, `onTranslationHotkey`, `onTranslateToSourceHotkey`, `onToolbarHotkey`, `onToggleExclusionHotkey`, `onDebugHotkey` (tìm bằng `grep -n "eventTapManager?.on" XKey/App/AppDelegate.swift`). Không đổi hành vi hotkey nào.

Xoá các lời gọi đã bị `apply` thay thế, để không có hai nguồn thiết lập cùng một state.

- [ ] **Step 3: Build + test**

Run: `APPBUILD` → BUILD SUCCEEDED; `IMBUILD` → BUILD SUCCEEDED; `XCTEST 2>&1 | tail -5` → TEST SUCCEEDED (trừ hai nhóm môi trường).

- [ ] **Step 4: Commit**

```bash
git add Shared/TapEnvironment.swift XKey/App/AppDelegate.swift
git commit -m "refactor(app): wire the tap layer through the environment contract"
```

---

### Task 4: XKeyIM cung cấp `TapEnvironment`

**Files:**
- Modify: `XKeyIM/TapController.swift`

**Interfaces:**
- Consumes: `TapEnvironment.apply(to:tap:)` (T3).
- Produces: không API mới. Đây là task chữa **cú freeze Raycast/Spotlight** và các lỗ đúng-sai lớn nhất của XKeyIM.

- [ ] **Step 1: Dựng environment trong `arm()`**

Trong `TapController.arm()`, thay lời gọi `handler.setVietnamese(...)` hiện có bằng một environment đầy đủ:

```swift
        let environment = TapEnvironment(
            preferences: SharedSettings.shared.loadPreferences(),
            overlayAppName: { OverlayAppDetector.shared.getVisibleOverlayAppName() },
            remoteDesktopInjectMode: { SharedSettings.shared.remoteDesktopInjectMode },
            windowTitleRulesEnabled: SharedSettings.shared.loadPreferences().windowTitleRulesEnabled,
            vietnameseEnabled: SharedSettings.shared.vietnameseEnabled,
            axMessagingTimeout: 0.25,
            hotkeys: TapHotkeys(
                // XKeyIM owns the keyboard when armed, so the hotkeys that only
                // need the engine work here exactly as they do in XKey.app.
                toggleVietnamese: .supported({ [weak self] in self?.toggleVietnameseFromHotkey() }),
                undoTyping: .supported({}),
                // The rest drive windows XKeyIM does not have. Stated, not nil.
                convertTool: .unsupportedInThisHost(reason: "XKeyIM has no window UI; open XKey to use the convert tool"),
                translate: .unsupportedInThisHost(reason: "XKeyIM has no window UI; open XKey to translate"),
                translateToSource: .unsupportedInThisHost(reason: "XKeyIM has no window UI; open XKey to translate"),
                toolbar: .unsupportedInThisHost(reason: "the temp-off toolbar is an XKey.app window"),
                toggleExclusion: .supported({}),
                toggleWindowRules: .supported({}),
                debugWindow: .unsupportedInThisHost(reason: "the debug window is an XKey.app window")
            )
        )
        environment.apply(to: handler, tap: manager)
```

Thêm vào `TapController` một hành động toggle thật:

```swift
    /// Flip the shared Vietnamese state and push it to both channels, so the
    /// hotkey, the input-method menu and XKey.app never disagree.
    private func toggleVietnameseFromHotkey() {
        let enabled = !SharedSettings.shared.vietnameseEnabled
        SharedSettings.shared.vietnameseEnabled = enabled
        applyVietnameseEnabled(enabled)
    }
```

Với `undoTyping`, `toggleExclusion`, `toggleWindowRules`: nếu hành động thật chỉ cần state dùng chung (không cần UI), cài đặt nó; nếu cần UI, đổi thành `.unsupportedInThisHost` kèm lý do. Quyết định từng cái và **ghi lý do vào báo cáo** — chỗ này là bản chất của hợp đồng, không được đoán bừa.

- [ ] **Step 2: Cấu hình hotkey cũng phải được nạp**

`apply(to:tap:)` nối *hành động*; *phím tắt* nào kích hoạt chúng nằm ở `tap.toggleHotkey`, `tap.undoTypingHotkey`… Kiểm `AppDelegate` gán chúng ở đâu (`grep -n "eventTapManager?.toggleHotkey\|\.undoTypingHotkey" XKey/App/AppDelegate.swift`) và nạp cùng nguồn (`SharedSettings`) trong `TapController`. Nếu việc này làm `apply` phình ra, đưa cấu hình phím vào `TapHotkeys` như các trường `Hotkey?` bên cạnh action tương ứng — và cập nhật T2's test cho khớp. Ghi lựa chọn vào báo cáo.

- [ ] **Step 3: Build + test**

Run: `IMBUILD`, `APPBUILD`, `XCTEST` → tất cả xanh.

- [ ] **Step 4: Commit**

```bash
git add XKeyIM/TapController.swift
git commit -m "feat(xkeyim): supply the full tap environment when arming"
```

---

### Task 5: Sửa nhiễm chéo singleton tĩnh

**Files:**
- Modify: `XKey/EventHandling/KeyboardEventHandler.swift` (~:152-153)
- Test: `XKeyTests/TapOwnershipTests.swift` hoặc file mới

**Interfaces:** không API mới.

Bối cảnh: `KeyboardEventHandler.init()` gọi `VNEngine.setSharedMacroManager(macroManager)` và `VNEngine.setSharedSmartSwitchManager(smartSwitchManager)` — ghi vào state **tĩnh, toàn process**. Trong XKeyIM, `XKeyIMController` có engine marked-text riêng dùng chung hai singleton đó, nên hành vi macro/smart-switch của kênh marked-text đổi tuỳ theo tap đã từng arm hay chưa. Đó là ràng buộc ẩn giữa hai kênh lẽ ra độc lập.

- [ ] **Step 1: Xác định phạm vi thật**

```bash
grep -rn "setSharedMacroManager\|setSharedSmartSwitchManager\|_macroManager\|_smartSwitchManager" XKey Shared XKeyIM
```
Đọc kết quả và trả lời trong báo cáo: hai singleton này được ĐỌC ở đâu, và việc chúng bị ghi hai lần (một lần bởi `XKeyIMController`, một lần bởi `KeyboardEventHandler.init()`) đổi hành vi gì cụ thể.

- [ ] **Step 2: Chọn cách sửa nhỏ nhất và ghi lý do**

Hai hướng, chọn một dựa trên kết quả Step 1:
- Nếu chúng thực sự nên là một bản dùng chung toàn process: để nguyên, thêm comment nói rõ chủ ý và vì sao ghi lần thứ hai là vô hại.
- Nếu mỗi engine cần bản riêng: bỏ ghi vào static trong `init()`, truyền manager vào engine tương ứng.

Ghi quyết định + lý do vào báo cáo trước khi sửa.

- [ ] **Step 3: Test khẳng định hành vi đã chọn**

Viết một test pin đúng điều Step 2 kết luận (ví dụ: dựng `KeyboardEventHandler` không được đổi macro manager mà một engine khác đang dùng). Chạy trước khi sửa để thấy nó fail (nếu đang sai), rồi sửa cho pass.

- [ ] **Step 4: Build + test + commit**

Run: `APPBUILD`, `IMBUILD`, `XCTEST` → xanh.

```bash
git add -A XKey/EventHandling/KeyboardEventHandler.swift XKeyTests
git commit -m "fix(engine): stop the tap handler from rebinding process-wide engine singletons"
```

---

### Task 6: Dời khối app-switch + re-prime ra `TapEventSource`

**Files:**
- Create: `Shared/TapEventSource.swift`
- Modify: `XKey/App/AppDelegate.swift`, `XKey.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  ```swift
  final class TapEventSource {
      init(handler: KeyboardEventHandler)
      func start()
      func stop()
  }
  ```
  T7/T8 mở rộng cùng lớp này; T9 (TapController) khởi tạo nó.

**Luật vàng áp dụng: dời cơ học.** Khối cần dời: `setupAppSwitchObserver()` (`AppDelegate.swift:1181`) cùng toàn bộ thân closure của nó, gồm khối re-prime +50ms.

- [ ] **Step 1: Đọc và chép nguyên khối**

Đọc `setupAppSwitchObserver()` đầy đủ. Chép **nguyên văn** thân closure vào `TapEventSource`, chỉ đổi các tham chiếu `self.keyboardHandler?` thành `handler`. Mọi thứ khác — thứ tự lời gọi, các `DispatchQueue.main.asyncAfter`, việc huỷ work item, mọi comment — giữ y nguyên.

Phần nào trong closure gọi tới thứ chỉ có ở `AppDelegate` (Smart Switch UI, verification title, ForceAccessibility nếu chưa dời): **để lại** trong `AppDelegate` bằng một closure callback mà `TapEventSource` gọi ra, đừng kéo theo. Khai báo callback đó là một property optional có tên rõ ràng và ghi trong báo cáo cái gì ở lại vì sao.

- [ ] **Step 2: `AppDelegate` dùng `TapEventSource`**

Xoá `setupAppSwitchObserver()` khỏi `AppDelegate`, thay bằng khởi tạo `TapEventSource` và gọi `start()`; `applicationWillTerminate` gọi `stop()`. Giữ nguyên `appSwitchObserver` property nếu còn thứ khác dùng, ngược lại xoá.

- [ ] **Step 3: pbxproj — `Shared/TapEventSource.swift` vào cả bốn target**

Verify: `plutil -lint` OK; số lần `TapEventSource.swift in Sources` bằng số của `AXHelper.swift`.

- [ ] **Step 4: Build + test + kiểm hồi quy XKey.app**

Run: `APPBUILD`, `IMBUILD`, `XCTEST` → xanh.

Rồi ghi vào báo cáo yêu cầu kiểm tay cho chủ repo (task này đụng đường CGEvent đang chạy ổn):
> Chạy XKey.app ở chế độ CGEvent (không chọn XKeyIM làm input source), kiểm: gõ tiếng Việt thường, đổi app rồi gõ ngay, Spotlight, Chrome omnibox. Phải **không khác gì** trước.

- [ ] **Step 5: Commit**

```bash
git add Shared/TapEventSource.swift XKey/App/AppDelegate.swift XKey.xcodeproj/project.pbxproj
git commit -m "refactor(tap): move app-switch handling into a shared tap event source"
```

---

### Task 7: Dời AXObserver focus + title

**Files:**
- Modify: `Shared/TapEventSource.swift`, `XKey/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `TapEventSource` (T6). Không API công khai mới ngoài những gì `start()`/`stop()` đã bao.

Khối cần dời (tất cả trong `AppDelegate.swift`): `setupFocusChangeMonitoring` `:2146`, `handleFocusCheck` `:2170`, `checkIntraAppFocusChange` `:2199`, `setupAXObserverForApp` `:2255`, `removeAXObserver` `:2323`, `handleAXFocusChanged` `:2350`, `handleAXTitleChanged` `:2442`, `performTitleChangeRedetection` `:2459`; cùng state đi kèm: `focusObserver` `:77`, `focusObserverPID` `:78`, `titleVerificationWorkItem` `:105`, `lastDetectedTitle` `:108`, `titleChangeDebounceWorkItem` `:112`.

**Luật vàng áp dụng.** Đây là khối tinh vi nhất: throttle 100ms, debounce 150/250ms, `AXObserver` theo từng PID. Dời nguyên, không tinh chỉnh.

- [ ] **Step 1: Dời từng hàm một, giữ nguyên thân**

Chuyển tám hàm và năm biến state sang `TapEventSource`. Đổi `self.keyboardHandler?` → `handler`. Thứ nào cần UI (log ra Debug Window) thì đi qua callback optional như T6 đã lập.

- [ ] **Step 2: Nối vào vòng đời**

`start()` gọi `setupFocusChangeMonitoring()`; `stop()` gọi `removeAXObserver()` và huỷ mọi work item.

- [ ] **Step 3: Build + test**

Run: `APPBUILD`, `IMBUILD`, `XCTEST` → xanh.

- [ ] **Step 4: Ghi yêu cầu kiểm tay + commit**

Báo cáo phải nêu: chủ repo cần kiểm XKey.app đổi tab trong Chrome, Tab vào address bar, đổi channel Slack — hành vi phải không đổi.

```bash
git add Shared/TapEventSource.swift XKey/App/AppDelegate.swift
git commit -m "refactor(tap): move AX focus and title monitoring into the shared tap event source"
```

---

### Task 8: Dời mouse-click monitor + overlay callback + ForceAccessibility

**Files:**
- Modify: `Shared/TapEventSource.swift`, `XKey/App/AppDelegate.swift`, `XKey.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `TapEventSource` (T6, T7).

Khối cần dời: `setupMouseClickMonitor` `:1534`, `detectBehaviorWithRetry` `:1584`, state `mouseClickMonitor` `:69`; callback `OverlayAppDetector.shared.onOverlayVisibilityChanged` (`AppDelegate.swift:1275-1320`).

Ngoài ra: `XKey/Utilities/ForceAccessibilityManager.swift` hiện **chỉ ở target XKey + tests** (`grep -c "ForceAccessibilityManager.swift in Sources"` → `2`). Thêm nó vào target XKeyIM để `applyForCurrentApp()` chạy được ở cả hai host.

**Luật vàng áp dụng.**

- [ ] **Step 1: Thêm `ForceAccessibilityManager` vào target XKeyIM**

Verify: `grep -c "ForceAccessibilityManager.swift in Sources" XKey.xcodeproj/project.pbxproj` tăng từ `2` lên `3`; `plutil -lint` OK; `IMBUILD` xanh. Nếu nó kéo theo phụ thuộc XKey-only, **dừng và báo cáo** — đừng thêm file bừa (đúng bài học của đợt trước, khi `Notification.Name` ẩn làm hỏng giả định portable).

- [ ] **Step 2: Dời mouse monitor + overlay callback**

Chuyển nguyên `setupMouseClickMonitor` và `detectBehaviorWithRetry` sang `TapEventSource`. Phần overlay callback: chuyển phần đụng tầng tap (re-detect, `resetMidSentenceFlag`, `resetWithCursorMoved`); phần đụng Smart Switch/ngôn ngữ theo app **để lại** `AppDelegate` qua callback, trừ khi nó chỉ đọc state dùng chung — ghi quyết định vào báo cáo.

- [ ] **Step 3: Nối vòng đời + build + test**

`start()` gắn monitor và callback; `stop()` gỡ. Run: `APPBUILD`, `IMBUILD`, `XCTEST` → xanh.

- [ ] **Step 4: Ghi yêu cầu kiểm tay + commit**

Kiểm tay XKey.app: click vào giữa một từ rồi gõ dấu; mở/đóng Spotlight; click sang field khác.

```bash
git add Shared/TapEventSource.swift XKey/App/AppDelegate.swift XKey.xcodeproj/project.pbxproj
git commit -m "refactor(tap): move mouse, overlay and force-accessibility handling into the shared tap event source"
```

---

### Task 9: XKeyIM tiêu thụ `TapEventSource`

**Files:**
- Modify: `XKeyIM/TapController.swift`

**Interfaces:**
- Consumes: `TapEventSource` (T6–T8).

- [ ] **Step 1: Thay observer tự chế bằng `TapEventSource`**

`TapController` hiện tự đăng ký `NSWorkspace.didActivateApplicationNotification` trong `observeFrontmostApp()`. Xoá nó và dùng `TapEventSource`: `arm()` khởi tạo + `start()`, `disarm()`/`shutdown()` gọi `stop()`.

Các callback optional mà T6–T8 để lại cho host: XKeyIM gán những cái nó làm được, và **không gán** cái nào cần UI. Nếu một callback là bắt buộc cho tính đúng đắn chứ không phải UI, đó là dấu hiệu nó đặt sai chỗ — báo cáo lại thay vì tự vá.

- [ ] **Step 2: Build + test**

Run: `IMBUILD`, `APPBUILD`, `XCTEST` → xanh.

- [ ] **Step 3: Commit**

```bash
git add XKeyIM/TapController.swift
git commit -m "feat(xkeyim): drive the tap from the shared event source"
```

---

### Task 10: Đo lại thực địa (cần chủ repo)

**Files:** không sửa file nào (trừ log tạm, revert sau).

**Interfaces:** sản phẩm là số đo và kết quả kiểm tay.

- [ ] **Step 1: Bàn giao**

Ghi vào báo cáo, nguyên văn:

> Build: `cd /Volumes/SSD1TB/PROJECTS/XKEY/XKey && rm -rf ./build && ENABLE_DMG=false ./build_release.sh`, cài XKeyIM qua XKey Settings, bật Debug mode, chuyển sang XKeyIM.
>
> **XKeyIM — các ca từng hỏng:**
> 1. Mở Raycast/Spotlight rồi gõ — không được freeze, không được giật
> 2. Đổi app rồi gõ ngay — không nhảy text
> 3. Đổi tab trong Chrome / đổi channel Slack rồi gõ
> 4. Click vào giữa một từ rồi gõ dấu
> 5. Terminal: gõ `as` → `á`, không gạch chân, zsh-autosuggestion còn sống, Tab-complete còn chạy
> 6. Đặt kiểu gõ VNI trong Settings → XKeyIM phải gõ VNI
> 7. Một app trong danh sách loại trừ → không gõ tiếng Việt
> 8. Gõ nhanh liên tục 30 giây → không loạn chữ, bàn phím không treo
> 9. Ô mật khẩu → không biến đổi
>
> **XKey.app (chế độ CGEvent) — kiểm hồi quy sau khi dời code:**
> 10. Gõ thường, đổi app, click giữa từ, Spotlight, Chrome omnibox — phải không khác trước
>
> Rồi gửi lại: `grep -E "TAP|DISABLED" ~/XKey_Debug.log | tail -40`

- [ ] **Step 2: Ghi kết quả**

Chép kết quả từng mục vào báo cáo, PASS/FAIL. Ca nào FAIL: ghi log kèm theo, **không tự sửa** — coordinator quyết định.

---

## Ngoài phạm vi (đã cân nhắc, chủ động bỏ)

- **Bỏ chế độ CGEvent của XKey.app** — quyết định sản phẩm riêng.
- **Hotkey chỉ có ở XKeyIM** (ví dụ đổi input source bằng phím) — không thuộc hợp đồng này.
- **Đổi engine hay luật chính tả.**
- **Test biên dịch khẳng định "thiếu trường là lỗi biên dịch"** — Swift không có cách khẳng định điều đó trong XCTest; hợp đồng tự bảo đảm nhờ init không có giá trị mặc định, và T2's test phủ phần khẳng định được.
