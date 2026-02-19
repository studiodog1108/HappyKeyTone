import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.happykeytone.app", category: "Audio")

enum AudioPlaybackResult: Sendable {
    case played
    case skippedRepeat
    case noBuffer
    case engineError(String)
}

/// 低レイテンシ音声再生エンジン
///
/// AVAudioPlayerNodeのプール方式で同時発音に対応。
@MainActor
final class TypingAudioEngine {
    var volume: Float = 0.8
    var pitchVariation: Float = 0.05

    private let engine = AVAudioEngine()
    private var playerNodes: [AVAudioPlayerNode] = []
    private var mixer: AVAudioMixerNode { engine.mainMixerNode }
    private var currentNodeIndex = 0
    private let poolSize = 12

    /// 全バッファの共通フォーマット（エンジンの出力フォーマットに統一）
    private var standardFormat: AVAudioFormat!

    /// キーカテゴリ x イベント種別 -> バッファ配列
    private var soundBuffers: [String: [AVAudioPCMBuffer]] = [:]

    /// エラー状態（UIに伝播用）
    private(set) var lastError: String?
    private(set) var loadedBufferCount = 0
    private(set) var expectedBufferCount = 0

    var isEngineRunning: Bool { engine.isRunning }

    init() {
        setupEngine()
    }

    private func setupEngine() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        standardFormat = format
        logger.info("Audio engine standard format: \(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat.rawValue)")

