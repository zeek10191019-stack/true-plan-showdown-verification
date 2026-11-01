import Foundation

struct FramePacket {
    let frameID: Int64
    let png: Data
    let monotonicMs: Int64
    let wallClockMs: Int64
}
