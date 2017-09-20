/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of Compiler
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Source
import XCTest
@testable import FAST

//---------------------------------------

class CompilerTests: XCTestCase {

    static let compiler = Compiler()

    /** 
     * Check that the parsing and compilation of 'incrementer.intent' correctly
     * extracts information as an IntentSpec.
     */
    func testCompileIntentSpec() {

        if let intentFileContent = readFile(withName: "incrementer", ofType: "intent", fromBundle: Bundle(for: type(of: self))),
           let intentSpec = CompilerTests.compiler.compileIntentSpec(source: intentFileContent) {

            CompilerTests.checkIncrementer(spec: intentSpec)

        }
        else {
            XCTFail("Failed to parse intent at 'incrementer.intent'.")
        }

    }

    static func checkIncrementer(spec: IntentSpec) {

        XCTAssertEqual("incrementer", spec.name)
            
        /* Knobs */

        let (stepRange, stepReference) = spec.knobs["step"]!
        XCTAssertEqual(1, stepReference as! Int)
        let stepRangeExpected = [1,2,3,4]
        for i in 0 ..< stepRangeExpected.count {
            XCTAssertEqual(stepRangeExpected[i], stepRange[i] as! Int)
        }

        let (thresholdRange, thresholdReference) = spec.knobs["threshold"]!
        XCTAssertEqual(10000000, thresholdReference as! Int)
        let thresholdRangeExpected = [2000000,4000000,6000000,8000000,10000000]
        for i in 0 ..< thresholdRangeExpected.count {
            XCTAssertEqual(thresholdRangeExpected[i], thresholdRange[i] as! Int)
        }

        /* Measures */

        XCTAssertEqual(["latency", "operations"], spec.measures)

        /* Intent */

        XCTAssertEqual("incrementer", spec.name)
        XCTAssertEqual(0.1          , spec.constraint)
        XCTAssertEqual("latency"    , spec.constraintName)
        XCTAssertEqual(4.5          , spec.costOrValue([0.0,3.0])) // 4.5 == (3.0*3.0)/2.0
        XCTAssertEqual(.minimize    , spec.optimizationType)

        /* Training set */

        XCTAssertEqual([], spec.trainingSet)

    }

    static var allTests = [
        ("testCompileIntentSpec", testCompileIntentSpec)
    ]

}