import Foundation

fileprivate typealias JSONFormat = JSONFormatSync

public struct JSONFormatSync: IteratorProtocol {
    public init(buffer: UnsafeRawBufferPointer) {
        self.buffer = buffer
        self.cursor = buffer.startIndex
    }

    let buffer: UnsafeRawBufferPointer
    var cursor: UnsafeRawBufferPointer.Index
    
    fileprivate var nextCodePoint: CodePoint? {
        mutating get throws {
            if cursor == buffer.endIndex { return nil }
            defer { cursor += 1 }
            return buffer[cursor]
        }
    }
    public mutating func next() -> String? {
        do {
            return try parseNextIndented()
        } catch {
            print(error)
            state = .error
            return nil
        }
    }
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

    @inline(__always)
    mutating func read() throws -> CodePoint {
        guard let codePoint = try readOptional() else {
            state = .error
            throw JSONError("more input expected")
        }
        return codePoint
    }

    @inline(__always)
    mutating func readOptional() throws -> CodePoint? {
        if let putBackChar {
            self.putBackChar = nil
            return putBackChar
        }

        while true {
            guard let codePoint = try nextCodePoint else {
                return nil
            }
            if codePoint.isWhitespace { continue }
            if codePoint.isControl {
                throw JSONError("unexpected control character")
            }
            return codePoint
        }
    }

    mutating func parseNextIndented() throws -> String? {
        var depth = stack.count
        if let value = try parseNext() {
            depth -= stack.count < depth ? 1 : 0
            return String(repeating: " ", count: depth * 2) +  value
        }
        return nil
    }

    mutating func parseNext() throws -> String? {
        switch state {
        case .error, .finished: return nil
        case .initial: return try parseValue()
        case .inObject: return try parseObjectContents()
        case .inArray: return try parseArrayContents()
        default: fatalError("not yet implemented")
        }
    }

    mutating func parseValue() throws -> String {
        let codePoint = try read()
        switch codePoint {
        case 0x7b: // {
            return try parseBeginObject()
        case 0x5b: // [
            return try parseBeginArray()
        case 0x6e: // n
            try parse(expected: "ull".utf8)
            return "null"
        case 0x74: // t
            try parse(expected: "rue".utf8)
            return "true"
        case 0x66: // f
            try parse(expected: "alse".utf8)
            return "false"
        case 0x30 ... 0x39, 0x2d: // 0-9, -
            return try parseNumber(startingWith: codePoint)
        case 0x22: // "
            return try parseDoubleQuotedString()
        default:
            throw JSONError("unexpected character")
        }
    }

    @inline(__always)
    mutating func parseBeginObject() throws -> String {
        let codePoint = try read()
        if codePoint == 0x7d {
            return "{}"
        } else {
            putBackChar = codePoint
            state = .inObject
            stack.append(.object)
            return "{"
        }
    }

    @inline(__always)
    mutating func parseEndObject() throws -> Bool {
        let codePoint = try read()
        switch codePoint {
        case 0x7d: // }
            return true
        case 0x22: // "
            return false
        default:
            throw JSONError("unexpected character: \(codePoint)")
        }
    }

    mutating func parseObjectContents() throws -> String? {

        if try parseEndObject() {
            stack.removeLast()
            switch stack.last {
            case nil:     state = .finished
            case .object: state = .inObject
            case .array:  state = .inArray
            }
            if try parseCommaOptional() {
                return "},"
            }
            return "}"
        }

        let string = try parseDoubleQuotedString()
        try parse(expected: ":".utf8)

        let count = stack.count
        let element = try parseValue()
        if stack.count != count {
            return "\(string): \(element)"
        }

        if try parseCommaOptional() {
            return "\(string): \(element),"
        }

        return "\(string): \(element)"
    }

    @inline(__always)
    mutating func parseBeginArray() throws -> String {
        let codePoint = try read()
        if codePoint == 0x5d {
            return "[]"
        } else {
            putBackChar = codePoint
            state = .inArray
            stack.append(.array)
            return "["
        }
    }

    @inline(__always)
    mutating func parseEndArray() throws -> Bool {
        let codePoint = try read()
        if codePoint == 0x5d {
            return true
        }
        putBackChar = codePoint
        return false
    }

    mutating func parseArrayContents() throws -> String? {

        if try parseEndArray() {
            stack.removeLast()
            switch stack.last {
            case nil:     state = .finished
            case .object: state = .inObject
            case .array:  state = .inArray
            }
            if try parseCommaOptional() {
                return "],"
            }
            return "]"
        }

        let count = stack.count
        let element = try parseValue()
        if stack.count != count {
            return element
        }

        if try parseCommaOptional() {
            return element + ","
        }

        return element
    }

    @inline(__always)
    mutating func parseCommaOptional() throws -> Bool {
        guard let codePoint = try readOptional() else {
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

    @inline(__always)
    mutating func parse(expected: String.UTF8View) throws {
        for expectedCodePoint in expected {
            let codePoint = try read()
            guard codePoint == expectedCodePoint else {
                throw JSONError("unexpected character")
            }
        }
    }

    mutating func parseDoubleQuotedString() throws -> String {
        var utf8: [CodePoint] = [0x22]
        while true {
            let codePoint = try read()
            utf8.append(codePoint)

            switch codePoint {
            case 0x22: // "
                guard let string = String(bytes: utf8, encoding: .utf8) else {
                    throw JSONError("cannot decode utf8")
                }
                return string
            case 0x5c: // \
                let codePoint = try read()
                utf8.append(codePoint)
                continue
            default:
                continue
            }
        }
    }

    @inline(__always)
    mutating func readDigits(into utf8: inout [CodePoint]) throws {
        while true {
            let codePoint = try read()
            if (0x30 ... 0x39).contains(codePoint) {
                utf8.append(codePoint)
            } else {
                putBackChar = codePoint
                break
            }
        }
    }

    mutating func parseNumber(startingWith codePoint: CodePoint) throws -> String {
        var codePoint = codePoint
        var utf8: [CodePoint] = [codePoint]
        if codePoint == 0x2d {
            codePoint = try read()
            utf8.append(codePoint)
        }

        switch codePoint {
        case 0x30: // 0
            break
        case 0x31 ... 0x39: // 1-9
            try readDigits(into: &utf8)
        default:
            throw JSONError("unexpected character")
        }

        codePoint = try read()

        if codePoint == 0x2e { // .
            utf8.append(codePoint)
            try readDigits(into: &utf8)
            codePoint = try read()
        }

        if codePoint.isExponentChar {
            utf8.append(codePoint)
            codePoint = try read()

            if codePoint.isSign {
                utf8.append(codePoint)
                codePoint = try read()
            }

            if codePoint.isDigit {
                utf8.append(codePoint)
                try readDigits(into: &utf8)
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
