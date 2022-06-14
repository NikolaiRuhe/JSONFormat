import XCTest
import JSONFormat
import Foundation


final class JSONFormatTests: XCTestCase {

    func testSimpleExample() async throws {
        let data = #"{"":[]}"#.data(using: .utf8)!

        let sut = JSONFormatAsync { buffer in
            buffer.copyBytes(from: data)
            return data.count
        }

        let result = try await sut.reduce("") { $0 + $1 + "\n" }
        print(result)
        XCTAssertEqual(result, "{\n  \"\": []\n}\n")
    }

    func testAsyncCountLargeFile() async throws {
        let sut = JSONFormatAsync(data: testJSON)
        var count = 1
        for try await _ in sut {
            count += 1
        }
        XCTAssertEqual(count, 732458)
    }

    func testMoreSync() {
        testJSON.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Void in
            var iterator = JSONFormatSync(buffer: buffer)
            var count = 1
            while let _ = iterator.next() {
                count += 1
            }
            XCTAssertEqual(count, 732458)
        }
    }
}

fileprivate let jsonURL = Bundle.module.url(forResource: "large-file", withExtension: "json")!
let testJSON = try! Data(contentsOf: jsonURL)


// Results, Mac Studio, Release Build:
// Test Case '-[JSONFormatTests.JSONFormatTests testAsyncCountLargeFile]' passed (5.857 seconds).
// Test Case '-[JSONFormatTests.JSONFormatTests testMoreSync]' passed (0.388 seconds).
