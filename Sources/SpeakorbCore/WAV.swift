import Foundation

public enum WAVEncoder {
    public struct Format: Equatable, Sendable {
        public var sampleRate: Int
        public var channels: Int
        public var bitsPerSample: Int
        public init(sampleRate: Int = 16_000, channels: Int = 1, bitsPerSample: Int = 16) {
            self.sampleRate = sampleRate
            self.channels = channels
            self.bitsPerSample = bitsPerSample
        }
    }

    /// 把 16-bit PCM 采样编码为 WAV 文件（RIFF）。
    public static func encode(samples: [Int16], format: Format = Format()) -> Data {
        let byteRate = format.sampleRate * format.channels * format.bitsPerSample / 8
        let blockAlign = format.channels * format.bitsPerSample / 8
        let dataSize = samples.count * 2
        var data = Data(capacity: 44 + dataSize)

        func appendASCII(_ s: String) { data.append(contentsOf: Array(s.utf8)) }
        func appendUInt32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func appendUInt16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(UInt16(format.channels))
        appendUInt32(UInt32(format.sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(format.bitsPerSample))
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        for sample in samples {
            var x = UInt16(bitPattern: sample).littleEndian
            withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func durationMs(sampleCount: Int, sampleRate: Int) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int((Double(sampleCount) / Double(sampleRate) * 1000).rounded())
    }
}
