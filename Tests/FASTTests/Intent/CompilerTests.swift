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

    /** 
     * Check that the parsing and compilation of 'incrementer.intent' correctly
     * extracts information as an IntentSpec.
     */
    func testCompileIntentSpec() {
        
        let compiler = Compiler()

        if let intentFileContent = readFile(withName: "incrementer", ofType: "intent", fromBundle: Bundle(for: type(of: self))),
           let intentSpec = compiler.compileIntentSpec(source: intentFileContent) {
            XCTAssertEqual("incrementer", intentSpec.name)
            
            /* Knobs */

            let (stepRange, stepReference) = intentSpec.knobs["step"]!
            XCTAssertEqual(1, stepReference as! Int)
            let stepRangeExpected = [0,1,2,3,4,5]
            for i in 0 ..< stepRangeExpected.count {
                XCTAssertEqual(stepRangeExpected[i], stepRange[i] as! Int)
            }

            let (thresholdRange, thresholdReference) = intentSpec.knobs["threshold"]!
            XCTAssertEqual(10000000, thresholdReference as! Int)
            let thresholdRangeExpected = [0,2000000,4000000,6000000,8000000,10000000]
            for i in 0 ..< thresholdRangeExpected.count {
                XCTAssertEqual(thresholdRangeExpected[i], thresholdRange[i] as! Int)
            }

            /* Measures */

            XCTAssertEqual(["latency", "operations"], intentSpec.measures)

            /* Intent */

            XCTAssertEqual("incrementer", intentSpec.name)
            XCTAssertEqual(0.1          , intentSpec.constraint)
            XCTAssertEqual("latency"    , intentSpec.constraintName)
            XCTAssertEqual(0.25         , intentSpec.costOrValue([0.0,3.0])) // 0.25 == 1.0/(3.0+1.0)
            XCTAssertEqual(.minimize    , intentSpec.optimizationType)

            /* Training set */

            XCTAssertEqual([], intentSpec.trainingSet)

        }
        else {
            XCTFail("Failed to parse intent at 'incrementer.intent'.")
        }

    }

    static var allTests = [
        ("testCompileIntentSpec", testCompileIntentSpec)
    ]

}