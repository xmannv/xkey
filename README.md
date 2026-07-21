# XKey

<div align="center">
  <img src="xkey.png" alt="XKey Logo" width="128" height="128">

  **Bộ gõ tiếng Việt hiện đại cho macOS · Modern Vietnamese input method for macOS**

  [![Version](https://img.shields.io/badge/version-1.2.24-blue.svg)](https://github.com/xmannv/xkey/releases)
  [![Homebrew Cask](https://img.shields.io/homebrew/cask/v/xkey?label=homebrew%20cask)](https://formulae.brew.sh/cask/xkey)
  [![macOS](https://img.shields.io/badge/macOS-12.0+-green.svg)](https://www.apple.com/macos/)
  [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
</div>

---

> Tài liệu này song ngữ. Mỗi phần trình bày tiếng Việt trước, tiếng Anh sau.
> This document is bilingual. Each section is written in Vietnamese first, then English.

---

## Giới thiệu · Introduction

### Tại sao XKey ra đời? · Why XKey?

**Tiếng Việt.** Các bộ gõ tiếng Việt hiện có trên macOS thường gặp một số vấn đề:

- Không tương thích với các phiên bản macOS mới nhất
- Còn nhiều lỗi chưa được sửa, ít được cập nhật và bảo trì
- Thiếu tính năng hiện đại, khó debug và tùy biến

XKey được xây dựng để giải quyết những vấn đề này.

**English.** Existing Vietnamese input methods on macOS often suffer from:

- Poor compatibility with the latest macOS releases
- Unfixed bugs and infrequent maintenance
- Missing modern features, and being hard to debug or customize

XKey is built to address these problems.

### Điểm nổi bật · Highlights

**Tiếng Việt.**

- Hiệu suất cao: viết hoàn toàn bằng Swift native, tối ưu cho macOS
- Tương thích tốt với các phiên bản macOS mới (12.0+)
- Ổn định và cập nhật thường xuyên, có auto-update
- Debug Window để theo dõi hoạt động của bộ gõ theo thời gian thực
- Các tính năng thông minh: Smart Switch, Macro, Quick Typing, kiểm tra chính tả, từ điển cá nhân
- Dịch thuật nhanh bằng phím tắt, hỗ trợ hơn 30 ngôn ngữ qua nhiều nhà cung cấp (Google, Tencent, Volcano)
- Giao diện hiện đại xây dựng bằng SwiftUI
- Chạy hoàn toàn cục bộ, không thu thập dữ liệu người dùng
- Hai chế độ hoạt động: CGEvent và Input Method Kit (XKeyIM)

**English.**

- High performance: written entirely in native Swift, optimized for macOS
- Good compatibility with recent macOS versions (12.0+)
- Stable, frequently updated, with built-in auto-update
- A Debug Window to observe the engine's behavior in real time
- Smart features: Smart Switch, Macro, Quick Typing, spell checking, personal dictionary
- Fast translation via hotkeys, supporting 30+ languages across multiple providers (Google, Tencent, Volcano)
- A modern SwiftUI interface
- Runs fully locally, with no user data collection
- Dual operating modes: CGEvent and Input Method Kit (XKeyIM)

---

## Tính năng chính · Core Features

<div align="center">
  <img src="xkey-panel.png" alt="XKey Settings Panel" width="800">
</div>

### 1. Hai chế độ hoạt động · Two operating modes

**Tiếng Việt.**

| Chế độ | Mô tả | Ưu điểm |
|--------|-------|---------|
| **CGEvent** (mặc định) | Dùng CGEvent injection | Không cần cấu hình, hoạt động ngay với mọi app |
| **XKeyIM** (thử nghiệm) | Dùng Input Method Kit | Mượt hơn trong Terminal, Spotlight, Address Bar |

**English.**

| Mode | Description | Advantage |
|------|-------------|-----------|
| **CGEvent** (default) | Uses CGEvent injection | No configuration needed, works with every app |
| **XKeyIM** (experimental) | Uses Input Method Kit | Smoother in Terminal, Spotlight, Address Bar |

### 2. Hỗ trợ đa kiểu gõ · Multiple typing methods

**Tiếng Việt.**

| Kiểu gõ | Mô tả | Ví dụ |
|---------|-------|-------|
| **Tự nhận kiểu gõ** | Tự nhận diện Telex hoặc VNI khi gõ | — |
| **Telex** | Kiểu gõ phổ biến nhất | `tieengs` → tiếng |
| **VNI** | Kiểu gõ truyền thống dùng số | `tie61ng` → tiếng |
| **Simple Telex 1** | Telex đơn giản (w không biến đổi) | `tieengs` → tiếng |
| **Simple Telex 2** | Telex + w cho ư/ơ | `tuaw` → tưa |

**English.**

| Method | Description | Example |
|--------|-------------|---------|
| **Auto-detect** | Automatically detects Telex or VNI while typing | — |
| **Telex** | The most common method | `tieengs` → tiếng |
| **VNI** | Traditional number-based method | `tie61ng` → tiếng |
| **Simple Telex 1** | Simplified Telex (w unchanged) | `tieengs` → tiếng |
| **Simple Telex 2** | Telex + w for ư/ơ | `tuaw` → tưa |

### 3. Bảng mã · Character encodings

**Tiếng Việt.**

- **Unicode (UTF-8)** — khuyến nghị, mặc định
- **TCVN3 (ABC)** — tương thích phần mềm cũ
- **VNI Windows** — tương thích font VNI

**English.**

- **Unicode (UTF-8)** — recommended, default
- **TCVN3 (ABC)** — compatible with legacy software
- **VNI Windows** — compatible with VNI fonts

### 4. Gõ nhanh · Quick Typing

**Tiếng Việt.** Tăng tốc độ gõ bằng các phím tắt thông minh.

| Tính năng | Chức năng |
|-----------|-----------|
| **Quick Telex** | `cc`→`ch`, `gg`→`gi`, `kk`→`kh`, `nn`→`ng`, `pp`→`ph`, `qq`→`qu`, `tt`→`th` |
| **Quick Start Consonant** | `f`→`ph`, `j`→`gi`, `w`→`qu` (đầu từ) |
| **Quick End Consonant** | `g`→`ng`, `h`→`nh`, `k`→`ch` (cuối từ) |

**English.** Speed up typing with smart shortcuts.

| Feature | Behavior |
|---------|----------|
| **Quick Telex** | `cc`→`ch`, `gg`→`gi`, `kk`→`kh`, `nn`→`ng`, `pp`→`ph`, `qq`→`qu`, `tt`→`th` |
| **Quick Start Consonant** | `f`→`ph`, `j`→`gi`, `w`→`qu` (word start) |
| **Quick End Consonant** | `g`→`ng`, `h`→`nh`, `k`→`ch` (word end) |

### 5. Macro (thay thế văn bản) · Macro (text shortcuts)

**Tiếng Việt.** Tự động thay thế văn bản bằng Macro:

- Tạo các từ viết tắt tùy chỉnh
- Import/export danh sách macro (.txt)
- Tùy chọn tự động viết hoa macro
- Tùy chọn thêm khoảng trắng sau macro
- Dùng được cả trong chế độ tiếng Anh

**English.** Automatically expand text with Macros:

- Create custom abbreviations
- Import/export macro lists (.txt)
- Optional auto-capitalization for macros
- Optional trailing space after a macro
- Works even in English mode

### 6. Công cụ chuyển đổi văn bản · Text conversion tools

**Tiếng Việt.** Truy cập nhanh bằng phím tắt tùy chỉnh.

| Tính năng | Mô tả |
|-----------|-------|
| **Chữ hoa/thường** | Viết hoa tất cả, viết thường tất cả, viết hoa chữ đầu, viết hoa mỗi từ |
| **Bảng mã** | Chuyển đổi Unicode ↔ TCVN3 ↔ VNI |
| **Xóa dấu** | Chuyển từ có dấu sang không dấu |

**English.** Accessible via custom hotkeys.

| Feature | Description |
|---------|-------------|
| **Letter case** | UPPERCASE, lowercase, Capitalize first letter, Capitalize Each Word |
| **Encoding** | Convert between Unicode ↔ TCVN3 ↔ VNI |
| **Remove diacritics** | Convert accented text to plain text |

### 7. Kiểm tra chính tả (thử nghiệm) · Spell checking (experimental)

**Tiếng Việt.**

- Dùng từ điển tiếng Việt (~200KB, giấy phép GPL)
- Tự động khôi phục khi gõ sai chính tả
- Hỗ trợ cả dấu mới (xoà) và dấu cũ (xóa)
- Từ điển cá nhân: thêm từ riêng để bỏ qua kiểm tra
- Import/export từ điển cá nhân

**English.**

- Uses a Vietnamese dictionary (~200KB, GPL license)
- Automatic recovery from misspellings
- Supports both new (xoà) and old (xóa) diacritic styles
- Personal dictionary: add your own words to skip checking
- Import/export the personal dictionary

### 8. Smart Switch

**Tiếng Việt.**

- Nhớ ngôn ngữ theo từng ứng dụng
- Hỗ trợ phát hiện các app overlay như Spotlight/Raycast/Alfred
- Tự động chuyển ngôn ngữ khi chuyển app

**English.**

- Remembers the language per application
- Detects overlay apps such as Spotlight/Raycast/Alfred
- Automatically switches language when changing apps

### 9. Dịch thuật nhanh · Fast translation

**Tiếng Việt.** Dịch văn bản ngay trong mọi ứng dụng bằng phím tắt tùy chỉnh. XKey cung cấp hai hướng dịch, mỗi hướng có phím tắt riêng và các tùy chọn hoạt động độc lập.

**English.** Translate text inside any application via custom hotkeys. XKey offers two translation directions, each with its own hotkey and independently toggled options.

#### Dịch sang ngôn ngữ đích · Translate to target language

**Tiếng Việt.** Dịch văn bản đang chọn (hoặc toàn bộ nội dung) từ ngôn ngữ nguồn sang ngôn ngữ đích.

Cách dùng:
1. Chọn (bôi đen) text cần dịch trong bất kỳ ứng dụng nào
2. Nhấn phím tắt (mặc định: `⌘ + ⇧ + T`)
3. Kết quả được xử lý theo các tùy chọn đã bật

Nếu không chọn text, XKey sẽ dịch toàn bộ nội dung trong ô nhập liệu.

| Tùy chọn | Mặc định | Mô tả |
|----------|----------|-------|
| **Thay thế text gốc** | Bật | Thay thế text đang chọn bằng bản dịch |
| **Copy vào clipboard** | Bật | Copy bản dịch vào clipboard |
| **Hiển thị popup** | Tắt | Hiển thị bản dịch trong overlay popup |
| **Tự ẩn popup** | 4 giây | Thời gian tự ẩn (0 = không tự ẩn) |

**English.** Translate the selected text (or the whole field) from the source language to the target language.

Usage:
1. Select the text you want to translate in any app
2. Press the hotkey (default: `⌘ + ⇧ + T`)
3. The result is processed according to the enabled options

If no text is selected, XKey translates the entire content of the input field.

| Option | Default | Description |
|--------|---------|-------------|
| **Replace original text** | On | Replace the selected text with the translation |
| **Copy to clipboard** | On | Copy the translation to the clipboard |
| **Show popup** | Off | Display the translation in an overlay popup |
| **Auto-hide popup** | 4 seconds | Auto-hide delay (0 = never) |

#### Dịch ngược về ngôn ngữ nguồn · Translate back to source language

**Tiếng Việt.** Dịch ngược văn bản từ ngôn ngữ đích về ngôn ngữ nguồn — hữu ích để xem nghĩa hoặc kiểm tra bản dịch.

Cách dùng:
1. Chọn text cần dịch ngược
2. Nhấn phím tắt (cần cấu hình trong Settings)
3. Kết quả được xử lý theo các tùy chọn đã bật

| Tùy chọn | Mặc định | Mô tả |
|----------|----------|-------|
| **Thay thế text gốc** | Tắt | Thay thế text đang chọn bằng bản dịch ngược |
| **Copy vào clipboard** | Tắt | Copy bản dịch vào clipboard |
| **Hiển thị popup** | Bật | Hiển thị bản dịch trong overlay popup |
| **Tự ẩn popup** | 4 giây | Thời gian tự ẩn (0 = không tự ẩn) |

**English.** Translate text back from the target language to the source language — useful for checking meaning or verifying a translation.

Usage:
1. Select the text to translate back
2. Press the hotkey (configure it in Settings)
3. The result is processed according to the enabled options

| Option | Default | Description |
|--------|---------|-------------|
| **Replace original text** | Off | Replace the selected text with the reverse translation |
| **Copy to clipboard** | Off | Copy the translation to the clipboard |
| **Show popup** | On | Display the translation in an overlay popup |
| **Auto-hide popup** | 4 seconds | Auto-hide delay (0 = never) |

Mỗi tùy chọn hoạt động hoàn toàn độc lập — có thể bật đồng thời thay thế text, copy clipboard và hiển thị popup.
Each option is fully independent — you may enable replacing text, copying to clipboard, and showing the popup at the same time.

#### Overlay popup

**Tiếng Việt.**

- Giao diện glassmorphism, tự động theo Light/Dark mode
- Nút copy nhanh bản dịch vào clipboard
- Nút tăng/giảm cỡ chữ (+/−)
- Kéo header để di chuyển, kéo cạnh để thay đổi kích thước
- Thời gian tự ẩn tùy chỉnh riêng cho mỗi hướng dịch
- Thanh countdown hiển thị thời gian còn lại

**English.**

- Glassmorphism UI that follows Light/Dark mode automatically
- A button to quickly copy the translation to the clipboard
- Buttons to increase/decrease font size (+/−)
- Drag the header to move it, drag edges to resize
- Independent auto-hide delay per translation direction
- A countdown bar showing the remaining time

#### Ngôn ngữ hỗ trợ · Supported languages

**Tiếng Việt.**

| Tính năng | Mô tả |
|-----------|-------|
| **Tự động nhận diện** | Nhận diện ngôn ngữ nguồn tự động |
| **Đa ngôn ngữ** | Hơn 30 ngôn ngữ phổ biến (Anh, Việt, Trung, Nhật, Hàn, Pháp, Đức...) |
| **Ngôn ngữ tùy chỉnh** | Nhập mã ISO 639-1 để dùng bất kỳ ngôn ngữ nào |

**English.**

| Feature | Description |
|---------|-------------|
| **Auto-detection** | Detects the source language automatically |
| **Multilingual** | 30+ common languages (English, Vietnamese, Chinese, Japanese, Korean, French, German...) |
| **Custom language** | Enter an ISO 639-1 code to use any language |

#### Nhà cung cấp dịch thuật · Translation providers

**Tiếng Việt.**

| Nhà cung cấp | Mô tả |
|--------------|-------|
| **Google Translate** | Miễn phí, đa ngôn ngữ, chất lượng tốt |
| **Tencent Transmart** | Miễn phí, tối ưu cho các ngôn ngữ châu Á |
| **Volcano Engine** | Miễn phí, chất lượng cao cho Trung ↔ Việt |

Bạn có thể bật/tắt từng nhà cung cấp và thay đổi thứ tự ưu tiên trong **Thiết lập → Dịch thuật**.

**English.**

| Provider | Description |
|----------|-------------|
| **Google Translate** | Free, multilingual, good quality |
| **Tencent Transmart** | Free, optimized for Asian languages |
| **Volcano Engine** | Free, high quality for Chinese ↔ Vietnamese |

You can enable/disable each provider and change their priority under **Settings → Translation**.

#### Tính năng nâng cao · Advanced behavior

**Tiếng Việt.**

- Fallback tự động: nếu nhà cung cấp ưu tiên lỗi hoặc trả kết quả rỗng, tự động thử nhà cung cấp tiếp theo
- Thông báo lỗi rõ ràng cho từng loại lỗi (mạng, giới hạn tần suất, kết quả không hợp lệ...)
- Giữ nguyên định dạng chữ hoa/thường (ALL CAPS, Capitalize, lowercase)
- Overlay loading hiển thị trạng thái đang dịch tại vị trí con trỏ
- Lấy văn bản thông minh: Accessibility API, fallback sang Clipboard

**English.**

- Automatic fallback: if the preferred provider fails or returns empty, the next provider is tried automatically
- Clear error messages for each error type (network, rate limit, invalid result...)
- Preserves letter case (ALL CAPS, Capitalize, lowercase)
- A loading overlay showing translation progress at the cursor
- Smart text retrieval: Accessibility API with a Clipboard fallback

Cấu hình · Configuration: **Settings → Translation**

### 10. Quản lý Input Sources · Input source management

**Tiếng Việt.**

- Xem danh sách tất cả Input Sources
- Bật/tắt XKey cho từng Input Source cụ thể
- Phím tắt chuyển nhanh sang XKey/ABC
- Tự động phát hiện các Input Source tiếng Việt khác

**English.**

- View the list of all input sources
- Enable/disable XKey for specific input sources
- A hotkey to quickly switch between XKey/ABC
- Automatic detection of other Vietnamese input sources

### 11. Hiệu chỉnh engine theo ứng dụng · Per-app engine tuning (Window Title Rules)

**Tiếng Việt.** Phát hiện ngữ cảnh đặc biệt dựa trên tiêu đề cửa sổ, giải quyết vấn đề gõ tiếng Việt trong các web app.

| Web App | Xử lý đặc biệt |
|---------|----------------|
| Google Docs/Sheets/Slides | Tắt marked text, slow injection |
| Notion, Figma | Điều chỉnh delay phù hợp |
| Và nhiều app khác | Tùy chỉnh theo nhu cầu |

Tính năng Window Title Rules:
- Tự động nhận diện web app trong bất kỳ trình duyệt nào
- Áp dụng xử lý phù hợp cho từng ngữ cảnh
- Ghi đè injection method, delay, phương thức gửi text
- Tự động chuyển Input Source khi rule khớp
- Hỗ trợ Regex matching

Cấu hình: **Settings → Nâng cao → Hiệu chỉnh XKey Engine theo ứng dụng**

**English.** Detects special contexts based on window titles, solving Vietnamese typing issues in web apps.

| Web App | Special handling |
|---------|------------------|
| Google Docs/Sheets/Slides | Disable marked text, slow injection |
| Notion, Figma | Adjusted delays |
| And many other apps | Customizable as needed |

Window Title Rules features:
- Automatically recognizes web apps in any browser
- Applies the right handling per context
- Overrides injection method, delay, and text-sending method
- Automatically switches input source when a rule matches
- Supports Regex matching

Configuration: **Settings → Advanced → Per-app engine tuning**

#### Thêm quy tắc mới · Adding a new rule

**Tiếng Việt.**

1. Mở **Settings → Nâng cao → Hiệu chỉnh XKey Engine theo ứng dụng**
2. Nhấn **"Thêm quy tắc"**
3. Điền thông tin:
   - **Tên**: tên hiển thị cho quy tắc
   - **Bundle ID**: `*` để áp dụng cho tất cả app, hoặc chọn app cụ thể
   - **Title Pattern**: từ khóa để nhận diện trong tiêu đề cửa sổ
   - **Match mode**: Chứa, Bắt đầu bằng, Kết thúc bằng, Khớp chính xác, hoặc Regex
4. Cấu hình behavior (tùy chọn):
   - **Ghi đè Marked Text**: bật/tắt gạch chân khi gõ
   - **Ghi đè Injection Method**: Fast, Slow, Selection, Autocomplete, AX Direct hoặc Passthrough
   - **Tùy chỉnh Injection Delays**: delay (µs) cho Backspace, Wait, Text
   - **Phương thức gửi text**: Chunked hoặc One-by-One
   - **Chuyển Input Source**: tự động chuyển sang Input Source cụ thể
5. Nhấn **"Thêm"** để lưu

Lưu ý: Nếu dùng Google Docs/Sheets/Slides với giao diện tiếng Việt, tiêu đề cửa sổ sẽ là "Google Tài liệu", "Google Trang tính", "Google Trang trình bày". Cần tạo thêm quy tắc với Title Pattern tương ứng.

**English.**

1. Open **Settings → Advanced → Per-app engine tuning**
2. Click **"Add rule"**
3. Fill in the details:
   - **Name**: the display name of the rule
   - **Bundle ID**: `*` to apply to all apps, or pick a specific app
   - **Title Pattern**: a keyword to match in the window title
   - **Match mode**: Contains, Starts with, Ends with, Exact match, or Regex
4. Configure behavior (optional):
   - **Override Marked Text**: enable/disable underline while typing
   - **Override Injection Method**: Fast, Slow, Selection, Autocomplete, AX Direct, or Passthrough
   - **Custom Injection Delays**: delays (µs) for Backspace, Wait, Text
   - **Text sending method**: Chunked or One-by-One
   - **Switch Input Source**: automatically switch to a specific input source
5. Click **"Add"** to save

Note: If you use Google Docs/Sheets/Slides with a Vietnamese UI, the window titles appear as "Google Tài liệu", "Google Trang tính", "Google Trang trình bày". Add matching rules with the corresponding Title Pattern.

### 12. Tính năng khác · Other features

**Tiếng Việt.**

| Tính năng | Mô tả |
|-----------|-------|
| **Hoàn tác gõ (Undo)** | Phím tắt để hoàn tác việc bỏ dấu (`tiếng` → `tieesng`) |
| **Free Mark** | Đặt dấu tự do ở bất kỳ vị trí nào trong từ |
| **Kiểu gõ hiện đại** | Hỗ trợ cả dấu mới (oà/uý) và dấu cũ (òa/úy) |
| **Tạm tắt thông minh** | Ctrl tắt chính tả, Option tắt bộ gõ tạm thời |
| **Thanh công cụ nổi** | Điều khiển nhanh XKey tại vị trí con trỏ |
| **Loại trừ ứng dụng** | Tắt XKey cho các app cụ thể |
| **Auto-update** | Tự động cập nhật phiên bản mới với Sparkle |
| **Backup/Restore** | Sao lưu và khôi phục toàn bộ cài đặt |
| **Debug Window** | Theo dõi hoạt động của bộ gõ theo thời gian thực |

**English.**

| Feature | Description |
|---------|-------------|
| **Undo typing** | A hotkey to undo diacritic placement (`tiếng` → `tieesng`) |
| **Free Mark** | Place diacritics anywhere in the word |
| **Modern diacritics** | Supports both new (oà/uý) and old (òa/úy) styles |
| **Smart temporary off** | Ctrl disables spell check, Option temporarily disables the engine |
| **Floating toolbar** | Quick XKey controls at the cursor position |
| **App exclusion** | Disable XKey for specific apps |
| **Auto-update** | Automatic updates via Sparkle |
| **Backup/Restore** | Back up and restore all settings |
| **Debug Window** | Observe the engine's activity in real time |

---

## Cài đặt · Installation

### Yêu cầu hệ thống · System requirements

**Tiếng Việt.**

- macOS 12.0 (Monterey) trở lên
- Quyền truy cập Accessibility

**English.**

- macOS 12.0 (Monterey) or later
- Accessibility permission

### Cài qua Homebrew (khuyến nghị) · Install via Homebrew (recommended)

**Tiếng Việt.** XKey có mặt trên [Homebrew Cask](https://formulae.brew.sh/cask/xkey). Chỉ cần một lệnh:

**English.** XKey is available on [Homebrew Cask](https://formulae.brew.sh/cask/xkey). A single command:

```bash
brew install --cask xkey
```

Cập nhật · Upgrade:

```bash
brew upgrade --cask xkey
```

Gỡ cài đặt · Uninstall:

```bash
brew uninstall --cask xkey
```

**Tiếng Việt.** Sau khi cài, vẫn cần cấp quyền Accessibility: **System Settings → Privacy & Security → Accessibility** → bật quyền cho XKey.

**English.** After installing, you still need to grant Accessibility permission: **System Settings → Privacy & Security → Accessibility** → enable XKey.

### Cài từ Release · Install from a release

**Tiếng Việt.**

1. Tải file `XKey.dmg` mới nhất từ [Releases](https://github.com/xmannv/xkey/releases)
2. Mở DMG và kéo XKey.app vào thư mục Applications
3. Mở XKey từ Applications
4. Cấp quyền Accessibility: **System Settings → Privacy & Security → Accessibility** → bật quyền cho XKey

**English.**

1. Download the latest `XKey.dmg` from [Releases](https://github.com/xmannv/xkey/releases)
2. Open the DMG and drag XKey.app into the Applications folder
3. Launch XKey from Applications
4. Grant Accessibility permission: **System Settings → Privacy & Security → Accessibility** → enable XKey

### Build từ mã nguồn · Build from source

```bash
# Clone repository
git clone https://github.com/xmannv/xkey.git
cd xkey/XKey

# Build release
./build_release.sh

# Output: Release/XKey.app, Release/XKey.dmg
```

---

## XKeyIM — Input Method Kit Mode

**Tiếng Việt.** XKeyIM là input method dùng IMKit của Apple, cung cấp trải nghiệm gõ mượt hơn trong các ứng dụng có độ trễ phản hồi thấp hoặc có cơ chế autocomplete như Terminal, Spotlight, Address Bar.

**English.** XKeyIM is an input method built on Apple's IMKit, offering a smoother typing experience in apps with low response latency or autocomplete behavior such as Terminal, Spotlight, and the Address Bar.

### Bundle Identifiers

| Component | Bundle ID |
|-----------|-----------|
| XKey (main app) | `com.codetay.XKey` |
| XKeyIM (input method) | `com.codetay.inputmethod.XKey` |
| App Group | `group.com.codetay.xkey` |

### Tính năng XKeyIM · XKeyIM features

**Tiếng Việt.**

| Tính năng | Mô tả |
|-----------|-------|
| **Marked Text Mode** | Hiển thị gạch chân khi gõ — ổn định, tương thích tốt (khuyến nghị) |
| **Direct Mode** | Không gạch chân — có thể gặp lỗi trong một số app |
| **Phím hoàn tác** | ESC để hoàn tác (ví dụ: "thử" → "thur") |
| **Phím tắt chuyển nhanh** | Tùy chỉnh phím tắt toggle giữa XKey và ABC |

**English.**

| Feature | Description |
|---------|-------------|
| **Marked Text Mode** | Shows an underline while typing — stable and compatible (recommended) |
| **Direct Mode** | No underline — may misbehave in some apps |
| **Undo key** | ESC to undo (e.g., "thử" → "thur") |
| **Quick toggle hotkey** | Customizable hotkey to toggle between XKey and ABC |

### Cài đặt XKeyIM · Installing XKeyIM

**Tiếng Việt.**

1. Mở XKey Settings → **Input Sources**
2. Nhấn **"Cài đặt XKeyIM..."**
3. Copy `XKeyIM.app` vào `~/Library/Input Methods/`
4. Logout/Login lại
5. Mở **System Settings → Keyboard → Input Sources**
6. Nhấn **"+"** và thêm **"XKey Vietnamese"**

**English.**

1. Open XKey Settings → **Input Sources**
2. Click **"Install XKeyIM..."**
3. Copy `XKeyIM.app` into `~/Library/Input Methods/`
4. Log out and log back in
5. Open **System Settings → Keyboard → Input Sources**
6. Click **"+"** and add **"XKey Vietnamese"**

### Quyền truy cập cho XKeyIM · Permissions for XKeyIM

**Tiếng Việt.** XKeyIM cần quyền **Accessibility** để xử lý một số tổ hợp phím đặc biệt (như Ctrl+C trong Terminal):

1. Mở **System Settings → Privacy & Security → Accessibility**
2. Nhấn **"+"** và thêm `XKeyIM.app` từ `~/Library/Input Methods/`
3. Bật quyền cho XKeyIM

Nếu không cấp quyền Accessibility, XKeyIM vẫn gõ tiếng Việt bình thường. Quyền này chỉ cần để đảm bảo các phím tắt như Ctrl+C hoạt động đúng khi đang có marked text.

Phím hoàn tác: XKeyIM dùng ESC làm phím hoàn tác mặc định (không thể tùy chỉnh do hạn chế của Input Method Kit). Bấm ESC khi đang gõ từ có dấu sẽ hoàn tác về dạng không dấu.

**English.** XKeyIM needs **Accessibility** permission to handle certain special key combinations (such as Ctrl+C in Terminal):

1. Open **System Settings → Privacy & Security → Accessibility**
2. Click **"+"** and add `XKeyIM.app` from `~/Library/Input Methods/`
3. Enable XKeyIM

Without Accessibility permission, XKeyIM still types Vietnamese normally. The permission is only needed so shortcuts like Ctrl+C behave correctly while marked text is present.

Undo key: XKeyIM uses ESC as the default undo key (not customizable due to Input Method Kit limitations). Pressing ESC while typing an accented word reverts it to its plain form.

### Build XKeyIM từ mã nguồn · Build XKeyIM from source

Xem hướng dẫn chi tiết · See detailed instructions: [XKeyIM/README.md](XKeyIM/README.md)

---

## Phát triển · Development

### Cấu trúc dự án · Project structure

```
XKey/
├── Shared/               # Shared code between XKey and XKeyIM
│   ├── SharedSettings.swift
│   ├── AppBehaviorDetector.swift
│   ├── DebugLogger.swift
│   └── TranslationLanguage.swift
├── XKey/
│   ├── App/              # Entry point, AppDelegate
│   ├── Core/             # Core engine
│   │   ├── Engine/       # Vietnamese input engine (VNEngine.swift, etc.)
│   │   ├── Models/       # Data models (Preferences, VNCharacter, etc.)
│   │   └── Translation/  # Translation service with multiple providers
│   ├── EventHandling/    # Keyboard event handling, EventTap
│   ├── InputMethod/      # Input source management
│   ├── UI/               # SwiftUI views and settings sections
│   └── Utilities/        # Helper utilities
├── XKeyIM/               # Input Method Kit bundle
│   ├── Info.plist        # IMKit configuration
│   ├── main.swift        # Entry point
│   └── XKeyIMController.swift
├── XKeyTests/            # Unit tests
├── Release/              # Build output
└── build_release.sh      # Build script
```

### Build script

**Tiếng Việt.** Script `build_release.sh` hỗ trợ nhiều tùy chọn để tùy biến quá trình build:

**English.** The `build_release.sh` script supports several options to customize the build process:

```bash
# Build với code signing + DMG (mặc định) · with code signing + DMG (default)
./build_release.sh

# Build không code signing · without code signing
ENABLE_CODESIGN=false ./build_release.sh

# Build không XKeyIM · without XKeyIM
ENABLE_XKEYIM=false ./build_release.sh

# Full release: Notarization + Auto GitHub Release
ENABLE_NOTARIZE=true ./build_release.sh

# Tạo GitHub Release tự động · create a GitHub Release automatically
ENABLE_GITHUB_RELEASE=true ./build_release.sh
```

#### Tự động tạo GitHub Release · Automatic GitHub Release

**Tiếng Việt.** Script hỗ trợ tự động tạo GitHub Release khi build hoàn thành.

Yêu cầu:
- Đã cài GitHub CLI (`gh`): `brew install gh`
- Đã đăng nhập: `gh auth login`

Tính năng:
- Tự động đọc version từ `Info.plist`
- Tạo tag `v{version}` và release trên GitHub
- Upload `XKey.dmg` và `signature.txt` (cho Sparkle auto-update)
- Tự động tạo release notes từ git commits
- Trigger GitHub Actions để tạo appcast

Custom release notes: tạo file `.release_notes.md` ở thư mục gốc để dùng release notes tùy chỉnh thay vì auto-generate.

**English.** The script can create a GitHub Release automatically after a build finishes.

Requirements:
- GitHub CLI (`gh`) installed: `brew install gh`
- Logged in: `gh auth login`

Features:
- Reads the version from `Info.plist`
- Creates a `v{version}` tag and a GitHub release
- Uploads `XKey.dmg` and `signature.txt` (for Sparkle auto-update)
- Auto-generates release notes from git commits
- Triggers GitHub Actions to generate the appcast

Custom release notes: create a `.release_notes.md` file at the project root to use custom notes instead of auto-generation.

```bash
# Cách 1: Bật thủ công · Option 1: enable manually
ENABLE_GITHUB_RELEASE=true ./build_release.sh

# Cách 2: Tự động khi notarize · Option 2: automatic on notarize (full release)
ENABLE_NOTARIZE=true ./build_release.sh
```

### Công nghệ sử dụng · Technology stack

| Công nghệ · Technology | Mục đích · Purpose |
|------------------------|--------------------|
| **Swift Native** | 100% Swift, tối ưu cho macOS · optimized for macOS |
| **SwiftUI** | Giao diện hiện đại · modern user interface |
| **Input Method Kit** | Input method native (XKeyIM) |
| **Core Graphics Events** | Xử lý và injection sự kiện bàn phím · keyboard event handling and injection |
| **Accessibility API** | Phát hiện focus với AXObserver · focus detection with AXObserver |
| **Sparkle** | Framework auto-update · auto-update framework |

### Lưu trữ cài đặt · Settings persistence

**Tiếng Việt.** XKey dùng hệ thống lưu trữ kép để cài đặt không bị mất:

1. **Primary Storage**: App Group UserDefaults (`group.com.codetay.inputmethod.XKey`)
   - Chia sẻ settings giữa XKey và XKeyIM
   - Cho phép cả hai app đồng bộ cài đặt theo thời gian thực
2. **Backup Storage**: UserDefaults.standard
   - Tự động backup mỗi khi settings thay đổi
   - Tự động restore nếu App Group container bị reset

Lợi ích:
- Settings được giữ nguyên khi cập nhật phiên bản mới
- Tự động migrate từ phiên bản cũ
- Backup an toàn
- Đồng bộ giữa XKey và XKeyIM

**English.** XKey uses a dual storage system so settings are never lost:

1. **Primary Storage**: App Group UserDefaults (`group.com.codetay.inputmethod.XKey`)
   - Shares settings between XKey and XKeyIM
   - Lets both apps sync settings in real time
2. **Backup Storage**: UserDefaults.standard
   - Automatically backs up whenever settings change
   - Automatically restores if the App Group container is reset

Benefits:
- Settings persist across version updates
- Automatic migration from older versions
- Safe backups
- Synchronization between XKey and XKeyIM

---

## Cảm ơn · Acknowledgements

**Tiếng Việt.** XKey được phát triển dựa trên:

- **OpenKey**: bộ gõ tiếng Việt mã nguồn mở
- **Unikey**: bộ gõ tiếng Việt phổ biến

**English.** XKey is built upon:

- **OpenKey**: an open-source Vietnamese input method
- **Unikey**: a popular Vietnamese input method

---

## Giấy phép · License

**Tiếng Việt.** Dự án được phát hành dưới giấy phép MIT. Xem file [LICENSE](LICENSE) để biết thêm chi tiết.

**English.** This project is released under the MIT license. See the [LICENSE](LICENSE) file for details.

---

## Liên hệ · Contact

- **Issues**: [GitHub Issues](https://github.com/xmannv/xkey/issues)
- **Discussions**: [GitHub Discussions](https://github.com/xmannv/xkey/discussions)

---

<div align="center">
  Made by XKey Contributors

  Nếu thấy hữu ích, hãy cho dự án một star. · If you find it useful, please give the project a star.
</div>
