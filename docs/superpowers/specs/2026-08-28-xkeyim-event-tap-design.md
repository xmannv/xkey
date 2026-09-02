# XKeyIM Event Tap — Design

**Ngày:** 2026-08-28 · **Trạng thái:** đã duyệt qua brainstorming, chờ lập plan

## Vấn đề

XKeyIM ghi chữ qua IMKit (`insertText` / `setMarkedText`). Với terminal, đường này hỏng theo bản chất: "document" của terminal là lưới ký tự, không app nào honor `replacementRange` tử tế (iTerm2 append → `as` ra `aá`), Warp báo caret cố định `0`, và AX không phơi text thật để đối chiếu. Marked text chạy đúng nhưng mở composition ⇒ shell không thấy phím live ⇒ **chết zsh-autosuggestions / tab-complete**, cộng gạch chân.

Sâu hơn: mọi bug ghi chữ gặp gần đây — Chrome chốt inline suggestion, Warp caret láo, iTerm append, Cmd+A mất dấu từ đầu — **đều nằm ở tầng ghi IMKit**. Lớp bug này không tồn tại ở đường CGEventTap mà XKey.app đã dùng ổn định.

Ràng buộc quyết định: **người dùng quit XKey.app và chỉ chạy XKeyIM**. Nên mọi thiết kế dựa vào XKey.app còn sống đều vô hiệu.

## Kết quả đo (2026-08-28, macOS 26.6.2)

Đo trực tiếp, không dựa vào tài liệu bên ngoài:

- `XKeyIM.app` thật, do macOS launch làm input method từ `~/Library/Input Methods/`, giữ nguyên `LSBackgroundOnly=true`: `AXIsProcessTrusted=true`, cả hai `CGPreflight*EventAccess()=true`, `tapCreate(.cghidEventTap)` và `tapCreate(.cgSessionEventTap)` **đều OK**.
- `LSBackgroundOnly=true` **không** chặn tap (A/B cùng grant, cùng DR, lật đúng biến đó).
- `AXIsProcessTrusted()` **không** nói dối khi chữ ký lệch — cả ba tín hiệu cùng báo `false`.
- **Không** cần notarize để nhận grant; bản Developer ID là đủ.
- Ký ad-hoc → DR gắn `cdhash` (rebuild là mất grant); Developer ID → DR identity-based. `XKeyIM.app` đang phát hành **đã** ký đúng loại.
- `tccutil reset Accessibility <bundle-id>` chạy được không cần root.
- App đặt trong `/private/tmp` **không bao giờ** nhận grant dù đã thêm tay vào danh sách; chuyển sang `~/Applications` là ăn ngay.

Kết luận: nhúng tap vào XKeyIM khả thi, không cần sửa plist, không cần notarize khi phát triển.

## Mục tiêu

1. Terminal trong XKeyIM gõ bằng phím thật: không gạch chân, giữ shell autocomplete.
2. **Một tầng ghi chữ dùng chung** giữa XKey.app và XKeyIM — sửa một lần, cả hai hưởng.
3. XKeyIM tự lập, không cần XKey.app chạy.
4. Ròng lại **ít code hơn hiện tại**.

## Ngoài phạm vi

- Bỏ chế độ CGEvent của XKey.app (cân nhắc sau, không phải bây giờ).
- Đổi engine hay luật chính tả.
- Đổi cách XKey.app chạy tap (giữ nguyên main run loop).

## Kiến trúc

### Điều kiện vũ trang

XKeyIM có `TapController` sở hữu một `EventTapManager`. Tap **chỉ** vũ trang khi cả hai đúng:

1. **Có quyền thật** — xác nhận bằng `CGPreflightPostEventAccess()` + `CGPreflightListenEventAccess()` **và** `tapCreate` trả non-nil. Không dùng `AXIsProcessTrusted()` làm cổng (đo thấy nó trung thực trên macOS 26, nhưng preflight là API đúng ngữ nghĩa cho quyền post/listen).
2. **IME đang active** — theo state machine `IMEActivation` (dưới).

