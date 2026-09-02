# XKeyIM Event Tap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cho XKeyIM tự chạy một CGEventTap khi có quyền Accessibility, để terminal (và mọi app) được gõ bằng phím thật — dùng chung nguyên tầng ghi chữ với XKey.app, và xoá bỏ tầng ghi IMKit phức tạp.

**Architecture:** XKeyIM compile-share 6 file tầng tap của XKey.app (không tạo abstraction nào — đúng cách 28 file engine đang share). Một `TapController` mới trong XKeyIM vũ trang tap khi có quyền + IME đang active; lúc đó `XKeyIMController.handle()` trả `false` cho mọi event và IMKit thành ống dẫn. Thiếu quyền thì rơi về marked text thuần. Trạng thái active theo state machine `IMEActivation`; chống hai tap bằng cờ App Group một chiều.

**Tech Stack:** Swift, InputMethodKit, CoreGraphics event taps, ApplicationServices (AX/TCC), XCTest, Xcode project file.

**Spec:** `docs/superpowers/specs/2026-08-28-xkeyim-event-tap-design.md`

## Global Constraints

- Commit message: English, Conventional Commits. **KHÔNG** thêm `Co-Authored-By` / AI attribution.
- Làm trên branch `feat/xkeyim-event-tap` (tách từ `main`, HEAD hiện tại `a10abe5`).
- **KHÔNG** ⌘R/⌘B target XKeyIM trong Xcode GUI — bundle DerivedData trùng `InputMethodConnectionName` với bản đã cài sẽ khiến macOS dựng lại toàn bộ enabled input sources.
- Build type-check XKeyIM: `xcodebuild build -project XKey.xcodeproj -target XKeyIM -configuration Debug CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5` → phải in `** BUILD SUCCEEDED **`. Viết tắt dưới đây: `IMBUILD`.
- Build type-check XKey: đổi `-target XKeyIM` thành `-target XKey`. Viết tắt: `APPBUILD`.
- Test: `xcodebuild test -project XKey.xcodeproj -scheme XKeyTests -configuration Debug CODE_SIGNING_ALLOWED=NO` (Bash timeout 600000). Viết tắt: `XCTEST`. Lỗi môi trường đã biết, **bỏ qua đúng hai nhóm này**: `TranslationProviderTests.*` (cần network), `iCloudSyncManagerTests.*` (cần entitlement). Mọi thứ khác đỏ là lỗi của mình.
- **KHÔNG sửa** đường chạy của XKey.app ngoài đúng một guard nhường quyền ở Task 7. Tap của XKey.app giữ nguyên main run loop.
- File thuộc thư mục `XKeyIM/` **tự động** vào target XKeyIM (`PBXFileSystemSynchronizedRootGroup`) — **không** thêm entry pbxproj cho chúng, sẽ double-register. File ngoài thư mục đó phải thêm tay.
- Thêm file vào target bằng tay trong `XKey.xcodeproj/project.pbxproj`: theo đúng khuôn `SCRSIM0001`/`INPROBE0001` đã có (1 `PBXBuildFile` + dùng lại `PBXFileReference` sẵn có + 1 dòng trong `PBXSourcesBuildPhase` của target đích). Sau mỗi lần sửa: `plutil -lint XKey.xcodeproj/project.pbxproj` phải OK.
- Người thực thi **không tự cài/không tự cấp quyền**. Task nào cần chạy thật trên máy thì dừng lại, ghi rõ hướng dẫn cho chủ repo, và báo cáo là "chờ đo".

---

### Task 0: Branch + baseline

**Files:** không sửa file nào.

**Interfaces:**
- Produces: branch `feat/xkeyim-event-tap` và một lần chạy test baseline để mọi task sau đối chiếu.

- [ ] **Step 1: Tạo branch**

```bash
git checkout -b feat/xkeyim-event-tap
```

- [ ] **Step 2: Chạy test baseline**

Run: `XCTEST` (lệnh đầy đủ ở Global Constraints), rồi `2>&1 | tail -20`.
Expected: `** TEST SUCCEEDED **`, hoặc chỉ đỏ ở `TranslationProviderTests.*` / `iCloudSyncManagerTests.*`. Nếu có test khác đỏ ngay baseline: **dừng**, báo chủ repo, không sửa test cũ trong plan này.

- [ ] **Step 3: Ghi lại số liệu baseline**

Chạy: `XCTEST 2>&1 | grep -E "Test Suite 'XKeyTests' .* at|Executed .* tests"` và dán kết quả vào báo cáo task. Không commit gì ở task này.

---

### Task 1: `IMEActivation` — state machine bám input source

**Files:**
- Create: `XKeyIM/IMEActivation.swift`
- Create: `XKeyTests/IMEActivationTests.swift`
- Modify: `XKey.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces:
  ```swift
  struct IMEActivation {
      private(set) var isActive: Bool
      init(isActive: Bool = false)
      mutating func activate()
      mutating func deactivate(stillSelected: Bool)
      mutating func selectionChanged(isXKeyIM: Bool)
  }
  ```
  Task 4 (`TapController`) tiêu thụ nguyên vẹn.

Bối cảnh: `activateServer`/`deactivateServer` có thể tới **không đúng thứ tự** — IMK gọi `activateServer` của client mới trước `deactivateServer` của client cũ. Một `deactivate → false` ngây thơ sẽ đè mất activate vừa tới, tap ngủ trong khi IME vẫn đang được chọn. Nguyên tắc: input source do OS chọn là sự thật; lifecycle callback chỉ là gợi ý.

- [ ] **Step 1: Viết test fail trước**

Tạo `XKeyTests/IMEActivationTests.swift`:

```swift
import XCTest
@testable import XKey

/// IMEActivation is compiled directly into the XKeyTests target (see pbxproj),
/// so no import beyond XKey is needed.
final class IMEActivationTests: XCTestCase {

    func testStartsInactive() {
        XCTAssertFalse(IMEActivation().isActive)
    }

