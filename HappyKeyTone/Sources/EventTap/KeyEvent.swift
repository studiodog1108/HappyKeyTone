import CoreGraphics

/// キーイベントの種類
enum KeyEventType: Sendable {
    case keyDown
    case keyUp
}

/// キーのカテゴリ（サウンドパック内の音声グループに対応）
enum KeyCategory: String, Sendable, CaseIterable {
    case letter       // 文字キー (A-Z, 0-9, 記号)
    case space        // スペースバー
    case enter        // Enter/Return
    case delete       // Backspace/Delete
    case modifier     // Shift, Control, Option, Command
    case arrow        // 矢印キー
    case function     // Fn, F1-F12
    case tab          // Tab
    case escape       // Escape

    static func from(keyCode: Int64) -> KeyCategory {
        switch keyCode {
        case 49:
            return .space
        case 36, 76:
            return .enter
        case 51, 117:
            return .delete
        case 48:
            return .tab
        case 53:
            return .escape
        case 123, 124, 125, 126:
            return .arrow
        case 56, 57, 58, 59, 54, 55, 60, 61, 62, 63:
            // Shift(56,60), Control(59,62), Option(58,61), Command(55,54), Fn(63), CapsLock(57)
            return .modifier
        case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111:
            // F1-F12
            return .function
        default:
            return .letter
        }
    }
}

/// グローバルキーイベント
struct KeyEvent: Sendable {
    let type: KeyEventType
    let keyCode: Int64
    let category: KeyCategory
    let isRepeat: Bool

    init(type: KeyEventType, keyCode: Int64, isRepeat: Bool = false) {
        self.type = type
        self.keyCode = keyCode
        self.category = KeyCategory.from(keyCode: keyCode)
        self.isRepeat = isRepeat
    }
}