XKeyIM **không** kiểm tra tap của XKey.app: khi XKeyIM là IME đang active cho app đang focus, nó có quyền ưu tiên và XKey.app phải nhường (một chiều, xem dưới).

### Hai chế độ ghi chữ

| Trạng thái | Ghi chữ | `XKeyIMController.handle()` |
|---|---|---|
| Tap vũ trang | Tap → `KeyboardEventHandler` → `CharacterInjector` (y hệt XKey.app) | `return false` cho mọi event — IMKit thành ống dẫn |
| Thiếu quyền | Marked text cho mọi app | Chỉ còn nhánh marked |

Không còn chế độ direct-insert. Người dùng không cấp quyền chấp nhận gạch chân mờ ở mọi app — đây là đánh đổi đã chọn có ý thức, đổi lấy việc xoá cả một tầng bug.

### `IMEActivation` — tap phải theo input source per-app

macOS nhớ input source **theo từng app**. Nếu XKeyIM được chọn ở Terminal nhưng ABC ở Chrome, một tap chạy toàn hệ thống sẽ gõ tiếng Việt vào Chrome. Tap buộc phải khoá theo trạng thái active của IME.

Nhưng `activateServer`/`deactivateServer` **đến không đúng thứ tự**: khi focus nhảy giữa hai client cùng dùng XKeyIM, IMK có thể gọi `activateServer` của client mới **trước** `deactivateServer` của client cũ. Một `deactivate → false` ngây thơ sẽ đè mất activate vừa tới ⇒ tap ngủ trong khi IME vẫn đang được chọn ⇒ phím lọt qua im lặng.

Thiết kế: **input source do OS chọn là sự thật duy nhất**, lifecycle callback chỉ là gợi ý.

```
struct IMEActivation {
    private(set) var isActive: Bool
    mutating func activate()                          // activateServer
    mutating func deactivate(stillSelected: Bool)     // bỏ qua nếu vẫn đang được chọn
    mutating func selectionChanged(isXKeyIM: Bool)    // TIS notification — thẩm quyền
}
```

Struct thuần, không dính IMKit ⇒ unit-test đầy đủ. Đăng ký `kTISNotifySelectedKeyboardInputSourceChanged` để tính lại thẩm quyền (cũng phủ ca chuyển per-document bỏ qua hẳn `activateServer`).

**Phải tự đo trước khi tin:** ghi log cả hai callback kèm input source tại mỗi lần đổi app, xác nhận thứ tự đảo có thật xảy ra trên macOS 26.

### Chống hai tap cùng ăn một phím

XKey.app hiện suspend tap khi XKeyIM là input source **toàn cục** — không đủ, vì input source là per-app.

Thiết kế một chiều: XKeyIM ghi vào App Group plist khi tap lên — `XKeyIM.tapArmed` (Bool), `XKeyIM.tapPID` (Int). `shouldProcessEvent` của XKey.app đọc bản cache (làm mới theo notification settings-changed, không đọc plist mỗi phím) và nhường khi cờ còn hiệu lực. Hiệu lực = cờ bật **và** `kill(pid, 0) == 0` — để XKeyIM chết đột ngột không khoá vĩnh viễn XKey.app.

Cờ chỉ tồn tại **trong lúc XKeyIM đang active**: bật ở `activateServer` (khi vũ trang được), xoá ở `deactivateServer` và `applicationWillTerminate`. Hệ quả đúng mong muốn: người dùng để XKeyIM ở Terminal và ABC ở Chrome thì sang Chrome cờ tự tắt, XKey.app lại làm việc bình thường — tốt hơn cơ chế suspend theo input source toàn cục hiện nay.

### Chuyển trạng thái giữa từ

