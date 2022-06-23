import Foundation

fileprivate typealias JSONFormat = JSONFormatAsync

public struct JSONFormatAsync: AsyncIteratorProtocol, AsyncSequence {

    public init(data: Data) {
        actor DataReader {
            init(_ data: Data) { self.data = data }
            var data: Data
            func read(into buffer: UnsafeMutableRawBufferPointer) -> Int {
                let chunk = data.prefix(buffer.count)
                if chunk.isEmpty { return 0 }
                chunk.copyBytes(to: buffer)
                data = data.suffix(from: data.startIndex + chunk.count)
                return chunk.count
            }
        }
        let source = DataReader(data)
        self.init() { buffer in
            await source.read(into: buffer)
        }
    }

    public init(readFunction: @Sendable @escaping (UnsafeMutableRawBufferPointer) async throws -> Int) {
        self.input = AsyncBufferedByteIterator(capacity: 1024, readFunction: readFunction)
    }

    public func makeAsyncIterator() -> JSONFormatAsync { self }
    public mutating func next() async throws -> String? { try await parseNextIndented() }
    fileprivate var input: AsyncBufferedByteIterator
    @inline(__always) /* @_unsafeInheritExecutor */ fileprivate mutating func nextCodePoint() async throws -> CodePoint? { try await input.next() }
    fileprivate var putBackChar: CodePoint? = nil

    fileprivate var state = State.initial
    fileprivate var stack: [NestingType] = []

    public typealias Element = String

    public struct JSONError: Error {
        var reason: String
        init(_ reason: String) {
            self.reason = reason
        }
    }
}


