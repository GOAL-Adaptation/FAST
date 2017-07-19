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

        let intentPath = "\(Bundle(for: type(of: self)).resourcePath!)/incrementer.intent"

        if let intentSpec = compiler.compileIntentSpec(from: intentPath) {
            XCTAssertEqual("incrementer", intentSpec.name)
            
            /* Knobs */

            let (stepRange, stepReference) = intentSpec.knobs["step"]!
            XCTAssertEqual(1, stepReference as! Int)
            XCTAssertEqual([0,1,2,3,4,5] as NSObject, stepRange as NSObject)

            let (thresholdRange, thresholdReference) = intentSpec.knobs["threshold"]!
            XCTAssertEqual(10000000, thresholdReference as! Int)
            XCTAssertEqual([0,2000000,4000000,6000000,8000000,10000000] as NSObject, thresholdRange as NSObject)

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
            XCTFail("Failed to parse intent at '\(intentPath)'.")
        }

    }

}