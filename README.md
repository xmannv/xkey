# XKey

<div align="center">
  <img src="xkey.png" alt="XKey Logo" width="128" height="128">
  
  **Bộ gõ tiếng Việt hiện đại cho macOS**
  
  [![Version](https://img.shields.io/badge/version-1.2.20-blue.svg)](https://github.com/xmannv/xkey/releases)
  [![Homebrew Cask](https://img.shields.io/homebrew/cask/v/xkey?label=homebrew%20cask)](https://formulae.brew.sh/cask/xkey)
  [![macOS](https://img.shields.io/badge/macOS-12.0+-green.svg)](https://www.apple.com/macos/)
  [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
</div>

---

## 📖 Giới thiệu

### 🎯 Tại sao XKey ra đời?

Các bộ gõ tiếng Việt hiện tại trên macOS đang gặp một số vấn đề:
- 🚫 **Không tương thích** với các phiên bản macOS mới nhất
- 🐛 **Nhiều bug** chưa được sửa, ít được tác giả cập nhật và bảo trì
- 🔧 **Thiếu tính năng** hiện đại, khó debug và tùy biến linh hoạt

**XKey** được tạo ra để giải quyết triệt để những vấn đề trên!

### ✨ Điểm nổi bật

- ⚡ **Hiệu suất vượt trội**: Viết hoàn toàn bằng **Swift native**, tối ưu hóa tối đa cho macOS, phản hồi tức thì
- 🎯 **Tương thích hoàn hảo**: Chạy mượt mà trên tất cả phiên bản macOS mới nhất (12.0+)
- 🔧 **Ổn định & Cập nhật thường xuyên**: Code base hiện đại, được test kỹ lưỡng với auto-update
- 🛠️ **Debug Window**: Cửa sổ debug chuyên nghiệp giúp developer theo dõi real-time hoạt động của bộ gõ
- 🚀 **Tính năng thông minh**: Smart Switch, Macro, Quick Typing, kiểm tra chính tả, từ điển cá nhân
- 🌐 **Dịch thuật nhanh**: Dịch văn bản với phím tắt, hỗ trợ 30+ ngôn ngữ qua nhiều nhà cung cấp (Google, Tencent, Volcano)
- 🎨 **Giao diện hiện đại**: Thiết kế theo phong cách Apple với SwiftUI
- 🔒 **Bảo mật**: Chạy local, không thu thập dữ liệu người dùng
- ⌨️ **Dual Mode**: Hỗ trợ cả CGEvent và Input Method Kit (XKeyIM)

---

## 🎯 Tính năng chính

<div align="center">
  <img src="xkey-panel.png" alt="XKey Settings Panel" width="800">
</div>

### 1. Hai chế độ hoạt động

| Chế độ | Mô tả | Ưu điểm |
|--------|-------|---------|
| **CGEvent** (Mặc định) | Sử dụng CGEvent injection | Không cần cấu hình, hoạt động ngay với mọi app |
| **XKeyIM** (Thử nghiệm) | Sử dụng Input Method Kit | Mượt mà hơn trong Terminal, Spotlight, Address Bar |

### 2. Hỗ trợ đa kiểu gõ

| Kiểu gõ | Mô tả | Ví dụ |
|---------|-------|-------|
| **Telex** | Kiểu gõ phổ biến nhất | `tieengs` → tiếng |
| **VNI** | Kiểu gõ truyền thống với số | `tie61ng` → tiếng |
| **Simple Telex 1** | Telex đơn giản (w không biến đổi) | `tieengs` → tiếng |
| **Simple Telex 2** | Telex + w cho ư/ơ | `tuaw` → tưa |

### 3. Bảng mã đa dạng

- **Unicode (UTF-8)** - Khuyến nghị, mặc định
- **TCVN3 (ABC)** - Tương thích với phần mềm cũ
- **VNI Windows** - Tương thích với font VNI

### 4. Gõ nhanh (Quick Typing)

Tăng tốc độ gõ với các phím tắt thông minh:

| Tính năng | Chức năng |
|-----------|-----------|
| **Quick Telex** | `cc`→`ch`, `gg`→`gi`, `kk`→`kh`, `nn`→`ng`, `pp`→`ph`, `qq`→`qu`, `tt`→`th` |
| **Quick Start Consonant** | `f`→`ph`, `j`→`gi`, `w`→`qu` (đầu từ) |
| **Quick End Consonant** | `g`→`ng`, `h`→`nh`, `k`→`ch` (cuối từ) |

### 5. Macro (Text Shortcuts)

Tự động thay thế văn bản với Macro:
- ✅ Tạo các từ viết tắt tùy chỉnh
- ✅ Hỗ trợ import/export danh sách macro (.txt)
- ✅ Tùy chọn tự động viết hoa macro
- ✅ Tùy chọn thêm khoảng trắng sau macro
- ✅ Sử dụng macro trong cả chế độ tiếng Anh

### 6. Công cụ chuyển đổi văn bản

Truy cập nhanh với phím tắt tùy chỉnh:

| Tính năng | Mô tả |
|-----------|-------|
| **Chữ hoa/thường** | Viết hoa tất cả, viết thường tất cả, viết hoa chữ đầu, viết hoa mỗi từ |
| **Bảng mã** | Chuyển đổi giữa Unicode ↔ TCVN3 ↔ VNI |
| **Xóa dấu** | Chuyển từ có dấu sang không dấu |

### 7. Kiểm tra chính tả (Thử nghiệm)

- 📖 Sử dụng từ điển tiếng Việt (~200KB, GPL license)
- 🔄 Tự động khôi phục khi gõ sai chính tả
- ✏️ Hỗ trợ cả dấu mới (xoà) và dấu cũ (xóa)
- 👤 **Từ điển cá nhân**: Thêm các từ riêng để bỏ qua kiểm tra
- 📥 Import/Export từ điển cá nhân

### 8. Smart Switch

- 🧠 Nhớ ngôn ngữ theo từng ứng dụng
- 🔍 Hỗ trợ phát hiện Spotlight/Raycast/Alfred overlay apps
- 🔄 Tự động chuyển ngôn ngữ khi chuyển app

### 9. Dịch thuật nhanh (Translation)

Dịch văn bản ngay trong mọi ứng dụng với phím tắt tùy chỉnh. XKey cung cấp **hai hướng dịch**, mỗi hướng có phím tắt riêng và các tùy chọn **hoạt động độc lập**:

#### 🌐 Dịch sang ngôn ngữ đích

Dịch văn bản đang chọn (hoặc toàn bộ nội dung) **từ ngôn ngữ nguồn sang ngôn ngữ đích**.

**Cách sử dụng:**
1. Chọn (bôi đen) text cần dịch trong bất kỳ ứng dụng nào
2. Nhấn phím tắt (mặc định: `⌘ + ⇧ + T`)
3. Kết quả được xử lý theo các tùy chọn đã bật

> 💡 Nếu không chọn text, XKey sẽ dịch toàn bộ nội dung trong ô nhập liệu.

**Tùy chọn (bật/tắt độc lập):**

| Tùy chọn | Mặc định | Mô tả |
|-----------|----------|-------|
| **Thay thế text gốc** | ✅ Bật | Thay thế text đang chọn bằng bản dịch |
| **Copy vào clipboard** | ✅ Bật | Copy bản dịch vào clipboard để dán ở nơi khác |
| **Hiển thị popup** | ❌ Tắt | Hiển thị bản dịch trong overlay popup |
| **Tự ẩn popup** | 4 giây | Thời gian tự ẩn (0 = không tự ẩn, chỉ hiện khi bật popup) |

#### 🔄 Dịch sang ngôn ngữ nguồn

Dịch ngược văn bản **từ ngôn ngữ đích sang ngôn ngữ nguồn** — hữu ích để xem nghĩa hoặc kiểm tra bản dịch.

**Cách sử dụng:**
1. Chọn text cần dịch ngược
2. Nhấn phím tắt (cần cấu hình trong Settings)
3. Kết quả được xử lý theo các tùy chọn đã bật

**Tùy chọn (bật/tắt độc lập):**

| Tùy chọn | Mặc định | Mô tả |
|-----------|----------|-------|
| **Thay thế text gốc** | ❌ Tắt | Thay thế text đang chọn bằng bản dịch ngược |
| **Copy vào clipboard** | ❌ Tắt | Copy bản dịch vào clipboard |
| **Hiển thị popup** | ✅ Bật | Hiển thị bản dịch trong overlay popup |
| **Tự ẩn popup** | 4 giây | Thời gian tự ẩn (0 = không tự ẩn, chỉ hiện khi bật popup) |

> 💡 Mỗi tùy chọn hoạt động **hoàn toàn độc lập** — bạn có thể bật đồng thời thay thế text, copy clipboard, và hiển thị popup nếu muốn.

#### Tính năng overlay popup

- 🪟 Glassmorphism UI — nền mờ, tự động phù hợp Light/Dark mode
- 📋 Nút copy nhanh bản dịch vào clipboard
- 🔤 Nút tăng/giảm cỡ chữ (+/−) để đọc dễ hơn
- ↔️ Kéo header để di chuyển overlay, kéo cạnh để resize
- ⏱️ Thời gian tự ẩn tùy chỉnh riêng cho mỗi hướng dịch
- 📊 Thanh countdown hiển thị thời gian còn lại

#### Ngôn ngữ hỗ trợ

| Tính năng | Mô tả |
|-----------|-------|
| **Tự động nhận diện** | Nhận diện ngôn ngữ nguồn tự động |
| **Đa ngôn ngữ** | Hỗ trợ 30+ ngôn ngữ phổ biến (Anh, Việt, Trung, Nhật, Hàn, Pháp, Đức...) |
| **Ngôn ngữ tùy chỉnh** | Nhập mã ISO 639-1 để sử dụng bất kỳ ngôn ngữ nào |

#### Nhà cung cấp dịch thuật

| Nhà cung cấp | Mô tả |
|--------------|-------|
| **Google Translate** | Miễn phí, hỗ trợ đa ngôn ngữ, chất lượng tốt |
| **Tencent Transmart** | Miễn phí, tối ưu cho các ngôn ngữ Châu Á |
| **Volcano Engine** | Miễn phí, chất lượng cao cho tiếng Trung ↔ Việt |

> 💡 Bạn có thể bật/tắt từng nhà cung cấp và thay đổi thứ tự ưu tiên trong **Thiết lập → Dịch thuật**.

#### Tính năng nâng cao

- ✅ **Fallback tự động**: Nếu nhà cung cấp ưu tiên lỗi hoặc trả về kết quả rỗng, tự động thử nhà cung cấp tiếp theo
- ✅ **Thông báo lỗi rõ ràng**: Thông báo cụ thể bằng tiếng Việt cho từng loại lỗi (mạng, giới hạn tần suất, kết quả không hợp lệ...)
- ✅ **Giữ nguyên định dạng chữ**: Hoa/thường (ALL CAPS, Capitalize, lowercase)
- ✅ **Overlay loading**: Hiển thị trạng thái đang dịch tại vị trí con trỏ
- ✅ **Lấy văn bản thông minh**: Accessibility API với fallback sang Clipboard

**Cấu hình:** Settings → Dịch thuật

### 10. Quản lý Input Sources

- 📋 Xem danh sách tất cả Input Sources
- ✅ Bật/tắt XKey cho từng Input Source cụ thể
- 🔀 Phím tắt chuyển nhanh sang XKey/ABC
- 🔔 Tự động phát hiện Input Sources tiếng Việt khác

### 11. Hiệu chỉnh XKey Engine theo ứng dụng (Window Title Rules)

Phát hiện ngữ cảnh đặc biệt dựa trên tiêu đề cửa sổ, giải quyết vấn đề gõ tiếng Việt trong các web apps:

| Web App | Xử lý đặc biệt |
|---------|----------------|
| Google Docs/Sheets/Slides | Tắt marked text, slow injection |
| Notion, Figma | Điều chỉnh delay phù hợp |
| Và nhiều apps khác... | Tùy chỉnh theo nhu cầu |

**Tính năng Window Title Rules:**
- ✅ Tự động nhận diện web apps trong bất kỳ browser nào
- ✅ Áp dụng xử lý phù hợp cho từng context
- ✅ Ghi đè injection method, delay, text sending method
- ✅ Tự động chuyển Input Source khi rule match
- ✅ Hỗ trợ Regex matching

**Cấu hình:** Settings → Nâng cao → Hiệu chỉnh XKey Engine theo ứng dụng

#### Hướng dẫn thêm quy tắc mới

1. Mở **Settings** → **Nâng cao** → **Hiệu chỉnh XKey Engine theo ứng dụng**
2. Nhấn **"Thêm quy tắc"**
3. Điền thông tin:
   - **Tên**: Tên hiển thị cho quy tắc
   - **Bundle ID**: `*` để áp dụng cho tất cả apps, hoặc chọn app cụ thể
   - **Title Pattern**: Từ khóa để nhận diện trong tiêu đề cửa sổ
   - **Match mode**: Chứa, Bắt đầu bằng, Kết thúc bằng, Khớp chính xác, hoặc Regex
4. Cấu hình behavior (tùy chọn):
   - **Ghi đè Marked Text**: Bật/tắt gạch chân khi gõ
   - **Ghi đè Injection Method**: Fast, Slow, Selection, Autocomplete, AX Direct hoặc Passthrough
   - **Tùy chỉnh Injection Delays**: Điều chỉnh delay (µs) cho Backspace, Wait, Text
   - **Phương thức gửi text**: Chunked hoặc One-by-One
   - **Chuyển Input Source**: Tự động chuyển sang Input Source cụ thể
5. Nhấn **"Thêm"** để lưu

> **💡 Lưu ý:** Nếu bạn sử dụng Google Docs/Sheets/Slides với ngôn ngữ **tiếng Việt**, tiêu đề cửa sổ sẽ hiển thị là **"Google Tài liệu"**, **"Google Trang tính"**, **"Google Trang trình bày"**. Bạn cần tạo thêm quy tắc với Title Pattern tương ứng.

### 12. Tính năng khác

| Tính năng | Mô tả |
|-----------|-------|
| **Hoàn tác gõ (Undo)** | Nhấn phím tắt để hoàn tác việc bỏ dấu (`tiếng` → `tieesng`) |
| **Free Mark** | Đặt dấu tự do ở bất kỳ vị trí nào trong từ |
| **Kiểu gõ hiện đại** | Hỗ trợ cả dấu mới (oà/uý) và dấu cũ (òa/úy) |
| **Tạm tắt thông minh** | Ctrl tắt chính tả, Option tắt bộ gõ tạm thời |
| **Thanh công cụ nổi** | Điều khiển nhanh XKey tại vị trí con trỏ |
| **Loại trừ ứng dụng** | Tắt XKey cho các app cụ thể |
| **Auto-update** | Tự động cập nhật phiên bản mới với Sparkle |
| **Backup/Restore** | Sao lưu và khôi phục toàn bộ cài đặt |
| **Debug Window** | Theo dõi real-time hoạt động của bộ gõ |

---

## 📥 Cài đặt

### Yêu cầu hệ thống

- macOS 12.0 (Monterey) trở lên
- Quyền truy cập Accessibility

### Cài đặt qua Homebrew (Khuyến nghị)

XKey đã có mặt trên [Homebrew Cask](https://formulae.brew.sh/cask/xkey). Chỉ cần một lệnh duy nhất:

```bash
brew install --cask xkey
```

Homebrew sẽ tự động tải, cài đặt XKey vào thư mục Applications, và quản lý cập nhật cho bạn.

**Cập nhật lên phiên bản mới:**

```bash
brew upgrade --cask xkey
```

**Gỡ cài đặt:**

```bash
brew uninstall --cask xkey
```

> **Lưu ý:** Sau khi cài đặt, bạn vẫn cần cấp quyền Accessibility cho XKey:
> **System Settings** → **Privacy & Security** → **Accessibility** → Bật quyền cho XKey

### Cài đặt từ Release

1. Tải file `XKey.dmg` mới nhất từ [Releases](https://github.com/xmannv/xkey/releases)
2. Mở DMG và kéo XKey.app vào thư mục Applications
3. Mở XKey từ Applications
4. Cấp quyền Accessibility:
   - **System Settings** → **Privacy & Security** → **Accessibility**
   - Bật quyền cho XKey

### Build từ mã nguồn

```bash
# Clone repository
git clone https://github.com/xmannv/xkey.git
cd xkey/XKey

# Build release
./build_release.sh

# Output: Release/XKey.app, Release/XKey.dmg
```

---

## ⌨️ XKeyIM - Input Method Kit Mode

XKeyIM là Input Method sử dụng IMKit của Apple, cung cấp trải nghiệm gõ mượt mà hơn trong các ứng dụng có độ trễ phản hồi thấp hoặc có cơ chế autocomplete như Terminal, Spotlight, Address Bar.

### Bundle Identifiers

| Component | Bundle ID |
|-----------|-----------|
| XKey (main app) | `com.codetay.XKey` |
| XKeyIM (input method) | `com.codetay.inputmethod.XKey` |
| App Group | `group.com.codetay.xkey` |

### Tính năng XKeyIM

| Tính năng | Mô tả |
|-----------|-------|
| **Marked Text Mode** | Hiển thị gạch chân khi gõ - ổn định và tương thích tốt (khuyến nghị) |
| **Direct Mode** | Không gạch chân - có thể gặp lỗi trong một số app |
| **Phím hoàn tác** | ESC để hoàn tác (ví dụ: "thử" → "thur") |
| **Phím tắt chuyển nhanh** | Tuỳ chỉnh phím tắt toggle giữa XKey và ABC |

### Cài đặt XKeyIM

1. Mở XKey Settings → **Input Sources**
2. Click **"Cài đặt XKeyIM..."**
3. Copy `XKeyIM.app` vào `~/Library/Input Methods/`
4. Logout/Login lại
5. Mở **System Settings** → **Keyboard** → **Input Sources**
6. Click **"+"** và thêm **"XKey Vietnamese"**

### Quyền truy cập cho XKeyIM

XKeyIM cần quyền **Accessibility** để xử lý một số tổ hợp phím đặc biệt (như Ctrl+C trong Terminal):

1. Mở **System Settings** → **Privacy & Security** → **Accessibility**
2. Click **"+"** và thêm `XKeyIM.app` từ `~/Library/Input Methods/`
3. Bật quyền cho XKeyIM

> **Lưu ý:** Nếu không cấp quyền Accessibility, XKeyIM vẫn hoạt động bình thường cho việc gõ tiếng Việt. Quyền này chỉ cần thiết để đảm bảo các phím tắt như Ctrl+C hoạt động đúng khi đang có văn bản đang soạn (marked text).

> **Phím hoàn tác:** XKeyIM sử dụng phím ESC làm phím hoàn tác mặc định (không thể tùy chỉnh do hạn chế của Input Method Kit). Bấm ESC khi đang gõ từ có dấu tiếng Việt sẽ hoàn tác về dạng không dấu.

### Build XKeyIM từ mã nguồn

Xem hướng dẫn chi tiết tại [XKeyIM/README.md](XKeyIM/README.md)

---

## 🛠️ Phát triển

### Cấu trúc dự án

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

### Build Script

Script `build_release.sh` hỗ trợ nhiều options để customize build process:

```bash
# Build với code signing + DMG (mặc định)
./build_release.sh

# Build không code signing
ENABLE_CODESIGN=false ./build_release.sh

# Build không XKeyIM
ENABLE_XKEYIM=false ./build_release.sh

# Full release: Notarization + Auto GitHub Release
ENABLE_NOTARIZE=true ./build_release.sh

# Tạo GitHub Release tự động
ENABLE_GITHUB_RELEASE=true ./build_release.sh
```

#### Tự động tạo GitHub Release

Script hỗ trợ tự động tạo GitHub Release khi build hoàn thành:

**Yêu cầu:**
- GitHub CLI (`gh`) đã cài đặt: `brew install gh`
- Đã đăng nhập: `gh auth login`

**Tính năng:**
- ✅ Tự động đọc version từ `Info.plist`
- ✅ Tạo tag `v{version}` và release trên GitHub
- ✅ Upload `XKey.dmg` và `signature.txt` (cho Sparkle auto-update)
- ✅ Tự động generate release notes từ git commits
- ✅ Trigger GitHub Actions để generate appcast

**Custom Release Notes:**
Tạo file `.release_notes.md` trong thư mục gốc để sử dụng release notes tùy chỉnh thay vì auto-generate.

**Sử dụng:**
```bash
# Cách 1: Enable thủ công
ENABLE_GITHUB_RELEASE=true ./build_release.sh

# Cách 2: Tự động khi notarize (full release)
ENABLE_NOTARIZE=true ./build_release.sh
# → Tự động enable GitHub Release
```

### Công nghệ sử dụng

| Công nghệ | Mục đích |
|-----------|----------|
| **Swift Native** | 100% Swift code, tối ưu cho macOS |
| **SwiftUI** | Giao diện người dùng hiện đại |
| **Input Method Kit** | Native input method support (XKeyIM) |
| **Core Graphics Events** | Keyboard event handling và injection |
| **Accessibility API** | Focus detection với AXObserver |
| **Sparkle** | Auto-update framework |

### Settings Persistence (Lưu trữ cài đặt)

XKey sử dụng **Dual Storage System** để đảm bảo settings không bao giờ bị mất:

1. **Primary Storage**: App Group UserDefaults (`group.com.codetay.inputmethod.XKey`)
   - Chia sẻ settings giữa XKey và XKeyIM
   - Cho phép cả 2 apps sync cài đặt real-time

2. **Backup Storage**: UserDefaults.standard
   - Tự động backup mỗi khi settings thay đổi
   - Tự động restore nếu App Group container bị reset

**Lợi ích**:
- ✅ Settings được giữ nguyên khi update version mới
- ✅ Tự động migrate từ phiên bản cũ
- ✅ Backup an toàn, không lo mất cài đặt
- ✅ Đồng bộ giữa XKey và XKeyIM

---

## 🙏 Cảm ơn

XKey được phát triển dựa trên:
- **OpenKey**: Bộ gõ tiếng Việt mã nguồn mở
- **Unikey**: Bộ gõ tiếng Việt phổ biến

---

## 📄 Giấy phép

Dự án được phát hành dưới giấy phép MIT. Xem file [LICENSE](LICENSE) để biết thêm chi tiết.

---

## 📧 Liên hệ

- **Issues**: [GitHub Issues](https://github.com/xmannv/xkey/issues)
- **Discussions**: [GitHub Discussions](https://github.com/xmannv/xkey/discussions)

---

<div align="center">
  Made with ❤️ & ☕ by XKey Contributors
  
  ⭐ Nếu bạn thấy hữu ích, hãy cho dự án một star!
</div>