Khi tap vũ trang hoặc hạ giữa lúc đang gõ dở (quyền bị thu hồi, IME deactivate), chốt từ hiện tại thành **word boundary tường minh**: `engine.reset()` + xoá tracking, thay vì để heuristic desync bắn muộn một phím — đúng bài học `demotedToMarkedText` đã fix.

### Threading

`EventTapManager.start()` gắn source vào `CFRunLoopGetCurrent()`, nên chạy trên thread riêng chỉ là gọi `start()` từ thread đó — không phải sửa `EventTapManager`. Nhưng nó kéo theo state cross-thread (`stop`/`suspend`/session-tap/NSWorkspace observer) phải audit.

**Quyết định: giữ tap trên main trước, rồi đo.** Khi tap vũ trang, `handle()` trả `false` ngay nên main của XKeyIM gần như rảnh — khác hẳn tình huống một controller làm việc thật trên main. Chỉ chuyển sang thread riêng nếu đo thấy `tapDisabledByTimeout` thật khi gõ nhanh.

## Chia sẻ code

Kiểm tra thực tế `project.pbxproj`: tầng tap **portable 100%, không cần refactor**.

**Thêm vào target XKeyIM (6 file):**
`EventTapManager.swift`, `KeyboardEventHandler.swift`, `CharacterInjector.swift`, `AdvancedInjectionMethods.swift`, `SecureInputStateMachine.swift`, `OverlayAppDetector.swift`.

- `MacroManager`, `SmartSwitchManager`, `AppBehaviorDetector`, `AXHelper`, `DebugLogger`, `SharedSettings` — **đã có trong cả 4 target**, không phải làm gì.
- `OverlayAppDetector` (331 dòng) chỉ phụ thuộc Cocoa/ApplicationServices + `DebugLogger` (đã shared).
- Hai tham chiếu tới `StatusBar`/`AppDelegate` trong tầng tap là **comment**, không phải code. `KeyboardEventHandler` chỉ import Cocoa + Combine.

Không tạo protocol/abstraction nào. Việc chia sẻ đạt được bằng compile-share — đúng cách 28 file engine đang dùng.

**Thêm mới:** `XKeyIM/IMEActivation.swift`, `XKeyIM/TapController.swift`.

**Phải nối dây:** XKeyIM tự đăng ký observer `NSWorkspace.didActivateApplicationNotification` để nuôi `cachedFrontmostBundleId` — nếu không, `isCurrentAppExcluded()` rơi vào truy vấn NSWorkspace live mỗi phím.

**Nguồn VI/EN:** dùng Smart Switch + trạng thái đã share. Bỏ `isVietnameseEnabled` cục bộ của XKeyIM (biến in-memory, không persist, không sync với XKey.app — đúng lớp bug desync vừa dọn).

## Xoá bớt

Khỏi `XKeyIMController.swift` (hiện 1.834 dòng):

- `replaceTextDirect` và toàn bộ logic nuốt inline-suggestion
- `XKeyIM/InPlaceProbe.swift` + `XKeyTests/InPlaceProbeTests.swift`
- Bốn tập học: `probeFallbackApps`, `probeConfirmedApps`, `probeExhaustedApps`, `caretLiarApps` (kèm key UserDefaults)
- Phát hiện caret-liar 3-strike
- Luật category `terminalApps` trong `shouldUseMarkedText`
- Toggle `isVietnameseEnabled` cục bộ

Giữ: nhánh marked text, guard passthrough sớm (secure input / remote desktop / excludedApps), xử lý `flagsChanged`, auto-capitalize, ESC undo, `didCommand`.

## Quyền — luồng người dùng

XKeyIM là process nền, không có cửa sổ settings. Luồng nằm hẳn trong XKeyIM để không phụ thuộc XKey.app:

