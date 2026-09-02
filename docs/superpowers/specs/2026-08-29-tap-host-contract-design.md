# Tap Host Contract — Design

**Ngày:** 2026-08-29 · **Trạng thái:** đã duyệt hướng qua brainstorming, chờ lập plan
**Tiền đề:** `docs/superpowers/specs/2026-08-28-xkeyim-event-tap-design.md` (XKeyIM đã có tap; branch `feat/xkeyim-event-tap`)

## Vấn đề

Tầng tap (`EventTapManager`, `KeyboardEventHandler`, `CharacterInjector`, `AdvancedInjectionMethods`, `SecureInputStateMachine`, `OverlayAppDetector`) được viết với giả định ngầm rằng `XKey/App/AppDelegate.swift` đứng sau lưng cung cấp mọi thứ nó cần. Giả định đó chưa từng được viết ra thành hợp đồng.

Khi XKeyIM biên dịch cùng tầng tap đó vào target của mình, nó thừa hưởng **code** nhưng không thừa hưởng **host**. Kết quả: 24 cơ chế hỗ trợ, XKeyIM cung cấp 5.

Điều khiến lớp lỗi này nguy hiểm hơn bình thường: **8 mảnh state được ghi từ bên ngoài đều có mặc định im lặng, không phải mặc định đúng** — `overlayAppNameProvider`, `remoteDesktopInjectModeProvider`, `customRules`, `windowTitleRulesEnabled`, `confirmedInjectionMethod`, `confirmedInputMethodPolicy`, engine settings, `excludedBundleIds`. Tất cả là optional gọi bằng `?()`. Compiler không báo, runtime không nổ; chỉ hành vi khác đi. Ta đã phát hiện ba lỗ theo đúng kiểu đó, mỗi lỗ qua một bug report của người dùng.

Spec trước ghi "tầng tap portable 100%, zero refactor". Đúng cho **biên dịch**, sai cho **hành vi**. Đó là lỗi thiết kế cần sửa tận gốc, không vá tiếp.

## Mục tiêu

1. Thiếu một mảnh của hợp đồng phải là **lỗi biên dịch**, không phải bug report.
2. Logic hỗ trợ tap tồn tại **một bản duy nhất**, cả hai process cùng dùng — không nhân đôi.
3. XKeyIM chạy độc lập với XKey.app mà vẫn đúng: đúng kiểu gõ, đúng bảng mã, tôn trọng excluded apps và Window Title Rules.
4. Không làm hỏng chế độ CGEvent của XKey.app đang chạy ổn định.

## Ngoài phạm vi

- Đổi engine, luật chính tả, hay cơ chế tap.
- Bỏ chế độ CGEvent của XKey.app.
- Tính năng chỉ thuộc UI của XKey.app (convert tool, dịch, toolbar) — XKeyIM sẽ không có chúng, và hợp đồng phải **nói rõ điều đó** thay vì để chúng nil một cách tình cờ.

## Hai loại phụ thuộc, hai lời giải

Audit chia 24 cơ chế thành hai nhóm có bản chất khác nhau:

**Loại A — tầng tap ĐỌC.** Provider, preferences, danh sách loại trừ, custom rules, cấu hình hotkey. Vấn đề là chúng optional-mặc-định-im-lặng.

**Loại B — host ĐẨY vào.** App switch, mouse click, AX focus/title change, overlay visibility. Vấn đề là ~300 dòng máy móc event-driven chỉ tồn tại trong `AppDelegate`.

### Loại A → `TapEnvironment`

Một kiểu duy nhất gom mọi thứ tầng tap cần đọc, **bắt buộc khi khởi tạo**. Không optional có default im lặng: mảnh nào thực sự có thể vắng thì phải là `Optional` **tường minh** kèm tài liệu nói vắng nghĩa là gì.

Nội dung (từ audit, mỗi mục có file:line trong bản ghi):

| Nhóm | Thành phần |
|---|---|
| Provider | `overlayAppName`, `remoteDesktopInjectMode` |
| Rules | `customRules` (nạp + theo dõi `.windowTitleRulesDidChange`), `windowTitleRulesEnabled` |
| Preferences | toàn bộ thứ `applyAllSettings` đang đẩy: kiểu gõ, bảng mã, macro, spell-check, quick telex, upper-case, custom consonants, restore |
| Exclusion | `excludedApps`, `exclusionRulesEnabled` |
| Ngôn ngữ | trạng thái bật/tắt tiếng Việt dùng chung |
| Hotkey | cấu hình + hành động; **mỗi hành động là một trường tường minh**, host nào không làm được thì gán một giá trị "không hỗ trợ" có tên, không phải nil ngầm |
| Hạ tầng | `AXHelper.setGlobalMessagingTimeout` — chặn cứng mọi AX call trên tap thread |

