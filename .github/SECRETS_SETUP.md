# 🔐 GitHub Secrets Setup for XKey Build & Release

Để sử dụng GitHub Actions workflow `build-release.yml`, bạn cần thiết lập các secrets sau trong repository settings.

## Required Secrets

### 1. Apple Developer Certificate

#### `APPLE_CERTIFICATE_P12_BASE64`
Certificate Developer ID Application dưới dạng base64.

**Cách tạo:**
```bash
# 1. Export certificate từ Keychain Access (format .p12)
# 2. Convert sang base64:
base64 -i DeveloperIDApplication.p12 | tr -d '\n' > certificate_base64.txt

# 3. Copy nội dung file certificate_base64.txt vào GitHub Secret
```

#### `APPLE_CERTIFICATE_PASSWORD`
Mật khẩu bạn đã đặt khi export certificate .p12.

---

### 2. Apple Notarization Credentials

#### `APPLE_ID`
Apple ID email của bạn (ví dụ: `developer@example.com`)

#### `APPLE_APP_PASSWORD`
App-specific password.

**Cách tạo:**
1. Đăng nhập https://appleid.apple.com/
2. Vào **Sign-In and Security** → **App-Specific Passwords**
3. Click **Generate an app-specific password**
4. Đặt tên: `GitHub Actions` hoặc `XKey CI`
5. Copy password (format: `xxxx-xxxx-xxxx-xxxx`)

#### `APPLE_TEAM_ID`
Team ID của Apple Developer account (10 ký tự).

**Cách tìm:**
- Xem trong certificate name: `Developer ID Application: Your Name (XXXXXXXXXX)`
- Hoặc tại https://developer.apple.com/account → Membership → Team ID

---

### 3. Sparkle Auto-Update Signing

#### `SPARKLE_PRIVATE_KEY`
EdDSA private key cho Sparkle auto-update.

**Lấy từ Keychain (nếu đã có):**
```bash
security find-generic-password -s "https://sparkle-project.org" -a "ed25519" -w
```

**Hoặc copy từ file `.env` trên máy local (nếu đã thiết lập).**

---

## Cách thêm Secrets vào GitHub

1. Vào repository: https://github.com/xmannv/xkey
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Thêm từng secret với name và value tương ứng

---

## Secrets Summary

| Secret Name | Mô tả | Ví dụ |
|-------------|-------|-------|
| `APPLE_CERTIFICATE_P12_BASE64` | Certificate base64 | (rất dài) |
| `APPLE_CERTIFICATE_PASSWORD` | Password của .p12 | `MySecretP@ss` |
| `APPLE_ID` | Apple ID email | `dev@example.com` |
| `APPLE_APP_PASSWORD` | App-specific password | `xxxx-xxxx-xxxx-xxxx` |
| `APPLE_TEAM_ID` | Team ID | `7E6Z9B4F2H` |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key | (rất dài) |

---

## Sử dụng Workflow

Sau khi thiết lập secrets, bạn có thể chạy workflow:

1. Vào **Actions** tab
2. Chọn workflow **Build and Release XKey**
3. Click **Run workflow**
4. Chọn các options:
   - **Enable Apple Notarization**: `true` để notarize (khuyến nghị cho release)
   - **Create GitHub Release**: `true` để tự động tạo release
   - **Release Notes**: (tùy chọn) ghi chú phát hành

---

## Troubleshooting

### Certificate không tìm thấy
- Đảm bảo certificate là **Developer ID Application** (không phải Distribution)
- Kiểm tra certificate chưa hết hạn
- Verify base64 encoding: `echo "$APPLE_CERTIFICATE_P12_BASE64" | base64 --decode | file -`

### Notarization failed
- Kiểm tra app-specific password còn valid
- Verify Team ID chính xác
- Xem log chi tiết từ Apple trong GitHub Actions output

### Sparkle signing failed
- Đảm bảo private key đúng định dạng EdDSA
- Kiểm tra key không có ký tự xuống dòng thừa