    func testActivateMakesActive() {
        var a = IMEActivation()
        a.activate()
        XCTAssertTrue(a.isActive)
    }

    /// The ordinary case: the user switched to another input source, so the
    /// deactivate is genuine.
    func testDeactivateWhenNoLongerSelectedTurnsOff() {
        var a = IMEActivation(isActive: true)
        a.deactivate(stillSelected: false)
        XCTAssertFalse(a.isActive)
    }

    /// The hazard this type exists for: focus moved between two clients that both
    /// use XKeyIM. IMK can deliver the OLD client's deactivate AFTER the NEW
    /// client's activate. Honouring it would silently disarm the tap while XKeyIM
    /// is still the selected source.
    func testLateDeactivateWhileStillSelectedIsIgnored() {
        var a = IMEActivation()
        a.activate()                          // new client
        a.deactivate(stillSelected: true)     // old client, arriving late
        XCTAssertTrue(a.isActive)
    }

    /// TIS notification is authoritative in both directions — it also covers
    /// per-document switching that skips activateServer entirely.
    func testSelectionChangedIsAuthoritative() {
        var a = IMEActivation(isActive: true)
        a.selectionChanged(isXKeyIM: false)
        XCTAssertFalse(a.isActive)
        a.selectionChanged(isXKeyIM: true)
        XCTAssertTrue(a.isActive)
    }

    /// A late deactivate must not resurrect-then-clobber after TIS already said no.
    func testLateDeactivateAfterAuthoritativeOffStaysOff() {
        var a = IMEActivation(isActive: true)
        a.selectionChanged(isXKeyIM: false)
        a.deactivate(stillSelected: false)
        XCTAssertFalse(a.isActive)
    }
}
```

- [ ] **Step 2: Chạy test — phải FAIL vì chưa có type**

Run: `XCTEST 2>&1 | grep -E "IMEActivation|error:" | head -5`
Expected: lỗi biên dịch "cannot find 'IMEActivation' in scope".

- [ ] **Step 3: Viết implementation**

Tạo `XKeyIM/IMEActivation.swift`:

```swift
//
//  IMEActivation.swift
//  XKeyIM
//
//  Tracks whether XKeyIM is the active input source, robust to IMKit delivering
//  activateServer / deactivateServer out of order across clients.
//
//  macOS remembers the input source PER APP. A system-wide event tap must therefore
//  only act while XKeyIM is actually the active IME, or it would type Vietnamese
//  into an app the user has set to ABC.
//
//  The ordering hazard: when focus moves between two clients that both use XKeyIM,
//  IMKit may call the NEW client's activateServer BEFORE the OLD client's
//  deactivateServer. Both write one shared flag, so a naive `deactivate -> false`
//  clobbers the fresh activate: the tap goes dormant while XKeyIM is STILL the
//  selected source, and typing passes through untransformed with no visible cause.
//
//  Rule: the OS-selected input source is the single source of truth; the lifecycle
//  callbacks are only hints.
//

import Foundation

struct IMEActivation: Equatable {
    private(set) var isActive: Bool

    init(isActive: Bool = false) {
        self.isActive = isActive
    }

    /// activateServer: XKeyIM is active for the focused client.
    mutating func activate() {
        isActive = true
    }

    /// deactivateServer: a client lost XKeyIM. `stillSelected` is whether XKeyIM is
    /// STILL the OS-selected keyboard input source at this instant. A late,
    /// out-of-order deactivate from a previously focused client fires while XKeyIM
    /// is still selected — ignore it so it cannot disarm the tap under our feet.
    mutating func deactivate(stillSelected: Bool) {
        if !stillSelected { isActive = false }
    }

    /// TIS "selected keyboard input source changed" — authoritative in both
    /// directions. Also covers per-document switching, which can skip
    /// activateServer entirely.
    mutating func selectionChanged(isXKeyIM: Bool) {
        isActive = isXKeyIM
    }
}
```

- [ ] **Step 4: Thêm vào target XKeyTests trong pbxproj**

`IMEActivation.swift` nằm trong `XKeyIM/` nên **tự vào** target XKeyIM (synchronized group) — không thêm entry cho XKeyIM. Nhưng XKeyTests là group cổ điển, phải thêm tay: 1 `PBXFileReference`, 1 `PBXBuildFile`, 1 dòng trong `PBXSourcesBuildPhase` `TEST00010`, theo đúng khuôn `INPROBE0001`/`INPROBE0002` đang có (dùng ID mới không trùng, ví dụ tiền tố `IMEACT`). Cả `IMEActivation.swift` lẫn `IMEActivationTests.swift` đều phải có mặt trong phase đó.

Verify: `grep -c "IMEActivation.swift in Sources" XKey.xcodeproj/project.pbxproj` → `1`; `plutil -lint XKey.xcodeproj/project.pbxproj` → OK.

- [ ] **Step 5: Chạy test — phải PASS**

Run: `XCTEST 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **` (trừ hai nhóm môi trường đã biết).

- [ ] **Step 6: Commit**

```bash
git add XKeyIM/IMEActivation.swift XKeyTests/IMEActivationTests.swift XKey.xcodeproj/project.pbxproj
git commit -m "feat(xkeyim): track IME activation robustly against out-of-order lifecycle calls"
```

---

### Task 2: Cờ App Group chống hai tap

**Files:**
- Modify: `XKey/Utilities/SharedSettings.swift`
- Test: `XKeyTests/TapOwnershipTests.swift` (Create)
- Modify: `XKey.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces trên `SharedSettings`:
  ```swift
  var xkeyIMTapArmed: Bool          // get/set
  var xkeyIMTapPID: Int             // get/set
  func armXKeyIMTap(pid: Int)       // set both + notify
  func disarmXKeyIMTap()            // clear both + notify
  var isXKeyIMTapOwningInput: Bool  // armed AND pid alive
  ```
  Task 4 gọi `armXKeyIMTap`/`disarmXKeyIMTap`; Task 7 đọc `isXKeyIMTapOwningInput`.

