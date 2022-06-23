import Foundation

/// A minimal implementation that mimics the interface of `SwiftAlgorithms.AsyncBufferedByteIterator`.
///
/// Runs on older Swift versions and we can set the needed attribute (@_unsafeInheritExecutor).
class AsyncBufferedByteIterator: AsyncIteratorProtocol {
    let capacity: Int
    var isTerminated = false
    var buffer: UnsafeMutableRawBufferPointer
    var cursor: Int = 0
    let readFunction: @Sendable (UnsafeMutableRawBufferPointer) async throws -> Int

    init(capacity: Int, readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutableRawBufferPointer(start: nil, count: 0)
        self.readFunction = readFunction
    }

    /* @_unsafeInheritExecutor */
    func next() async throws -> UInt8? {
        if isTerminated { return nil }

        if cursor < buffer.count {
            defer { cursor += 1 }
            return buffer[cursor]
        }

        buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: capacity, alignment: MemoryLayout<UInt8>.alignment)
        let length = try await readFunction(buffer)

        if length == 0 {
            isTerminated = true
            return nil
        }

        buffer = UnsafeMutableRawBufferPointer(start: buffer.baseAddress, count: length)
        cursor = 1
        return buffer[0]
    }
}
