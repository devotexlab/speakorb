import AVFoundation
import Foundation
import SpeakorbCore

/// 录音采集：AVAudioEngine 拿麦克风 Float32，转 16 kHz 单声道 Int16，封成 WAV。
///
/// 约定：
/// - start/stop/cancel 由同一个调用方（SessionController，主线程）串行调用；
/// - 采集回调在音频线程，只用 NSLock 保护共享状态，不做阻塞调用；
/// - 录满上限自动停引擎但**保留已录样本**，下一次 stopRecording() 照常拿到这一段；
/// - 全 0（麦克风被静音/选错设备）判 emptyRecording。
public final class AudioRecorder: AudioCapturing, @unchecked Sendable {
    /// 统一交付格式：16 kHz、单声道、16-bit PCM。
    public static let targetSampleRate = 16_000
    /// 协议/产品上限（见 AppSettings.maxRecordingSeconds 默认值）。
    public static let defaultMaxDurationSeconds = 180

    public let maxDurationSeconds: Int

    private let engine = AVAudioEngine()
    private let lock = NSLock()

    private var samples: [Int16] = []
    private var converter: AVAudioConverter?
    private var isTapInstalled = false
    private var isRecordingFlag = false
    /// 到上限自己停了（不是用户 stop）。下一次 stop 仍返回这一段。
    private var didAutoStop = false
    private var lastFailure: SpeakorbError?
    /// 最近一块缓冲区的音量（0…1），给界面画声球用。
    private var currentLevel: Float = 0

    public init(maxDurationSeconds: Int = AudioRecorder.defaultMaxDurationSeconds) {
        self.maxDurationSeconds = max(1, maxDurationSeconds)
        // 180 s × 16 kHz ≈ 288 万样本；预留到上限的一半，避免长录音反复扩容。
        samples.reserveCapacity(AudioRecorder.targetSampleRate * min(self.maxDurationSeconds, 180) / 2)
    }

    deinit {
        cancelRecording()
    }