Bối cảnh: XKey.app hiện suspend tap khi XKeyIM là input source **toàn cục** — không đủ, vì input source là per-app. Cờ chỉ sống trong lúc XKeyIM active, nên khi người dùng sang app dùng ABC thì XKey.app tự làm việc lại.

- [ ] **Step 1: Viết test fail trước**

Tạo `XKeyTests/TapOwnershipTests.swift`:

```swift
import XCTest
@testable import XKey

/// Ownership of the keyboard between XKey.app's tap and XKeyIM's tap is decided by
/// a one-way App Group flag: XKeyIM arms it, XKey.app yields. A dead PID must never
/// keep XKey.app locked out — XKeyIM can be killed without a clean shutdown.
final class TapOwnershipTests: XCTestCase {

    override func tearDown() {
        SharedSettings.shared.disarmXKeyIMTap()
        super.tearDown()
    }

    func testNotOwningWhenDisarmed() {
        SharedSettings.shared.disarmXKeyIMTap()
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
    }

    func testOwningWhenArmedByLiveProcess() {
        // This test process is certainly alive, so it stands in for XKeyIM.
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))
        XCTAssertTrue(SharedSettings.shared.isXKeyIMTapOwningInput)
    }

    func testNotOwningWhenArmingProcessIsDead() {
        // PID 0 is never a live user process; stands in for a crashed XKeyIM.
        SharedSettings.shared.armXKeyIMTap(pid: 0)
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput,
                       "a dead arming process must not keep XKey.app locked out")
    }

    func testDisarmClearsOwnership() {
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))
        SharedSettings.shared.disarmXKeyIMTap()
        XCTAssertFalse(SharedSettings.shared.isXKeyIMTapOwningInput)
    }
}
```

- [ ] **Step 2: Chạy test — phải FAIL**

Run: `XCTEST 2>&1 | grep -E "TapOwnership|error:" | head -5`
Expected: lỗi biên dịch "value of type 'SharedSettings' has no member 'armXKeyIMTap'".

- [ ] **Step 3: Thêm key vào enum `SharedSettingsKey`**

Trong `XKey/Utilities/SharedSettings.swift`, cạnh nhóm `remoteDesktopInjectMode`:

```swift
    // XKeyIM event tap ownership (one-way: XKeyIM arms, XKey.app yields)
    case xkeyIMTapArmed = "XKey.xkeyIMTapArmed"
    case xkeyIMTapPID = "XKey.xkeyIMTapPID"

    // Global Vietnamese on/off, shared by both processes
    case vietnameseEnabled = "XKey.vietnameseEnabled"
```

Nếu `readPlistDict()` là `private` trong file này, đổi accessor `vietnameseEnabled` ở Step 4 sang dùng đúng helper công khai sẵn có cho Bool-có-default (grep `func readBool` xem có overload nhận `defaultValue` không, giống `XKeyIMSettings.readBool(forKey:defaultValue:)`). Yêu cầu bất biến: **thiếu key ⇒ trả `true`**.

- [ ] **Step 4: Thêm accessor**

Cạnh `var remoteDesktopInjectMode` (theo đúng khuôn get/set + `notifySettingsChanged()` của file này):

```swift
    // MARK: - Vietnamese On/Off (shared by both processes)

    /// Global Vietnamese on/off. Lives here because BOTH the tap path
    /// (KeyboardEventHandler) and the marked-text path (XKeyIMController) must read
    /// one truth — XKeyIM used to keep a private in-memory flag that neither
    /// persisted nor synced, which is exactly the desync class this replaces.
    /// Defaults to true so a fresh install types Vietnamese.
    var vietnameseEnabled: Bool {
        get {
            guard let dict = readPlistDict(),
                  let value = dict[SharedSettingsKey.vietnameseEnabled.rawValue] as? Bool
            else { return true }
            return value
        }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.vietnameseEnabled.rawValue)
            notifySettingsChanged()
        }
    }

    // MARK: - XKeyIM Tap Ownership

    /// True while XKeyIM's event tap is armed. Written ONLY by XKeyIM.
    var xkeyIMTapArmed: Bool {
        get { readBool(forKey: SharedSettingsKey.xkeyIMTapArmed.rawValue) }
        set {
            writeBool(newValue, forKey: SharedSettingsKey.xkeyIMTapArmed.rawValue)
            notifySettingsChanged()
        }
    }

    /// PID of the XKeyIM process that armed the tap, so a crashed XKeyIM cannot
    /// keep XKey.app locked out forever.
    var xkeyIMTapPID: Int {
        get { readInt(forKey: SharedSettingsKey.xkeyIMTapPID.rawValue) }
        set {
            writeInt(newValue, forKey: SharedSettingsKey.xkeyIMTapPID.rawValue)
            notifySettingsChanged()
        }
    }

    /// Called by XKeyIM when its tap goes live.
    func armXKeyIMTap(pid: Int) {
        writeInt(pid, forKey: SharedSettingsKey.xkeyIMTapPID.rawValue)
        writeBool(true, forKey: SharedSettingsKey.xkeyIMTapArmed.rawValue)
        notifySettingsChanged()
    }

    /// Called by XKeyIM on deactivate and on terminate.
    func disarmXKeyIMTap() {
        writeBool(false, forKey: SharedSettingsKey.xkeyIMTapArmed.rawValue)
        writeInt(0, forKey: SharedSettingsKey.xkeyIMTapPID.rawValue)
        notifySettingsChanged()
    }

    /// The question XKey.app asks: should I keep my hands off the keyboard?
    /// Armed AND the arming process still alive — `kill(pid, 0)` probes liveness
    /// without sending a signal.
    var isXKeyIMTapOwningInput: Bool {
        guard xkeyIMTapArmed else { return false }
        let pid = xkeyIMTapPID
        guard pid > 0 else { return false }
        return kill(pid_t(pid), 0) == 0
    }
```