1. Lần đầu active mà thiếu quyền → gọi prompt hệ thống một lần (không lặp lại mỗi lần active).
2. Menu input source (đã có sẵn) thêm: dòng trạng thái quyền, "Cấp quyền Accessibility…" (mở đúng pane System Settings), "Reset & xin lại quyền".
3. "Reset & xin lại" chạy `tccutil reset Accessibility com.codetay.inputmethod.XKey` rồi prompt lại **từ chính tiến trình này** — chỉ khi người dùng bấm, không bao giờ tự động.
4. Thiếu quyền không phải lỗi: rơi về marked text, vẫn gõ được.

## Bất biến & cách chặn

| Bất biến | Cơ chế |
|---|---|
| Không bao giờ hai tap cùng ăn một phím | Cờ App Group + `kill(pid,0)`; XKey.app nhường trong `shouldProcessEvent` |
| Không gõ tiếng Việt vào app đang dùng ABC | `IMEActivation` + notification TIS làm thẩm quyền |
| Event tự bơm không quay lại chính mình | `kXKeyEventMarker` ở tap; `handle()` trả `false` khi tap vũ trang |
| Mất quyền giữa chừng không làm chết gõ | Preflight lúc activate → tụt về marked + chốt word boundary |
| Ô mật khẩu không bị biến đổi | `SecureInputStateMachine` (đi kèm tầng tap) + guard sẵn có ở `handle()` |

## Đo lường bắt buộc

Tự đo, không kế thừa kết luận từ nguồn ngoài:

1. **Thứ tự activate/deactivate** — log hai callback + input source mỗi lần đổi app; xác nhận thứ tự đảo có thật.
2. **Tap trên main có bị macOS tắt không** — stress gõ nhanh, đếm `tapDisabledByTimeout`.
3. **Latency** — tap-trong-IME so với marked hiện tại, dùng hạ tầng ratchet của `KeystrokePerfTests`.

Kết quả (1) và (2) có quyền đổi thiết kế: nếu thứ tự không đảo, `IMEActivation` rút gọn; nếu tap bị tắt, chuyển sang thread riêng.

## Kiểm thử

- **Unit:** `IMEActivation` phủ đủ — activate/deactivate đúng thứ tự, deactivate muộn khi vẫn được chọn, TIS override, chuyển per-app.
- **Không unit-test được:** `XKeyIMController` và tầng tap (TEST_HOST là XKey.app). Dựa vào Injection Test in-app sẵn có.
- **Kịch bản tay bắt buộc trước merge:** Terminal / iTerm2 / Warp / Ghostty (có autosuggestion đang bật) · Chrome omnibox có inline autocomplete · Spotlight / Raycast · ô mật khẩu · remote desktop client · thu hồi quyền giữa lúc gõ · quit XKey.app rồi gõ · chạy song song cả hai app · gõ nhanh liên tục 30 giây (cascade).

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Synthetic event storm treo bàn phím | Cascade breaker + marker của tầng tap sẵn có; kịch bản gõ nhanh 30 giây |
| Tap bị macOS tắt vì callback chậm | Đo (2); sẵn phương án thread riêng |
| Người dùng không cấp quyền → gạch chân ở mọi app | Đã chấp nhận có ý thức; menu nêu rõ lý do và cách bật |
| Regression cho người dùng đang tắt marked text | Với AX: tốt hơn direct. Không AX: mất direct — nêu rõ trong release notes |
| Tap layer cõng giả định của XKey.app | Đã audit: chỉ 2 tham chiếu và đều là comment |

## Quyết định đã chốt

1. Tap là đường chính khi có AX; marked text là fallback duy nhất khi không.
2. Compile-share tầng tap, không tạo abstraction.
3. Tap vũ trang chỉ giữa activate/deactivate, theo `IMEActivation`.
4. Tap chạy trên main trước, chuyển thread chỉ khi đo thấy cần.
5. Chống hai tap bằng cờ App Group có kiểm sống tiến trình.
6. VI/EN lấy từ Smart Switch dùng chung; bỏ toggle cục bộ của XKeyIM.
7. Luồng quyền nằm hẳn trong XKeyIM (prompt + menu + reset).
