/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of Main File
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import XCTest
@testable import FAST

//---------------------------------------

class FASTTests: XCTestCase {

    /**
     * Quick check to see if https://bugs.swift.org/browse/SR-221
     * affects the compiler that executes this test suite.
     * The test code corresponds to that of the first of the
     * 'Generated Superclass Mirrors' in:
     *    https://github.com/apple/swift/blob/master/test/stdlib/Mirror.swift#L235
     */
    func testSR221() {

        class B : CustomReflectable {
            var b: String = "two"
            var customMirror: Mirror {
            return Mirror(
                self, children: ["bee": b], ancestorRepresentation: .generated)
            }
        }
        
        let b = Mirror(reflecting: B())
        XCTAssertTrue(b.subjectType == B.self)
        XCTAssertNil(b.superclassMirror)
        XCTAssertEqual(1, b.children.count)
        XCTAssertEqual("bee", b.children.first!.label)
        XCTAssertEqual("two", b.children.first!.value as? String)

    }

    static var allTests = [
        ("testSR221", testSR221)
    ]

}

