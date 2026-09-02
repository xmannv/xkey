# Input Method Kit (IMKit) Research for XKey

## Tổng quan

Input Method Kit là framework của Apple cho phép tạo custom input methods trên macOS. Đây là cách "chính thống" mà bộ gõ tiếng Việt tích hợp của macOS sử dụng.

## Ưu điểm của IMKit so với CGEvent injection

| Aspect | CGEvent (hiện tại) | IMKit |
|--------|-------------------|-------|
| Composition | Không có buffer | Có marked text buffer |
| Rendering | Backspace + re-inject | Direct text replacement |
| Compatibility | Phụ thuộc app timing | Native support |
| User setup | Không cần | Cần chọn input source |
| Flickering | Có thể xảy ra | Không có |

## Kiến trúc IMKit

```
┌─────────────────────────────────────────────────────────┐
│                    macOS Text System                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────┐ │
│  │ Application  │◄───│ Input Method │◄───│ IMKServer │ │
│  │ (NSText...)  │    │   Client     │    │           │ │
│  └──────────────┘    └──────────────┘    └───────────┘ │
│         ▲                   ▲                   ▲       │
│         │                   │                   │       │
│         └───────────────────┴───────────────────┘       │
│                    NSTextInputClient                     │
└─────────────────────────────────────────────────────────┘
```

## Components cần thiết

### 1. Input Method Bundle (.app)
```
XKeyIM.app/
├── Contents/
│   ├── Info.plist          # Bundle configuration
│   ├── MacOS/
│   │   └── XKeyIM          # Main executable
│   └── Resources/
│       └── XKeyIM.tiff     # Icon
```

### 2. Info.plist keys
```xml
<key>InputMethodConnectionName</key>
<string>com.codetay.inputmethod.XKey_Connection</string>

<key>InputMethodServerControllerClass</key>
<string>XKeyIMController</string>

<key>tsInputMethodCharacterRepertoireKey</key>
<array>
    <string>Latn</string>
    <string>Vitn</string>
</array>

<key>tsInputMethodIconFileKey</key>
<string>XKeyIM</string>
</key>
```

### 3. IMKInputController subclass
```swift
import InputMethodKit

class XKeyIMController: IMKInputController {
    
    private var composingBuffer: String = ""
    private var engine: VNEngine!
    
    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        engine = VNEngine()
    }
    
    // Handle key input
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown else {
            return false
        }
        
        guard let client = sender as? IMKTextInput else {
            return false
        }
        
        let character = event.characters?.first ?? Character(" ")
        let keyCode = event.keyCode
        
        // Process through Vietnamese engine
        let result = engine.processKey(
            character: character,
            keyCode: UInt16(keyCode),
            isUppercase: character.isUppercase
        )
        
        if result.shouldConsume {
            // Update composing buffer
            updateComposingBuffer(result: result, client: client)
            return true
        }
        
        return false
    }
    
    private func updateComposingBuffer(result: VNEngine.ProcessResult, client: IMKTextInput) {
        // Build new text from result
        let newText = result.newCharacters.map { 
            $0.unicode(codeTable: .unicode) 
        }.joined()
        
        // Option 1: With marked text (underline)
        // client.setMarkedText(newText, 
        //                      selectionRange: NSRange(location: newText.count, length: 0),
        //                      replacementRange: NSRange(location: NSNotFound, length: 0))
        
        // Option 2: Direct insert (no underline) - PREFERRED
        client.insertText(newText, 
                         replacementRange: NSRange(location: NSNotFound, length: 0))
    }
    
    // Commit text when word break
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        
        if !composingBuffer.isEmpty {
            client.insertText(composingBuffer, 
                            replacementRange: NSRange(location: NSNotFound, length: 0))
            composingBuffer = ""
        }
    }
    
    // Handle candidate selection (if using candidates window)
    override func candidates(_ sender: Any!) -> [Any]! {
        return nil // No candidates for Vietnamese typing
    }
}
```

### 4. Main entry point
```swift
import Cocoa
import InputMethodKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var server: IMKServer!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create IMK server
        server = IMKServer(
            name: "com.codetay.inputmethod.XKey_Connection",
            bundleIdentifier: Bundle.main.bundleIdentifier!
        )
    }
}
```

## Cách hoạt động không cần gạch chân

Thay vì dùng `setMarkedText` (tạo gạch chân), ta dùng `insertText` với `replacementRange`:

```swift
// Khi user gõ "viet" → "việt"
// Thay vì: backspace 4 lần + inject "việt"
// IMKit: insertText("việt", replacementRange: NSRange(location: cursorPos - 4, length: 4))
```

Điều này cho phép:
1. **Atomic replacement** - Text được thay thế trong 1 operation
2. **No flickering** - Không có khoảng trống giữa xóa và insert
3. **Native support** - App không cần xử lý CGEvent

## Challenges

### 1. Installation
- Input method phải được install vào `/Library/Input Methods/` hoặc `~/Library/Input Methods/`
- User phải enable trong System Settings → Keyboard → Input Sources

### 2. Coexistence với XKey hiện tại
- Có thể chạy song song: XKey (CGEvent) cho apps không hỗ trợ IMKit tốt
- XKeyIM (IMKit) cho apps hỗ trợ tốt (terminals, IDEs)

### 3. Code sharing
- VNEngine có thể được share giữa XKey và XKeyIM
- Chỉ khác phần injection (CGEvent vs IMKit)

## Implementation Plan

### Phase 1: Prototype
1. Tạo XKeyIM.app bundle riêng
2. Implement basic IMKInputController
3. Integrate VNEngine
4. Test với Terminal.app

### Phase 2: Integration
1. Share VNEngine code
2. Add settings sync
3. Auto-detect khi nào dùng IMKit vs CGEvent

### Phase 3: Polish
1. Icon và UI
2. Installation helper
3. Documentation

## References

- [Input Method Kit Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/InputMethodKit/InputMethodKit.html)
- [IMKInputController Class Reference](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller)
- [Creating a Custom Input Method](https://developer.apple.com/library/archive/documentation/TextFonts/Conceptual/CocoaTextArchitecture/TextSystemArchitecture/ArchitectureOverview.html)
