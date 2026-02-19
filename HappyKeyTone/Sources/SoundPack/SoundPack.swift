import Foundation

/// サウンドパックのメタデータ
struct SoundPackInfo: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let author: String
    let version: String
    let description: String

    /// キーカテゴリごとの音声ファイルマッピング
    let keyDown: [String: [String]]  // category -> [filename]
    let keyUp: [String: [String]]    // category -> [filename]
}

/// 読み込み済みサウンドパック
struct SoundPack: Sendable {
    let info: SoundPackInfo
    let baseURL: URL

    /// 指定カテゴリ・イベント種別の音声ファイルURLを返す
    func audioURLs(for category: KeyCategory, eventType: KeyEventType) -> [URL] {
        let mapping = eventType == .keyDown ? info.keyDown : info.keyUp
        let categoryKey = category.rawValue

        // 指定カテゴリの音声がなければ letter にフォールバック
        guard let filenames = mapping[categoryKey] ?? mapping[KeyCategory.letter.rawValue] else {
            return []
        }

        return filenames.map { baseURL.appendingPathComponent($0) }
    }
}
