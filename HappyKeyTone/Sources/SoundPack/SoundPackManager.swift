import Foundation
import Observation

/// サウンドパックの検索・管理
@Observable
@MainActor
final class SoundPackManager {
    private(set) var availablePacks: [SoundPackInfo] = []

    /// インポートされたZIPの最大サイズ（Zip Bomb対策）
    private static let maxUnzippedSize: UInt64 = 50 * 1024 * 1024 // 50MB
    /// 許可する音声ファイル拡張子
    private static let allowedExtensions: Set<String> = ["wav", "caf", "aiff", "aif", "mp3", "m4a", "json", "png", "jpg"]

    init() {
        loadBuiltInPacks()
        loadCustomPacks()
    }

    func soundPack(for id: String) -> SoundPack? {
        guard Self.isValidPackID(id) else { return nil }

        if let builtInURL = builtInPackURL(for: id) {
            return loadPack(from: builtInURL)
        }
        if let customURL = customPackURL(for: id) {
            return loadPack(from: customURL)
        }
        return nil
    }

    /// カスタムサウンドパックをインポート
    func importPack(from sourceURL: URL) throws -> SoundPackInfo {
        let customDir = customPacksDirectory()

        let packDir: URL
        if sourceURL.pathExtension == "zip" || sourceURL.pathExtension == "happykeytone" {
            packDir = try unzipPack(sourceURL, to: customDir)
        } else {
            let destURL = customDir.appendingPathComponent(sourceURL.lastPathComponent)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            packDir = destURL
        }

        // 解凍後のサイズ検証
        try validateDirectorySize(packDir)

        guard let pack = loadPack(from: packDir) else {
            // 無効なパックはクリーンアップ
            try? FileManager.default.removeItem(at: packDir)
            throw SoundPackError.invalidPack
        }

        availablePacks.append(pack.info)
        return pack.info
    }

    /// カスタムサウンドパックを削除
    func deletePack(id: String) throws {
        guard Self.isValidPackID(id) else { throw SoundPackError.invalidPackID }
        guard let url = customPackURL(for: id) else {
            throw SoundPackError.packNotFound
        }
        try FileManager.default.removeItem(at: url)
        availablePacks.removeAll { $0.id == id }
    }

    // MARK: - Validation

    /// パスインジェクション防止: IDに不正な文字が含まれていないか検証
    private static func isValidPackID(_ id: String) -> Bool {
        !id.contains("/") && !id.contains("\\") && !id.contains("..") && !id.isEmpty
    }

    /// 解凍ディレクトリの合計サイズを検証（Zip Bomb対策）
    private func validateDirectorySize(_ url: URL) throws {
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        var totalSize: UInt64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])

            // symlink除外（セキュリティ対策）
            if resourceValues.isSymbolicLink == true {
                throw SoundPackError.symlinksNotAllowed
            }

            // 拡張子ホワイトリスト検証
            if !fileURL.hasDirectoryPath {
                let ext = fileURL.pathExtension.lowercased()
                if !Self.allowedExtensions.contains(ext) {
                    throw SoundPackError.unsupportedFileType(ext)
                }
            }

            totalSize += UInt64(resourceValues.fileSize ?? 0)
            if totalSize > Self.maxUnzippedSize {
                throw SoundPackError.packTooLarge
            }
        }
    }

    // MARK: - Loading

    private func loadBuiltInPacks() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let soundPacksURL = resourceURL.appendingPathComponent("SoundPacks")

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: soundPacksURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for dir in contents where dir.hasDirectoryPath {
            if let pack = loadPack(from: dir) {
                availablePacks.append(pack.info)
            }
        }
    }

    private func loadCustomPacks() {
        let customDir = customPacksDirectory()

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: customDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for dir in contents where dir.hasDirectoryPath {
            if let pack = loadPack(from: dir) {
                availablePacks.append(pack.info)
            }
        }
    }

    private func loadPack(from url: URL) -> SoundPack? {
        let manifestURL = url.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let info = try? JSONDecoder().decode(SoundPackInfo.self, from: data) else {
            return nil
        }
        return SoundPack(info: info, baseURL: url)
    }

    private func builtInPackURL(for id: String) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("SoundPacks/\(id)")
        // 解決パスが期待するディレクトリ内にあることを検証（パストラバーサル防止）
        let resolved = url.standardizedFileURL.path
        let base = resourceURL.appendingPathComponent("SoundPacks").standardizedFileURL.path
        guard resolved.hasPrefix(base) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func customPackURL(for id: String) -> URL? {
        let dir = customPacksDirectory()
        let url = dir.appendingPathComponent(id)
        let resolved = url.standardizedFileURL.path
        let base = dir.standardizedFileURL.path
        guard resolved.hasPrefix(base) else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func customPacksDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("HappyKeyTone/SoundPacks")

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        return dir
    }

    private func unzipPack(_ zipURL: URL, to directory: URL) throws -> URL {
        // 一時ディレクトリに解凍してパス検証後に移動
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer { try? FileManager.default.removeItem(at: tempDir) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", tempDir.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SoundPackError.unzipFailed
        }

        // Zip Slip検証: 全ファイルがtempDir内にあることを確認
        let basePath = tempDir.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            let resolvedPath = fileURL.standardizedFileURL.path
            guard resolvedPath.hasPrefix(basePath) else {
                throw SoundPackError.pathTraversal
            }
        }

        // manifest.jsonを含むディレクトリを探す
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )

        for item in contents where item.hasDirectoryPath {
            let manifest = item.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                let destURL = directory.appendingPathComponent(item.lastPathComponent)
                try FileManager.default.moveItem(at: item, to: destURL)
                return destURL
            }
        }

        throw SoundPackError.invalidPack
    }
}

enum SoundPackError: Error, LocalizedError {
    case invalidPack
    case invalidPackID
    case packNotFound
    case unzipFailed
    case packTooLarge
    case pathTraversal
    case symlinksNotAllowed
    case unsupportedFileType(String)

    var errorDescription: String? {
        switch self {
        case .invalidPack: return "Invalid sound pack format. Missing manifest.json."
        case .invalidPackID: return "Invalid sound pack ID."
        case .packNotFound: return "Sound pack not found."
        case .unzipFailed: return "Failed to unzip sound pack."
        case .packTooLarge: return "Sound pack exceeds 50MB size limit."
        case .pathTraversal: return "Sound pack contains invalid file paths."
        case .symlinksNotAllowed: return "Sound pack cannot contain symbolic links."
        case .unsupportedFileType(let ext): return "Unsupported file type: .\(ext)"
        }
    }
}