fileprivate extension JSONFormat {
    enum NestingType {
        case array
        case object
    }

    enum State {
        case initial
        case finished
        case inObject
        case inArray
        case inNumber
        case inBool
        case error
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func read() async throws -> CodePoint {
        guard let codePoint = try await readOptional() else {
            state = .error
            throw JSONError("more input expected")
        }
        return codePoint
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func readOptional() async throws -> CodePoint? {
        if let putBackChar = putBackChar {
            self.putBackChar = nil
            return putBackChar
        }

        while true {
            guard let codePoint = try await nextCodePoint() else {
                return nil
            }
            if codePoint.isWhitespace { continue }
            if codePoint.isControl {
                throw JSONError("unexpected control character")
            }
            return codePoint
        }
    }

    /* @_unsafeInheritExecutor */
    mutating func parseNextIndented() async throws -> String? {
        var depth = stack.count
        if let value = try await parseNext() {
            depth -= stack.count < depth ? 1 : 0
            return String(repeating: " ", count: depth * 2) +  value
        }
        return nil
    }

    /* @_unsafeInheritExecutor */
    mutating func parseNext() async throws -> String? {
        switch state {
        case .error, .finished: return nil
        case .initial: return try await parseValue()
        case .inObject: return try await parseObjectContents()
        case .inArray: return try await parseArrayContents()
        default: fatalError("not yet implemented")
        }
    }

    /* @_unsafeInheritExecutor */
    mutating func parseValue() async throws -> String {
        let codePoint = try await read()
        switch codePoint {
        case 0x7b: // {
            return try await parseBeginObject()
        case 0x5b: // [
            return try await parseBeginArray()
        case 0x6e: // n
            try await parse(expected: "ull".utf8)
            return "null"
        case 0x74: // t
            try await parse(expected: "rue".utf8)
            return "true"
        case 0x66: // f
            try await parse(expected: "alse".utf8)
            return "false"
        case 0x30 ... 0x39, 0x2d: // 0-9, -
            return try await parseNumber(startingWith: codePoint)
        case 0x22: // "
            return try await parseDoubleQuotedString()
        default:
            throw JSONError("unexpected character")
        }
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func parseBeginObject() async throws -> String {
        let codePoint = try await read()
        if codePoint == 0x7d {
            return "{}"
        } else {
            putBackChar = codePoint
            state = .inObject
            stack.append(.object)
            return "{"
        }
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func parseEndObject() async throws -> Bool {
        let codePoint = try await read()
        switch codePoint {
        case 0x7d: // }
            return true
        case 0x22: // "
            return false
        default:
            throw JSONError("unexpected character: \(codePoint)")
        }
    }

    /* @_unsafeInheritExecutor */
    mutating func parseObjectContents() async throws -> String? {

        if try await parseEndObject() {
            stack.removeLast()
            switch stack.last {
            case nil:     state = .finished
            case .object: state = .inObject
            case .array:  state = .inArray
            }
            if try await parseCommaOptional() {
                return "},"
            }
            return "}"
        }

        let string = try await parseDoubleQuotedString()
        try await parse(expected: ":".utf8)

        let count = stack.count
        let element = try await parseValue()
        if stack.count != count {
            return "\(string): \(element)"
        }

        if try await parseCommaOptional() {
            return "\(string): \(element),"
        }

        return "\(string): \(element)"
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func parseBeginArray() async throws -> String {
        let codePoint = try await read()
        if codePoint == 0x5d {
            return "[]"
        } else {
            putBackChar = codePoint
            state = .inArray
            stack.append(.array)
            return "["
        }
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func parseEndArray() async throws -> Bool {
        let codePoint = try await read()
        if codePoint == 0x5d {
            return true
        }
        putBackChar = codePoint
        return false
    }

    /* @_unsafeInheritExecutor */
    mutating func parseArrayContents() async throws -> String? {

        if try await parseEndArray() {
            stack.removeLast()
            switch stack.last {
            case nil:     state = .finished
            case .object: state = .inObject
            case .array:  state = .inArray
            }
            if try await parseCommaOptional() {
                return "],"
            }
            return "]"
        }

        let count = stack.count
        let element = try await parseValue()
        if stack.count != count {
            return element
        }

        if try await parseCommaOptional() {
            return element + ","
        }

        return element
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func parseCommaOptional() async throws -> Bool {
        guard let codePoint = try await readOptional() else {
            return false
        }
        switch codePoint {
        case 0x2c: // ,
            return true
        default:
            putBackChar = codePoint
            return false
        }
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func parse(expected: String.UTF8View) async throws {
        for expectedCodePoint in expected {
            let codePoint = try await read()
            guard codePoint == expectedCodePoint else {
                throw JSONError("unexpected character")
            }
        }
    }

    /* @_unsafeInheritExecutor */
    mutating func parseDoubleQuotedString() async throws -> String {
        var utf8: [CodePoint] = [0x22]
        while true {
            let codePoint = try await read()
            utf8.append(codePoint)

            switch codePoint {
            case 0x22: // "
                guard let string = String(bytes: utf8, encoding: .utf8) else {
                    throw JSONError("cannot decode utf8")
                }
                return string
            case 0x5c: // \
                let codePoint = try await read()
                utf8.append(codePoint)
                continue
            default:
                continue
            }
        }
    }

    @inline(__always) /* @_unsafeInheritExecutor */
    mutating func readDigits(into utf8: inout [CodePoint]) async throws {
        while true {
            let codePoint = try await read()
            if (0x30 ... 0x39).contains(codePoint) {
                utf8.append(codePoint)
            } else {
                putBackChar = codePoint
                break
            }
        }
    }

    /* @_unsafeInheritExecutor */
    mutating func parseNumber(startingWith codePoint: CodePoint) async throws -> String {
        var codePoint = codePoint
        var utf8: [CodePoint] = [codePoint]
        if codePoint == 0x2d {
            codePoint = try await read()
            utf8.append(codePoint)
        }

        switch codePoint {
        case 0x30: // 0
            break
        case 0x31 ... 0x39: // 1-9
            try await readDigits(into: &utf8)
        default:
            throw JSONError("unexpected character")
        }

        codePoint = try await read()

        if codePoint == 0x2e { // .
            utf8.append(codePoint)
            try await readDigits(into: &utf8)
            codePoint = try await read()
        }

        if codePoint.isExponentChar {
            utf8.append(codePoint)
            codePoint = try await read()

            if codePoint.isSign {
                utf8.append(codePoint)
                codePoint = try await read()
            }

            if codePoint.isDigit {
                utf8.append(codePoint)
                try await readDigits(into: &utf8)
            } else {
                throw JSONError("syntax error in number")
            }
        } else {
            putBackChar = codePoint
        }

        guard let string = String(bytes: utf8, encoding: .utf8) else {
            throw JSONError("cannot decode utf8")
        }
        return string
    }
}
