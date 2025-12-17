# XKey

<div align="center">
  <img src="xkey.png" alt="XKey Logo" width="128" height="128">
  
  **Bộ gõ tiếng Việt hiện đại cho macOS**
  
  [![Version](https://img.shields.io/badge/version-1.0.5-blue.svg)](https://github.com/xmannv/xkey/releases)
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
- 🎯 **Tương thích hoàn hảo**: Chạy mượt mà trên tất cả phiên bản macOS mới nhất
- 🔧 **Ổn định & Không bug**: Code base hiện đại, được test kỹ lưỡng, cập nhật thường xuyên
- 🛠️ **Debug Window**: Cửa sổ debug chuyên nghiệp giúp developer theo dõi real-time hoạt động của bộ gõ, phát hiện và fix lỗi nhanh chóng
- 🚀 **Tính năng thông minh**: Smart Switch, Macro, Quick Typing, kiểm tra chính tả
- 🎨 **Giao diện hiện đại**: Thiết kế theo phong cách Apple với SwiftUI
- 🔒 **Bảo mật**: Chạy local, không thu thập dữ liệu người dùng

---

## 🎯 Tính năng chính

<div align="center">
  <img src="xkey-panel.png" alt="XKey Settings Panel" width="800">
</div>

### 1. Hỗ trợ đa kiểu gõ

- **Telex**: Kiểu gõ phổ biến nhất (ví dụ: `tiếng` → tiếng)
- **VNI**: Kiểu gõ truyền thống (ví dụ: `tie61ng` → tiếng)
- **VIQR**: Kiểu gõ chuẩn quốc tế (ví dụ: `tie^'ng` → tiếng)

### 2. Bảng mã đa dạng

- Unicode (UTF-8) - Khuyến nghị
- TCVN3 (ABC)
- VNI Windows
- Unicode Compound

### 3. Gõ nhanh (Quick Typing)

Tăng tốc độ gõ với các phím tắt thông minh:

#### Quick Telex
- `cc` → `ch` (ví dụ: `ccao` → chao)
- `gg` → `gi` (ví dụ: `ggio` → gio)
- `kk` → `kh` (ví dụ: `kkong` → khong)
- `nn` → `ng` (ví dụ: `nnon` → ngon)
- `pp` → `ph` (ví dụ: `ppo` → pho)
- `qq` → `qu` (ví dụ: `qqan` → quan)
- `tt` → `th` (ví dụ: `tthe` → the)

#### Quick Consonant - Đầu từ
- `f` → `ph` (ví dụ: `fo` → pho)
- `j` → `gi` (ví dụ: `jo` → gio)
- `w` → `qu` (ví dụ: `wan` → quan)

#### Quick Consonant - Cuối từ
- `g` → `ng` (ví dụ: `mog` → mong)
- `h` → `nh` (ví dụ: `mih` → minh)
- `k` → `ch` (ví dụ: `sak` → sach)

### 4. Macro (Text Shortcuts)

Tự động thay thế văn bản với Macro:
- Tạo các từ viết tắt tùy chỉnh
- Hỗ trợ import/export danh sách macro
- Tự động viết hoa macro
- Sử dụng macro trong cả chế độ tiếng Việt và tiếng Anh

**Ví dụ:**
- `btw` → `by the way`
- `addr` → `123 Đường ABC, Quận XYZ`
- `email` → `example@email.com`

### 5. Công cụ chuyển đổi văn bản

Chuyển đổi văn bản nhanh chóng:
- **Chữ hoa/thường**: Viết hoa tất cả, viết thường tất cả, viết hoa chữ đầu, viết hoa mỗi từ
- **Bảng mã**: Chuyển đổi giữa Unicode, TCVN3, VNI
- **Xóa dấu**: Chuyển từ có dấu sang không dấu

### 6. Tính năng nâng cao

#### Kiểm tra chính tả
- Tự động phát hiện và sửa lỗi chính tả
- Khôi phục nếu sai chính tả
- Sửa lỗi tự động hoàn thành

#### Smart Switch
- Tự động nhớ ngôn ngữ theo từng ứng dụng
- Chuyển đổi thông minh giữa tiếng Việt và tiếng Anh

#### Tạm tắt thông minh
- Giữ **Ctrl** để tạm tắt kiểm tra chính tả
- Giữ **Option (⌥)** để tạm tắt bộ gõ tiếng Việt

#### Tùy chọn khác
- Kiểu gõ hiện đại (oà/uý)
- Đặt dấu tự do (Free Mark)
- Tự động viết hoa chữ đầu câu
- Cho phép phụ âm Z, F, W, J

### 7. Debug Window (Dành cho Developer)

Cửa sổ debug chuyên nghiệp giúp theo dõi hoạt động của bộ gõ:
- 📊 **Real-time monitoring**: Xem trực tiếp các sự kiện bàn phím
- 🔍 **Input tracking**: Theo dõi quá trình xử lý từng ký tự
- 🧪 **Engine state**: Kiểm tra trạng thái của Vietnamese engine
- 🐛 **Bug detection**: Phát hiện và debug lỗi nhanh chóng
- 📝 **Event logging**: Ghi lại toàn bộ sự kiện để phân tích

Bật Debug Window trong **Cài đặt** → **Nâng cao** → **Bật chế độ Debug**

### 8. Giao diện & Trải nghiệm

- Biểu tượng trên thanh trạng thái (Menu Bar)
  - Chọn giữa chữ **X** hoặc chữ **V** làm biểu tượng
  - Tự động đổi màu khi bật/tắt tiếng Việt
- Phím tắt tùy chỉnh để bật/tắt tiếng Việt
- Khởi động cùng hệ thống
- Kiểm tra cập nhật tự động

---

## 📥 Cài đặt

### Yêu cầu hệ thống

- macOS 12.0 (Monterey) trở lên
- Quyền truy cập Accessibility (sẽ được yêu cầu khi chạy lần đầu)

### Cài đặt từ Release

1. Tải file `Xkey.app.zip` mới nhất từ [Releases](https://github.com/xmannv/xkey/releases)
2. Giải nén và kéo XKey.app vào thư mục Applications
3. Mở XKey từ Applications
4. Cấp quyền Accessibility khi được yêu cầu:
   - Mở **System Settings** → **Privacy & Security** → **Accessibility**
   - Bật quyền cho XKey

### Cài đặt cho nhiều người dùng (Multi-User)

Nếu máy Mac có nhiều user accounts và bạn gặp lỗi **"You can't open the application because someone else is using it"**, hãy cài đặt theo cách sau:

#### Cách 1: Mỗi user cài riêng (Khuyến nghị)

Mỗi user cài XKey vào thư mục Applications riêng của mình:

```bash
# Tạo thư mục Applications cho user (nếu chưa có)
mkdir -p ~/Applications

# Di chuyển XKey.app vào thư mục user
mv /Applications/XKey.app ~/Applications/
```

Hoặc kéo thả `XKey.app` vào `~/Applications/` (thư mục Applications trong Home folder).

#### Cách 2: Mỗi user có bản copy riêng

Nếu muốn giữ XKey trong `/Applications` chung:

1. User A: Sử dụng `/Applications/XKey.app`
2. User B: Copy `XKey.app` vào `~/Applications/XKey.app`

#### Lưu ý quan trọng

- ✅ Mỗi user cần **cấp quyền Accessibility riêng** trong System Settings
- ✅ Preferences (cài đặt) của mỗi user được lưu **độc lập**
- ✅ Macro và Smart Switch data của mỗi user cũng **riêng biệt**
- ✅ Nếu muốn XKey tự khởi động, mỗi user cần thêm vào **Login Items** riêng

### Build từ mã nguồn

```bash
# Clone repository
git clone https://github.com/xmannv/xkey.git
cd xkey/XKey

# Mở project với Xcode
open XKey.xcodeproj

# Hoặc build bằng script
./build_release.sh
```

---

## 🚀 Sử dụng

### Bật/Tắt bộ gõ

- Sử dụng phím tắt (mặc định: có thể tùy chỉnh trong Settings)
- Click vào biểu tượng XKey trên Menu Bar

### Cấu hình

1. Click vào biểu tượng XKey trên Menu Bar
2. Chọn **Cài đặt** (Settings)
3. Tùy chỉnh theo nhu cầu:
   - **Cơ bản**: Kiểu gõ, bảng mã, phím tắt
   - **Gõ nhanh**: Bật/tắt Quick Typing
   - **Nâng cao**: Chính tả, Smart Switch, tạm tắt
   - **Macro**: Quản lý text shortcuts
   - **Chuyển đổi**: Công cụ chuyển đổi văn bản
   - **Giao diện**: Tùy chỉnh hiển thị
   - **Giới thiệu**: Thông tin phiên bản, kiểm tra cập nhật

---

## 🛠️ Phát triển

### Cấu trúc dự án

```
XKey/
├── XKey/
│   ├── App/              # Entry point
│   ├── Core/             # Core engine
│   │   ├── Engine/       # Vietnamese input engine
│   │   └── Models/       # Data models
│   ├── EventHandling/    # Keyboard event handling
│   ├── UI/               # SwiftUI views
│   └── Utilities/        # Helper utilities
├── XKeyTests/            # Unit tests
└── Release/              # Build output
```

### Công nghệ sử dụng

- **Swift Native**: 100% Swift code, tối ưu hiệu suất tối đa cho macOS
- **SwiftUI**: Giao diện người dùng hiện đại
- **Combine**: Reactive programming
- **Core Graphics**: Event handling
- **Accessibility API**: Keyboard monitoring

### Tại sao Swift Native?

XKey được viết hoàn toàn bằng Swift native thay vì Objective-C hay các ngôn ngữ khác vì:
- ⚡ **Hiệu suất cao hơn**: Swift được tối ưu hóa cho Apple Silicon và Intel
- 🎯 **Memory safety**: Quản lý bộ nhớ tốt hơn, ít crash hơn
- 🔧 **Modern syntax**: Code dễ đọc, dễ maintain, dễ mở rộng
- 🚀 **Future-proof**: Được Apple hỗ trợ và phát triển tích cực

### Đóng góp

Chúng tôi hoan nghênh mọi đóng góp! Vui lòng:

1. Fork repository
2. Tạo branch mới (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Mở Pull Request

---

## 🙏 Cảm ơn

XKey được phát triển dựa trên:
- **OpenKey**: Bộ gõ tiếng Việt mã nguồn mở
- **Unikey**: Bộ gõ tiếng Việt phổ biến

Cảm ơn cộng đồng đã đóng góp và hỗ trợ!

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