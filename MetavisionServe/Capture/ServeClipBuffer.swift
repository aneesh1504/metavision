import UIKit

/// Thread-safe rolling buffer of UIImage frames from the HSTN stream.
/// Clips are extracted by index range after serve detection.
final class ServeClipBuffer: @unchecked Sendable {

    private let lock = NSLock()
    private var frames: [UIImage] = []
    private var timestamps: [Date] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        frames.reserveCapacity(capacity)
        timestamps.reserveCapacity(capacity)
    }

    // MARK: - Write

    func push(_ frame: UIImage) {
        lock.lock()
        defer { lock.unlock() }
        if frames.count >= capacity {
            frames.removeFirst()
            timestamps.removeFirst()
        }
        frames.append(frame)
        timestamps.append(Date())
    }

    // MARK: - Read

    /// Returns up to `count` frames ending at the current tail, plus their timestamps.
    func tail(_ count: Int) -> [(image: UIImage, timestamp: Date)] {
        lock.lock()
        defer { lock.unlock() }
        let start = max(0, frames.count - count)
        return zip(frames[start...], timestamps[start...]).map { ($0, $1) }
    }

    /// Returns the most recent `seconds` worth of frames (approximate at 24 fps).
    func recentSeconds(_ seconds: Double) -> [(image: UIImage, timestamp: Date)] {
        tail(Int(seconds * 24))
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return frames.count
    }
}