`AXHelper.setGlobalMessagingTimeout(0.25)` hiện chỉ được gọi ở `AppDelegate.swift:192`. Thiếu nó, mọi AX call trên tap thread dùng mặc định hệ thống (~6s); một app treo là macOS tắt tap. Đây là primitive của mọi cú freeze và phải nằm trong hợp đồng.

### Loại B → dời `TapEventSource` ra tầng dùng chung

Không viết lại trong `TapController`. **Dời** khối máy móc từ `AppDelegate` sang một component dùng chung mà cả hai target biên dịch; `AppDelegate` trở thành người tiêu thụ mỏng.

Dời sang:

- Observer app switch (`didActivateApplication` / `didDeactivateApplication`) và khối re-prime +50ms đi kèm
- AXObserver focus + title theo từng app, kèm throttle 100ms và debounce 150/250ms
- Global mouse-click monitor, kèm `handleFocusCheck` +0.1s và `detectBehaviorWithRetry` 3 lần
- Callback `onOverlayVisibilityChanged`
- `ForceAccessibilityManager.applyForCurrentApp()` — **hiện chưa nằm trong target XKeyIM**, phải thêm
- `engine.notifyFocusChanged()`

Ở lại `AppDelegate` (là việc của app, không phải của tap): status bar, cửa sổ Settings, Sparkle, iCloud sync, temp-off toolbar, convert tool, dịch, cửa sổ Debug.

**Nguyên tắc dời:** cơ học, giữ nguyên hành vi từng dòng. Không "tiện tay cải tiến". Mọi thay đổi hành vi trong bước dời là lỗi.

## Bề mặt hợp đồng

Tầng tap nhận đúng hai thứ khi khởi tạo: một `TapEnvironment` và một `TapEventSource`. Cả hai bắt buộc.

Hai host implement:
- `AppDelegate` — đầy đủ, gồm cả hành động hotkey gắn UI
- `TapController` (XKeyIM) — đầy đủ phần lõi; hành động chỉ-có-ở-UI khai báo tường minh là không hỗ trợ

Điều này biến "XKeyIM không có convert tool" từ một closure nil tình cờ thành một quyết định đọc được trong code.

## Rủi ro

| Rủi ro | Giảm thiểu |
|---|---|
| Dời code làm hỏng chế độ CGEvent đang ổn | Dời cơ học từng khối, mỗi khối một commit; sau mỗi commit chạy full suite; kiểm tay XKey.app trước khi đụng XKeyIM |
| Hợp đồng phình thành "mọi thứ AppDelegate làm" | Tiêu chí: chỉ vào hợp đồng nếu tầng tap ĐỌC nó hoặc CẦN nó để đúng. Status bar/Settings/Sparkle ở ngoài |
| Hai host lệch nhau lần nữa | Đúng mục tiêu số 1: bắt buộc khi khởi tạo ⇒ thiếu là lỗi biên dịch |
| Singleton tĩnh nhiễm chéo | `KeyboardEventHandler.init()` ghi đè `VNEngine._macroManager` / `_smartSwitchManager` cho cả process, nên engine marked-text của XKeyIM đổi hành vi tuỳ theo tap đã arm hay chưa. Phải xử lý trong đợt này |

## Thứ tự triển khai

1. `TapEnvironment` + cả hai host cung cấp nó. **Riêng bước này chữa cú freeze Raycast/Spotlight và các lỗ đúng-sai lớn nhất** (kiểu gõ, bảng mã, excluded apps, custom rules).
2. Dời từng khối loại B, mỗi khối một commit, XKey.app xanh sau mỗi bước.
3. `TapController` tiêu thụ `TapEventSource`.
4. Sửa nhiễm chéo singleton tĩnh.
5. Đo lại thực địa: freeze, đổi tab trong cùng app, click giữa từ, 30 giây gõ nhanh.

Bước 1 có giá trị độc lập: nếu phải dừng giữa chừng, sản phẩm vẫn tốt hơn hiện tại rõ rệt.

## Kiểm chứng

- Full suite xanh sau **mỗi** commit dời (trừ hai nhóm môi trường đã biết).
- Kiểm tay XKey.app (chế độ CGEvent) sau bước 2: gõ thường, click giữa từ, đổi app, Spotlight, Chrome omnibox — phải **không đổi** so với trước.
- Kiểm tay XKeyIM sau bước 3: chính các kịch bản đã hỏng (Raycast/Spotlight freeze, đổi app, đổi tab trong cùng app, click giữa từ), cộng kiểu gõ VNI và một app trong danh sách loại trừ.
- Một test khẳng định hợp đồng đầy đủ: dựng `TapEnvironment` thiếu mảnh phải **không biên dịch được** — ghi lại bằng test biên dịch hoặc, nếu không khả thi, bằng một test khẳng định mọi trường đều được điền từ cả hai host.
