public typealias CodePoint = String.UTF8View.Element


public extension CodePoint {

    @inline(__always)
    var isWhitespace: Bool {
        switch self {
        case 0x20, 0x09, 0x0a, 0x0d: return true
        default: return false
        }
    }

    @inline(__always)
    var isControl: Bool {
        return self < 0x20
    }

    @inline(__always)
    var isSign: Bool {
        return self == 0x2b || self == 0x2d
    }

    @inline(__always)
    var isDigit: Bool {
        return self >= 0x30 && self <= 0x39
    }

    @inline(__always)
    var isExponentChar: Bool {
        return self == 0x45 || self == 0x65
    }

    @inline(__always)
    var isStringChar: Bool {
        switch self {
        case 0x22: // "
            return false
        case 0x5c: // \
            return false
        case 0 ..< 32:
            return false
        default:
            return true
        }
    }
}