Nếu tên helper đọc/ghi Int trong file này khác `readInt`/`writeInt`, dùng đúng tên thật (grep `func readInt` / `func writeInt` trong file trước khi viết).

- [ ] **Step 5: Thêm test file vào target XKeyTests trong pbxproj**

Theo khuôn `SCRSIM0001` (tiền tố ID mới, ví dụ `TAPOWN`). `SharedSettings.swift` đã có trong mọi target, không phải làm gì.
Verify: `plutil -lint XKey.xcodeproj/project.pbxproj` → OK.

- [ ] **Step 6: Chạy test — phải PASS**

Run: `XCTEST 2>&1 | tail -5` → `** TEST SUCCEEDED **` (trừ hai nhóm môi trường).

- [ ] **Step 7: Commit**

```bash
git add XKey/Utilities/SharedSettings.swift XKeyTests/TapOwnershipTests.swift XKey.xcodeproj/project.pbxproj
git commit -m "feat(settings): one-way tap ownership flag with liveness check"
```

---

### Task 3: Compile-share tầng tap vào target XKeyIM

**Files:**
- Modify: `XKey.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: target XKeyIM biên dịch được `EventTapManager`, `KeyboardEventHandler`, `CharacterInjector`, `AdvancedInjectionMethods`, `SecureInputStateMachine`, `OverlayAppDetector`. Task 4 dựng `EventTapManager` + `KeyboardEventHandler`.

Bối cảnh đã kiểm: tầng này portable 100%. `MacroManager`/`SmartSwitchManager`/`AppBehaviorDetector`/`AXHelper`/`DebugLogger`/`SharedSettings` đã có trong cả 4 target. Hai tham chiếu tới `StatusBar`/`AppDelegate` trong tầng tap chỉ là **comment**. `KeyboardEventHandler` chỉ import Cocoa + Combine.

- [ ] **Step 1: Xác nhận lại giả định trước khi sửa**

```bash
grep -nE "StatusBar|AppDelegate" XKey/EventHandling/*.swift
grep -nE "^import" XKey/EventHandling/KeyboardEventHandler.swift
for f in MacroManager.swift SmartSwitchManager.swift OverlayAppDetector.swift; do
  printf "%-28s %s\n" "$f" "$(grep -c "$f in Sources" XKey.xcodeproj/project.pbxproj)"
done
```
Expected: hai hit đầu đều nằm trong dòng comment; import chỉ `Cocoa`/`Combine`; `MacroManager`=4, `SmartSwitchManager`=4, `OverlayAppDetector`=2. Nếu khác: **dừng**, báo cáo — giả định của plan sai.

- [ ] **Step 2: Thêm 6 file vào Sources phase của target XKeyIM**

Sources phase của XKeyIM là `100D2BA92EF2B89600C26B87`. Với mỗi file, tạo một `PBXBuildFile` mới trỏ tới `PBXFileReference` **đã có sẵn** (các file này đang thuộc target XKey nên fileRef đã tồn tại — tìm bằng `grep -n "EventTapManager.swift" XKey.xcodeproj/project.pbxproj`), rồi thêm dòng vào phase đó. Dùng tiền tố ID mới không trùng, ví dụ `IMTAP01`…`IMTAP06`.

Sáu file: `EventTapManager.swift`, `KeyboardEventHandler.swift`, `CharacterInjector.swift`, `AdvancedInjectionMethods.swift`, `SecureInputStateMachine.swift`, `OverlayAppDetector.swift`.

- [ ] **Step 3: Verify pbxproj**

```bash
plutil -lint XKey.xcodeproj/project.pbxproj
for f in EventTapManager KeyboardEventHandler CharacterInjector AdvancedInjectionMethods SecureInputStateMachine OverlayAppDetector; do
  printf "%-28s %s\n" "$f" "$(grep -c "$f.swift in Sources" XKey.xcodeproj/project.pbxproj)"
done
```
Expected: `plutil` OK; mỗi file tăng đúng 1 so với trước (ví dụ `EventTapManager` từ 1 → 2).

- [ ] **Step 4: Build cả hai target**

Run: `IMBUILD` rồi `APPBUILD`.
Expected: cả hai `** BUILD SUCCEEDED **`. Nếu XKeyIM lỗi thiếu symbol: file đó có phụ thuộc chưa share — **dừng và báo cáo tên symbol**, đừng tự thêm file bừa.

- [ ] **Step 5: Commit**

```bash
git add XKey.xcodeproj/project.pbxproj
git commit -m "build(xkeyim): compile the event tap layer into the XKeyIM target"
```

---

### Task 4: `TapController` — vũ trang/hạ tap theo quyền và trạng thái active

**Files:**
- Create: `XKeyIM/TapController.swift`

**Interfaces:**
- Consumes: `IMEActivation` (Task 1), `SharedSettings.armXKeyIMTap/disarmXKeyIMTap` (Task 2), `EventTapManager`/`KeyboardEventHandler` (Task 3).
- Produces:
  ```swift
  final class TapController {
      static let shared: TapController
      var isArmed: Bool { get }              // Task 5 đọc để quyết định trả false
      func imeDidActivate()                  // gọi từ activateServer
      func imeDidDeactivate(stillSelected: Bool)  // gọi từ deactivateServer
      func inputSourceChanged(isXKeyIM: Bool)     // gọi từ TIS notification
      func noteFrontmostApp(bundleId: String?)
      static func hasEventPermission() -> Bool
  }
  ```

Ghi chú thiết kế: tap chạy trên **main run loop** (như XKey.app) — khi tap vũ trang, `handle()` trả `false` ngay nên main gần như rảnh. Chỉ chuyển thread nếu Task 9 đo thấy `tapDisabledByTimeout` thật.

- [ ] **Step 1: Viết `TapController`**

Tạo `XKeyIM/TapController.swift`:

```swift
//
//  TapController.swift
//  XKeyIM
//
//  Owns XKeyIM's CGEventTap. When armed, the tap does all the typing (exactly the
//  path XKey.app uses) and XKeyIMController becomes a pass-through pipe. Without
//  Accessibility permission the tap never arms and XKeyIM falls back to marked text.
//

import Cocoa
import ApplicationServices

final class TapController {

    static let shared = TapController()

    private var manager: EventTapManager?
    private var handler: KeyboardEventHandler?
    private var activation = IMEActivation()
    private var frontmostObserver: Any?

    /// True while the tap owns the keyboard. Read by XKeyIMController on every
    /// keystroke, so it must stay a plain stored-property read.
    private(set) var isArmed = false

    private init() {}

    // MARK: - Permission

    /// Ground truth for "may I post and listen to events?". `AXIsProcessTrusted()`
    /// answers a broader question; these two are the specific permissions a tap
    /// needs, and they are what CGEventTapCreate is actually gated on.
    static func hasEventPermission() -> Bool {
        CGPreflightListenEventAccess() && CGPreflightPostEventAccess()
    }

    // MARK: - IME lifecycle

    /// Set by reconcile() when arming or disarming actually changed the channel.
    /// XKeyIMController reads and clears it to finish the word in progress — the
    /// two channels track a word differently, so carrying one across the switch
    /// leaves the engine describing text the new channel never wrote.
    private(set) var channelDidChange = false

    func consumeChannelChange() -> Bool {
        defer { channelDidChange = false }
        return channelDidChange
    }

    func imeDidActivate() {
        activation.activate()
        reconcile()
    }

    func imeDidDeactivate(stillSelected: Bool) {
        activation.deactivate(stillSelected: stillSelected)
        reconcile()
    }

    func inputSourceChanged(isXKeyIM: Bool) {
        activation.selectionChanged(isXKeyIM: isXKeyIM)
        reconcile()
    }

    /// Keeps KeyboardEventHandler's frontmost-app cache fresh. Without this its
    /// exclusion check falls back to a live NSWorkspace query on every keystroke.
    func noteFrontmostApp(bundleId: String?) {
        handler?.noteFrontmostApp(bundleId: bundleId)
    }

    // MARK: - Arming

    private func reconcile() {
        let shouldArm = activation.isActive && Self.hasEventPermission()
        let was = isArmed
        if shouldArm { arm() } else { disarm() }
        if isArmed != was { channelDidChange = true }
    }

    private func arm() {
        guard !isArmed else { return }

        let handler = self.handler ?? KeyboardEventHandler()
        self.handler = handler
        handler.noteFrontmostApp(bundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        // One truth for Vietnamese on/off across both channels and both processes.
        handler.setVietnamese(SharedSettings.shared.vietnameseEnabled)

        let manager = self.manager ?? EventTapManager()
        manager.delegate = handler
        self.manager = manager

        do {
            try manager.start()
        } catch EventTapManager.EventTapError.alreadyRunning {
            manager.resume()
        } catch {
            IMKitDebugger.shared.log("Tap failed to start: \(error)", category: "TAP")
            return
        }

        isArmed = true
        SharedSettings.shared.armXKeyIMTap(pid: Int(getpid()))
        observeFrontmostApp()
        IMKitDebugger.shared.log("Tap ARMED (pid \(getpid()))", category: "TAP")
    }

    private func disarm() {
        guard isArmed else { return }
        manager?.suspend()
        isArmed = false
        SharedSettings.shared.disarmXKeyIMTap()
        stopObservingFrontmostApp()
        IMKitDebugger.shared.log("Tap DISARMED", category: "TAP")
    }

    /// Called from applicationWillTerminate: the flag must not outlive the process,
    /// or XKey.app would keep yielding to a tap that no longer exists. (The PID
    /// liveness check is the backstop for a hard crash.)
    func shutdown() {
        manager?.stop()
        isArmed = false
        SharedSettings.shared.disarmXKeyIMTap()
        stopObservingFrontmostApp()
    }

    // MARK: - Frontmost app cache

    private func observeFrontmostApp() {
        guard frontmostObserver == nil else { return }
        frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.handler?.noteFrontmostApp(bundleId: app?.bundleIdentifier)
        }
    }

    private func stopObservingFrontmostApp() {
        if let o = frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            frontmostObserver = nil
        }
    }
}
```

- [ ] **Step 2: Build type-check**

Run: `IMBUILD`
Expected: `** BUILD SUCCEEDED **`. Nếu `EventTapManager()` cần tham số hoặc `EventTapError` nằm ở scope khác, sửa theo chữ ký thật (`grep -n "init(" XKey/EventHandling/EventTapManager.swift`) và ghi lại trong báo cáo.

- [ ] **Step 3: Commit**

```bash
git add XKeyIM/TapController.swift
git commit -m "feat(xkeyim): add TapController that arms an event tap when permitted and active"
```

---

### Task 5: Nối `TapController` vào vòng đời IMKit + biến `handle()` thành ống dẫn

**Files:**
- Modify: `XKeyIM/XKeyIMController.swift` (`activateServer` ~:1502, `deactivateServer` ~:1556, đầu `handle()` ~:375)
- Modify: `XKeyIM/main.swift` (đăng ký TIS notification, `applicationWillTerminate`)

**Interfaces:**
- Consumes: `TapController.shared` (Task 4).
- Produces: khi `TapController.shared.isArmed == true`, `handle()` trả `false` cho mọi event và không đụng engine.

- [ ] **Step 1: Nối activate/deactivate**

Trong `activateServer`, ngay sau `super.activateServer(sender)`:

```swift
        TapController.shared.imeDidActivate()
```

Trong `deactivateServer`, thay thân hàm thành:

```swift
    override func deactivateServer(_ sender: Any!) {
        commitComposition(sender)
        // `stillSelected` decides whether this is a genuine deactivate or a late,
        // out-of-order one from a client we already left (see IMEActivation).
        TapController.shared.imeDidDeactivate(stillSelected: Self.isXKeyIMSelectedInputSource())
        super.deactivateServer(sender)
        NSLog("XKeyIMController: Deactivated")
    }
```

Thêm helper vào cùng class:

```swift
    /// Is XKeyIM the OS-selected keyboard input source right now? This is the
    /// authority IMEActivation defers to — lifecycle callbacks are only hints.
    static func isXKeyIMSelectedInputSource() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return false }
        let id = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        return id.hasPrefix("com.codetay.inputmethod.XKey")
    }
```

Thêm `import Carbon` đầu file nếu chưa có (`grep -n "^import" XKeyIM/XKeyIMController.swift`).

- [ ] **Step 2: Biến `handle()` thành ống dẫn khi tap cầm lái**

Trong `handle(_:client:)`, ngay sau `guard let client = sender as? IMKTextInput else { return false }` và **trước** mọi guard passthrough hiện có:

```swift
        // The channel just switched (tap armed or disarmed). Finish the word in
        // progress on an explicit boundary instead of letting a desync heuristic
        // fire a keystroke later — the two channels track a word differently, so a
        // carried-over buffer describes text the new channel never wrote.
        if TapController.shared.consumeChannelChange() {
            if !composingText.isEmpty { commitComposition(client) }
            engine.reset()
            composingText = ""
            currentWordLength = 0
            markedTextStartLocation = NSNotFound
        }

        // The tap owns the keyboard: it sees every physical key before the app does
        // and does all the typing. IMKit must not also process them — and our own
        // injected synthetic events arrive here too, so composing on them would
        // double-type. Pure pipe.
        if TapController.shared.isArmed {
            return false
        }
```

- [ ] **Step 3: Đăng ký TIS notification + dọn khi thoát trong `main.swift`**

Trong `applicationDidFinishLaunching`, cạnh observer settings hiện có:

```swift
            // TIS selection is authoritative for whether XKeyIM is active — it also
            // covers per-document switching, which can skip activateServer entirely.
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                object: nil, queue: .main
            ) { _ in
                TapController.shared.inputSourceChanged(
                    isXKeyIM: XKeyIMController.isXKeyIMSelectedInputSource())
            }
```

Trong `applicationWillTerminate`:

```swift
        TapController.shared.shutdown()
```

Thêm `import Carbon` vào `main.swift` nếu cần.

- [ ] **Step 4: Build type-check**

Run: `IMBUILD` → `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add XKeyIM/XKeyIMController.swift XKeyIM/main.swift
git commit -m "feat(xkeyim): drive the tap from IMKit lifecycle and pipe keys through when armed"
```

---

### Task 6: Menu quyền trong XKeyIM

**Files:**
- Modify: `XKeyIM/XKeyIMController.swift` (`menu()` ~:1631)

**Interfaces:**
- Consumes: `TapController.hasEventPermission()`, `TapController.shared.isArmed`.
- Produces: ba mục menu mới. Không có API mới cho task sau.

Bối cảnh: XKeyIM là process nền, không có cửa sổ settings; luồng quyền phải nằm hẳn trong nó để không phụ thuộc XKey.app đang chạy.

- [ ] **Step 1: Thêm mục vào `menu()`**

Trong `menu()`, sau các mục hiện có, chèn:

```swift
        menu.addItem(NSMenuItem.separator())

        let permitted = TapController.hasEventPermission()
        let status = NSMenuItem(
            title: permitted
                ? (TapController.shared.isArmed ? "Chế độ gõ: phím thật" : "Chế độ gõ: gạch chân")
                : "Chế độ gõ: gạch chân (chưa có quyền Trợ năng)",
            action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !permitted {
            let grant = NSMenuItem(title: "Cấp quyền Trợ năng…",
                                   action: #selector(openAccessibilitySettings), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        let reset = NSMenuItem(title: "Đặt lại & xin lại quyền Trợ năng",
                               action: #selector(resetAccessibilityGrant), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
```

- [ ] **Step 2: Thêm hai action**

Cạnh `openXKeySettings` trong cùng class:

```swift
    @objc private func openAccessibilitySettings() {
        // Fires the system prompt from THIS process — it is the code identity being
        // asked about, so the prompt must not come from XKey.app.
        _ = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Recovery for a grant that exists but no longer matches this build's signature:
    /// the Settings checkbox is drawn from the bundle id while the actual check uses
    /// the requirement recorded when the grant was made, so a stale row looks enabled
    /// and still fails. Resetting our own row (no root needed — it can only REMOVE
    /// permission) lets the next prompt write a fresh one.
    /// Only ever on an explicit user click; never automatic.
    @objc private func resetAccessibilityGrant() {
        guard let bundleId = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", bundleId]
        try? task.run()
        task.waitUntilExit()
        openAccessibilitySettings()
    }
```

- [ ] **Step 3: Build type-check**

Run: `IMBUILD` → `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add XKeyIM/XKeyIMController.swift
git commit -m "feat(xkeyim): surface accessibility status and recovery in the input method menu"
```

---

### Task 7: XKey.app nhường khi tap của XKeyIM đang cầm lái

**Files:**
- Modify: `XKey/EventHandling/KeyboardEventHandler.swift` (`shouldProcessEvent` ~:335)

**Interfaces:**
- Consumes: `SharedSettings.isXKeyIMTapOwningInput` (Task 2).
- Produces: không API mới.

- [ ] **Step 1: Thêm guard đầu `shouldProcessEvent`**

Ngay dòng đầu thân hàm, **trước** `isCurrentAppExcluded()`:

```swift
        // XKeyIM's own tap is armed for the app in front. Two taps must never both
        // transform one keystroke. This is per-app-accurate: the flag only exists
        // while XKeyIM is the active IME, so switching to an ABC app hands control
        // straight back to us (the global input-source suspend cannot do that).
        if SharedSettings.shared.isXKeyIMTapOwningInput {
            return false
        }
```

- [ ] **Step 2: Build cả hai target**

Run: `APPBUILD` rồi `IMBUILD` → cả hai `** BUILD SUCCEEDED **`

- [ ] **Step 3: Chạy full test**

Run: `XCTEST 2>&1 | tail -5` → `** TEST SUCCEEDED **` (trừ hai nhóm môi trường). Đặc biệt kiểm `ToggleRulesTests` và `InjectionRoutingTests` không đỏ.

- [ ] **Step 4: Commit**

```bash
git add XKey/EventHandling/KeyboardEventHandler.swift
git commit -m "feat(injection): yield the keyboard while XKeyIM's tap owns input"
```

---

### Task 8: Xoá tầng ghi direct-insert khỏi XKeyIM

**Files:**
- Modify: `XKeyIM/XKeyIMController.swift`
- Delete: `XKeyIM/InPlaceProbe.swift`, `XKeyTests/InPlaceProbeTests.swift`
- Modify: `XKey.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `XKeyIMController` chỉ còn hai đường — pipe (tap cầm lái) hoặc marked text.

Bối cảnh: không còn direct-insert thì mọi máy móc dò-đoán quanh nó là code chết. Đây là phần lãi của cả plan.

- [ ] **Step 1: Xoá trong `XKeyIMController.swift`**

Xoá hẳn:
- `replaceTextDirect(newText:client:)` toàn bộ (kể cả logic nuốt inline-suggestion và khối probe)
- nhánh `else` gọi nó trong `handleResult` — `handleResult` chỉ còn gọi `setMarkedText(engine.getCurrentWord(), client:)`
- các property tĩnh/instance: `probeFallbackApps`, `probeConfirmedApps`, `probeExhaustedApps`, `caretLiarApps`, `honorTracker`, `consecutiveAppendedVerdicts`, `probeAttempts`, `constantCaretValue`, `constantCaretStrikes`, `persistProbeSets()`
- khối phát hiện caret-liar 3-strike trong nhánh `cursorMoved` và phần reset của nó
- luật category `terminalApps` cùng nhánh `probeFallbackApps` trong `shouldUseMarkedText`
- property `isVietnameseEnabled` (biến in-memory, không persist, không sync)

**Thay chỗ dùng nó, đừng xoá hành vi:**

- `guard isVietnameseEnabled else { … }` (~:908) → `guard SharedSettings.shared.vietnameseEnabled else { … }`
- `toggleVietnamese()` → lật trạng thái dùng chung và đẩy sang cả hai kênh:

```swift
    @objc private func toggleVietnamese() {
        let enabled = !SharedSettings.shared.vietnameseEnabled
        SharedSettings.shared.vietnameseEnabled = enabled
        TapController.shared.applyVietnameseEnabled(enabled)
        engine.reset()
        composingText = ""
        currentWordLength = 0
        markedTextStartLocation = NSNotFound
    }
```

- Tiêu đề mục menu → `SharedSettings.shared.vietnameseEnabled ? "✓ Tiếng Việt" : "Tắt Tiếng Việt"`
- Thêm vào `TapController` (Task 4 đã dựng class này):

```swift
    /// Push the shared on/off state into the tap's handler, which caches it.
    func applyVietnameseEnabled(_ enabled: Bool) {
        handler?.setVietnamese(enabled)
    }
```

Giữ nguyên: nhánh marked text, các guard passthrough sớm (secure input / remote desktop / excludedApps), xử lý `flagsChanged`, auto-capitalize, ESC undo, `didCommand`, `cursorTrackingBroken`/`cursorTrackingVerified` (marked text vẫn dùng).

`shouldUseMarkedText` rút về:

```swift
    /// Without the tap, marked text is the only channel that composes correctly
    /// everywhere. Overlay launchers and secure fields are the two exceptions where
    /// a composition session misbehaves, so they still get plain insertion.
    private func shouldUseMarkedText(_ client: IMKTextInput) -> Bool {
        if isOverlayApp(client) { return false }
        if isSecureTextField(client) { return false }
        return true
    }
```

- [ ] **Step 2: Xoá file + entry pbxproj**

```bash
git rm XKeyIM/InPlaceProbe.swift XKeyTests/InPlaceProbeTests.swift
```
Xoá mọi dòng `INPROBE0001`…`INPROBE0004` trong `XKey.xcodeproj/project.pbxproj`.
Verify: `grep -c INPROBE XKey.xcodeproj/project.pbxproj` → `0`; `plutil -lint XKey.xcodeproj/project.pbxproj` → OK.

- [ ] **Step 3: Dọn UserDefaults cũ**

Trong `TapController.shutdown()` **không** đụng gì; thay vào đó thêm vào `applicationDidFinishLaunching` của `main.swift`, sau khi dựng server:

```swift
            // One-time cleanup: keys from the removed direct-insert probe.
            for key in ["XKeyIM.probeFallbackApps", "XKeyIM.probeConfirmedApps",
                        "XKeyIM.caretLiarApps"] {
                UserDefaults.standard.removeObject(forKey: key)
            }
```

- [ ] **Step 4: Build + test**

Run: `IMBUILD` → BUILD SUCCEEDED; `XCTEST 2>&1 | tail -5` → TEST SUCCEEDED (trừ hai nhóm môi trường).

- [ ] **Step 5: Đo mức giảm code**

```bash
git diff --stat main -- XKeyIM/ XKeyTests/
```
Ghi con số vào báo cáo. Kỳ vọng: XKeyIM ròng **âm** dòng.

- [ ] **Step 6: Commit**

```bash
git add -A XKeyIM XKeyTests XKey.xcodeproj/project.pbxproj
git commit -m "refactor(xkeyim): drop direct-insert mode now that the tap handles typing"
```

---

### Task 9: Đo thực địa (cần chủ repo thao tác)

**Files:**
- Modify: `XKeyIM/TapController.swift` (log tạm), `XKeyIM/XKeyIMController.swift` (log tạm) — **revert sau khi đo**

**Interfaces:** không có API mới. Sản phẩm là **số đo** quyết định ba câu hỏi mở trong spec.

- [ ] **Step 1: Thêm log tạm**

Trong `TapController`, thêm cuối mỗi hàm (sau `reconcile()`):

```swift
    // imeDidActivate:
    IMKitDebugger.shared.log("ACTIVATE → active=\(activation.isActive) armed=\(isArmed) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")", category: "ACTIVATION")

    // imeDidDeactivate:
    IMKitDebugger.shared.log("DEACTIVATE(stillSelected=\(stillSelected)) → active=\(activation.isActive) armed=\(isArmed) front=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?")", category: "ACTIVATION")

    // inputSourceChanged:
    IMKitDebugger.shared.log("TIS(isXKeyIM=\(isXKeyIM)) → active=\(activation.isActive) armed=\(isArmed)", category: "ACTIVATION")
```

Thứ tự đảo sẽ lộ ra dưới dạng một dòng `DEACTIVATE(stillSelected=true)` nằm **sau** một dòng `ACTIVATE` của app khác.

Trong `EventTapManager.eventCallback`, nhánh `tapDisabledByTimeout`, thêm:

```swift
            debugLogCallback?("TAP DISABLED type=\(type.rawValue) — re-enabling")
```
(nhánh này đã tồn tại; chỉ thêm dòng log nếu chưa có.)

- [ ] **Step 2: Build và bàn giao cho chủ repo**

Run: `IMBUILD` → BUILD SUCCEEDED. Sau đó **dừng lại** và ghi hướng dẫn này vào báo cáo:

> Cần chạy thật: `ENABLE_DMG=false ./build_release.sh` → cài XKeyIM qua XKey Settings → bật debug log → chuyển sang XKeyIM. Kịch bản đo:
> 1. **Thứ tự activate/deactivate:** đổi qua lại giữa hai app đều dùng XKeyIM (ví dụ Terminal ↔ TextEdit) 10 lần.
> 2. **Tap có bị macOS tắt không:** gõ liên tục thật nhanh 30 giây trong Terminal.
> 3. **Latency:** gõ một đoạn dài, so cảm giác với marked text trước đó.
> Rồi gửi lại: `grep -E "ACTIVATION|TAP DISABLED" ~/XKey_Debug.log | tail -60`

- [ ] **Step 3: Phân tích kết quả**

Đọc log và trả lời dứt khoát ba câu:
- Có thấy `deactivate` tới **sau** `activate` của client mới không? Nếu **không** thấy sau 10 lần đổi app → ghi nhận, nhưng **giữ nguyên** `IMEActivation` (nó rẻ và là lưới an toàn); chỉ ghi vào báo cáo rằng chưa quan sát được.
- Có dòng `TAP DISABLED` nào không? Nếu **có** → mở task mới chuyển tap sang thread riêng (gọi `manager.start()` từ một `Thread` có `CFRunLoopRun()`), **không** làm trong task này.
- Có mất phím / gõ sai không?

- [ ] **Step 4: Revert log tạm + commit kết quả**

```bash
git checkout XKeyIM/TapController.swift XKeyIM/XKeyIMController.swift XKey/EventHandling/EventTapManager.swift
```
Ghi toàn bộ số đo vào báo cáo task (không commit code log).

---

### Task 10: Kịch bản kiểm thử tay + tài liệu

**Files:**
- Modify: `XKeyIM/README.md`

**Interfaces:** không có API mới.

- [ ] **Step 1: Bàn giao kịch bản kiểm thử tay cho chủ repo**

Ghi vào báo cáo, mỗi mục một dòng PASS/FAIL:

1. Terminal / iTerm2 / Warp / Ghostty — gõ `as` → `á`, **không gạch chân**, zsh-autosuggestion vẫn sống
2. Chrome omnibox có inline autocomplete — gõ URL tiếng Việt, suggestion không bị chốt thành text
3. Spotlight / Raycast — gõ tiếng Việt bình thường
4. Ô mật khẩu (System Settings hoặc `sudo` trong Terminal) — **không** biến đổi
5. Remote desktop client — passthrough, không chèn gì
6. App trong danh sách loại trừ — không gõ tiếng Việt
7. Thu hồi quyền Accessibility giữa lúc gõ → chuyển về marked text, từ đang gõ được chốt gọn
8. Quit XKey.app hoàn toàn rồi gõ — vẫn đầy đủ chức năng
9. Chạy song song XKey.app + XKeyIM — không nhân đôi ký tự
10. Để XKeyIM ở Terminal, ABC ở Chrome — sang Chrome gõ ra tiếng Anh, không lẫn tiếng Việt
11. Gõ nhanh liên tục 30 giây — không loạn ký tự, bàn phím không treo

- [ ] **Step 2: Cập nhật README XKeyIM**

Thêm mục mô tả: hai chế độ (phím thật khi có quyền Trợ năng / gạch chân khi không), cách cấp quyền qua menu bộ gõ, nút "Đặt lại & xin lại quyền" dùng khi Settings hiện đã bật mà vẫn không gõ được, và lưu ý XKeyIM hoạt động độc lập không cần XKey.app chạy.

- [ ] **Step 3: Commit**

```bash
git add XKeyIM/README.md
git commit -m "docs(xkeyim): document tap mode, permission flow, and recovery"
```

- [ ] **Step 4: Báo cáo tổng kết cho chủ repo**

Gồm: danh sách commit, kết quả 11 kịch bản tay, số đo Task 9, mức giảm dòng code từ Task 8, và các việc còn treo (nếu Task 9 chỉ ra cần chuyển thread).

---

## Ngoài phạm vi (đã cân nhắc, chủ động bỏ)

- **Chuyển tap sang thread riêng** — chỉ làm nếu Task 9 đo thấy `tapDisabledByTimeout`. Không đầu cơ.
- **Bỏ chế độ CGEvent của XKey.app** — quyết định sản phẩm riêng, không thuộc plan này.
- **Per-field detect cho browser omnibox** — đường tap của XKey.app đã có xử lý riêng cho omnibox; không thêm gì mới.
- **Sửa engine** — plan này không đụng `VNEngine`.