    public var isRecording: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRecordingFlag
    }

    /// 这一段是否因为到达时长上限而自动结束（供 UI 提示用，不影响 stop 语义）。
    public var didAutoStopAtLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didAutoStop
    }

    /// 最近一次采集/转换失败的原因（stop 时若没有样本会优先抛它）。
    public var lastError: SpeakorbError? {
        lock.lock()
        defer { lock.unlock() }
        return lastFailure
    }

    /// 当前音量（0…1，已做对数压缩）。只在录音中有意义，界面按 30 Hz 读取即可。
    public var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return isRecordingFlag ? currentLevel : 0
    }

    // MARK: - AudioCapturing

    public func startRecording() throws {
        lock.lock()
        if isRecordingFlag {
            lock.unlock()
            return
        }
        lock.unlock()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            throw SpeakorbError.microphonePermission
        case .authorized, .notDetermined:
            // notDetermined 交给系统在 engine.start() 时弹一次授权；失败在下面统一报 recordingFailed。
            break
        @unknown default:
            break
        }

        // 上一次异常退出可能留下 tap/引擎状态，先清干净。
        tearDownEngine()

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        didAutoStop = false
        lastFailure = nil
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw SpeakorbError.recordingFailed("没有可用的麦克风")
        }
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(AudioRecorder.targetSampleRate),
            channels: 1,
            interleaved: true
        ) else {
            throw SpeakorbError.recordingFailed("无法准备录音格式")
        }
        guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw SpeakorbError.recordingFailed("无法转换录音格式")
        }
        newConverter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue

        lock.lock()
        converter = newConverter
        lock.unlock()

        do {
            input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
                self?.handleTap(buffer)
            }
            lock.lock()
            isTapInstalled = true
            lock.unlock()
            engine.prepare()
            try engine.start()
            lock.lock()
            isRecordingFlag = true
            lock.unlock()
        } catch {
            tearDownEngine()
            lock.lock()
            converter = nil
            lock.unlock()
            throw SpeakorbError.recordingFailed(error.localizedDescription)
        }
    }

    public func stopRecording() async throws -> AudioPayload {
        // NSLock 的 lock/unlock 在 async 上下文里不可用（Swift 6 是错误），统一走同步小函数。
        markRecordingStopped()
        tearDownEngine()
        let (captured, failure) = takeCapturedSamples()

        guard !captured.isEmpty else {
            throw failure ?? SpeakorbError.emptyRecording
        }
        // 全 0：设备静音 / 选错输入 / 采到空设备。不要把静音当「说了话」交给识别。
        var peak: Int = 0
        for sample in captured {
            let magnitude = sample == .min ? 32_768 : abs(Int(sample))
            if magnitude > peak {
                peak = magnitude
                if peak > 0 { break }
            }
        }
        guard peak > 0 else {
            throw SpeakorbError.emptyRecording
        }

        let wav = WAVEncoder.encode(
            samples: captured,
            format: .init(sampleRate: AudioRecorder.targetSampleRate, channels: 1, bitsPerSample: 16)
        )
        let durationMs = WAVEncoder.durationMs(sampleCount: captured.count, sampleRate: AudioRecorder.targetSampleRate)
        return AudioPayload(
            data: wav,
            sampleRate: AudioRecorder.targetSampleRate,
            channels: 1,
            container: .wav,
            durationMs: durationMs
        )
    }

    public func cancelRecording() {
        lock.lock()
        isRecordingFlag = false
        currentLevel = 0
        lock.unlock()
        tearDownEngine()
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        converter = nil
        didAutoStop = false
        lock.unlock()
    }

    // MARK: - 采集回调

    /// 音频线程：把一块 Float32 缓冲区转成 Int16 追加到样本里。
    /// 转换器不是线程安全的，整个回调在锁内完成；单块 4096 帧，转换开销在毫秒级。
    private func handleTap(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }

        guard isRecordingFlag, let converter else { return }
        currentLevel = Self.normalizedLevel(of: buffer)
        let outputFormat = converter.outputFormat
        let ratio = outputFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            lastFailure = .recordingFailed(conversionError.localizedDescription)
            return
        }
        switch status {
        case .haveData, .inputRanDry:
            if let channel = output.int16ChannelData, output.frameLength > 0 {
                let count = Int(output.frameLength)
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: count))
            }
        case .endOfStream, .error:
            return
        @unknown default:
            return
        }

        let limitSamples = AudioRecorder.targetSampleRate * maxDurationSeconds
        guard samples.count >= limitSamples, !didAutoStop else { return }
        didAutoStop = true
        // 不能在 tap 回调里 removeTap（会等自己），交给主线程收尾。
        DispatchQueue.main.async { [weak self] in
            self?.finishAtLimit()
        }
    }

    /// RMS → dBFS → 0…1。-50 dB 以下当作安静，0 dB 为满。
    private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count {
            let v = channel[0][i]
            sum += v * v
        }
        let rms = (sum / Float(count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 50) / 50))
    }

    private func finishAtLimit() {
        lock.lock()
        guard isRecordingFlag else {
            lock.unlock()
            return
        }
        isRecordingFlag = false
        lock.unlock()
        tearDownEngine()
    }

    // MARK: - 同步状态操作（供 async stopRecording 调用）

    private func markRecordingStopped() {
        lock.lock()
        isRecordingFlag = false
        lock.unlock()
    }

    private func takeCapturedSamples() -> (samples: [Int16], failure: SpeakorbError?) {
        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        converter = nil
        let failure = lastFailure
        lock.unlock()
        return (captured, failure)
    }

    // MARK: - 引擎

    private func tearDownEngine() {
        lock.lock()
        let installed = isTapInstalled
        isTapInstalled = false
        lock.unlock()

        if installed {
            engine.inputNode.removeTap(onBus: 0)
        }
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
    }
}