        for _ in 0..<poolSize {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: mixer, format: format)
            playerNodes.append(node)
        }

        do {
            try engine.start()
            lastError = nil
        } catch {
            lastError = "Audio engine failed to start: \(error.localizedDescription)"
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
        }
    }

    func loadSoundPack(_ pack: SoundPack) {
        engine.stop()
        soundBuffers.removeAll()

        var totalLoaded = 0
        var totalExpected = 0

        for category in KeyCategory.allCases {
            for eventType in [KeyEventType.keyDown, KeyEventType.keyUp] {
                let key = bufferKey(category: category, eventType: eventType)
                let urls = pack.audioURLs(for: category, eventType: eventType)
                totalExpected += urls.count
                let buffers = urls.compactMap { loadBuffer(from: $0) }
                totalLoaded += buffers.count
                soundBuffers[key] = buffers
                if buffers.count < urls.count {
                    logger.warning("Loaded \(buffers.count)/\(urls.count) audio files for \(key)")
                }
            }
        }

        logger.info("Sound pack '\(pack.info.name)' loaded: \(totalLoaded)/\(totalExpected) buffers")
        loadedBufferCount = totalLoaded
        expectedBufferCount = totalExpected
        if totalLoaded == 0 {
            lastError = "Sound pack '\(pack.info.name)' has no playable audio files."
            logger.error("Sound pack '\(pack.info.name)' has no playable audio files.")
        }

        do {
            try engine.start()
            if totalLoaded > 0 {
                lastError = nil
            }
        } catch {
            lastError = "Audio engine failed to restart: \(error.localizedDescription)"
            logger.error("Failed to restart audio engine after loading sound pack '\(pack.info.name)': \(error.localizedDescription)")
        }
    }

    func play(for event: KeyEvent) -> AudioPlaybackResult {
        if event.isRepeat {
            return .skippedRepeat
        }

        let key = bufferKey(category: event.category, eventType: event.type)
        guard let buffers = soundBuffers[key], !buffers.isEmpty else {
            return .noBuffer
        }

        if let engineError = ensureEngineRunning() {
            return .engineError(engineError)
        }

        guard let buffer = buffers.randomElement() else {
            return .noBuffer
        }
        play(buffer: buffer)
        return .played
    }

    /// キー監視とは独立して音声出力経路を確認するためのプレビュー再生
    func playPreview() -> AudioPlaybackResult {
        if let engineError = ensureEngineRunning() {
            return .engineError(engineError)
        }

        let previewKeys = [
            bufferKey(category: .letter, eventType: .keyDown),
            bufferKey(category: .space, eventType: .keyDown),
            bufferKey(category: .enter, eventType: .keyDown),
            bufferKey(category: .letter, eventType: .keyUp),
        ]

        for key in previewKeys {
            if let buffer = soundBuffers[key]?.randomElement() {
                play(buffer: buffer)
                return .played
            }
        }
        return .noBuffer
    }

    private func play(buffer: AVAudioPCMBuffer) {
        let node = playerNodes[currentNodeIndex]
        currentNodeIndex = (currentNodeIndex + 1) % poolSize

        if node.isPlaying {
            node.stop()
        }

        let volumeJitter = Float.random(in: -0.05...0.05)
        node.volume = max(0, min(1, volume + volumeJitter))

        let pitchJitter = Float.random(in: -pitchVariation...pitchVariation)
        node.rate = 1.0 + pitchJitter

        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    private func loadBuffer(from url: URL) -> AVAudioPCMBuffer? {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            logger.error("Failed to read audio file '\(url.lastPathComponent)': \(error.localizedDescription)")
            return nil
        }

        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)

        // ソースバッファに読み込み
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: frameCount
        ) else {
            logger.error("Failed to create source buffer for '\(url.lastPathComponent)'")
            return nil
        }

        do {
            try file.read(into: sourceBuffer)
        } catch {
            logger.error("Failed to read into buffer for '\(url.lastPathComponent)': \(error.localizedDescription)")
            return nil
        }

        // フォーマットが一致すればそのまま返す
        if sourceFormat.sampleRate == standardFormat.sampleRate
            && sourceFormat.channelCount == standardFormat.channelCount
            && sourceFormat.commonFormat == standardFormat.commonFormat
        {
            return sourceBuffer
        }

        // AVAudioConverterでエンジンの標準フォーマットに変換
        guard let converter = AVAudioConverter(from: sourceFormat, to: standardFormat) else {
            logger.error("Failed to create audio converter for '\(url.lastPathComponent)': \(sourceFormat) -> \(self.standardFormat!)")
            return nil
        }

        let ratio = standardFormat.sampleRate / sourceFormat.sampleRate
        let convertedFrameCount = AVAudioFrameCount(Double(frameCount) * ratio) + 1
        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: standardFormat,
            frameCapacity: convertedFrameCount
        ) else {
            logger.error("Failed to create converted buffer for '\(url.lastPathComponent)'")
            return nil
        }

        var error: NSError?
        let state = ConverterInputState(buffer: sourceBuffer)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if state.consumed {
                outStatus.pointee = .endOfStream
                return nil
            }
            state.consumed = true
            outStatus.pointee = .haveData
            return state.buffer
        }

        converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            logger.error("Audio format conversion failed for '\(url.lastPathComponent)': \(error.localizedDescription)")
            return nil
        }

        let targetRate = standardFormat.sampleRate
        let targetCh = standardFormat.channelCount
        logger.debug("Converted '\(url.lastPathComponent)': \(sourceFormat.sampleRate)Hz/\(sourceFormat.channelCount)ch -> \(targetRate)Hz/\(targetCh)ch (\(convertedBuffer.frameLength) frames)")
        return convertedBuffer
    }

    private func bufferKey(category: KeyCategory, eventType: KeyEventType) -> String {
        let typeStr = eventType == .keyDown ? "down" : "up"
        return "\(category.rawValue)_\(typeStr)"
    }

    private func ensureEngineRunning() -> String? {
        guard !engine.isRunning else { return nil }

        do {
            try engine.start()
            return nil
        } catch {
            let message = "Audio engine failed during playback: \(error.localizedDescription)"
            lastError = message
            logger.error("\(message)")
            return message
        }
    }
}

/// AVAudioConverterInputBlockのSwift 6並行性対応ラッパー
/// コンバーターは同期的にブロックを呼ぶため、@unchecked Sendableは安全
private final class ConverterInputState: @unchecked Sendable {
    var consumed = false
    let buffer: AVAudioPCMBuffer
    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
}
