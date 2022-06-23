import XCTest
import JSONFormat
import Foundation


final class JSONFormatTests: XCTestCase {

    override func setUp() {
        // This is here to warm up the cached data
        _ = testJSON
    }

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

    func test_SyncCountLargeFile() {
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


// MARK: - Results (Mac Studio, Release Build)

// Xcode 13.4
// Test Case '-[JSONFormatTests.JSONFormatTests test_SyncCountLargeFile]' passed (0.444 seconds).
// Test Case '-[JSONFormatTests.JSONFormatTests testAsyncCountLargeFile]' passed (0.521 seconds).
//
// Xcode 14 beta 2
// Test Case '-[JSONFormatTests.JSONFormatTests test_SyncCountLargeFile]' passed (0.390 seconds).
// Test Case '-[JSONFormatTests.JSONFormatTests testAsyncCountLargeFile]' passed (4.808 seconds).
//
// Xcode 14 beta 2, with @_unsafeInheritExecutor
// Test Case '-[JSONFormatTests.JSONFormatTests test_SyncCountLargeFile]' passed (0.386 seconds).
// Test Case '-[JSONFormatTests.JSONFormatTests testAsyncCountLargeFile]' passed (0.513 seconds).
