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

        #if os(Linux)
        let bundle = Bundle.main
        #else
        let bundle = Bundle(for: type(of: self))
        #endif

        if let intentFileContent = readFile(withName: "incrementer", ofType: "intent", fromBundle: bundle),
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
        XCTAssertEqual("1", stepReference as! String)
        let stepRangeExpected = ["1", "2", "3", "4"]
        for i in 0 ..< stepRangeExpected.count {
            XCTAssertEqual(stepRangeExpected[i], stepRange[i] as! String)
        }

        let (thresholdRange, thresholdReference) = spec.knobs["threshold"]!
        XCTAssertEqual(1000000, thresholdReference as! Int)
        let thresholdRangeExpected = [200000, 400000, 600000, 800000, 1000000]
        for i in 0 ..< thresholdRangeExpected.count {
            XCTAssertEqual(thresholdRangeExpected[i], thresholdRange[i] as! Int)
        }

        XCTAssertTrue(spec.satisfiesKnobConstraints(knobSettings: KnobSettings(kid: -1, [
            "threshold"             : 600000,
            "step"                  : "3",
            "utilizedCores"         : 4,
            "utilizedCoreFrequency" : 600,
        ])))

        XCTAssertFalse(spec.satisfiesKnobConstraints(knobSettings: KnobSettings(kid: -1, [
            "threshold"             : 200000,
            "step"                  : "1",
            "utilizedCores"         : 4,
            "utilizedCoreFrequency" : 300,
        ])))

        /* Measures */

        // Note: this list must contain all the measures listed in incrementer.intent, but in alphabetical order
        // Note: this list must be reflected in incrementer.json
        XCTAssertEqual(["energy", "energyDelta", "latency", "operations", "performance", "powerConsumption", "quality"], spec.measures.sorted())

        /* Intent */

        XCTAssertEqual("incrementer", spec.name)

        // Constraints
        guard let (qualityConstraintValue, qualityConstraintType) = spec.constraints["quality"] else {
            XCTFail("Failed to parse quality constraint from intent.")
            return
        }
        XCTAssertEqual(qualityConstraintValue, 50000.0)
        XCTAssertEqual(qualityConstraintType, ConstraintType.lessOrEqualTo)
        
        guard let (performanceConstraintValue, performanceConstraintType) = spec.constraints["performance"] else {
            XCTFail("Failed to parse performance constraint from intent.")
            return
        }
        XCTAssertEqual(performanceConstraintValue, 5.0)
        XCTAssertEqual(performanceConstraintType, ConstraintType.greaterOrEqualTo)

        // Objective function
                                                // Note: this list must contain all the measures listed in incrementer.intent, but in alphabetical order
                                                // ["energy", "energyDelta", "latency", "operations", "performance", "powerConsumption", "quality"]
        XCTAssertEqual(1.0/9.0  , spec.costOrValue([13.0     , 7.0          , 1.0/50.0 , 3.0         , 50.0         , 11.0             , 1.0/9.0  ])) // 0.111... == 1.0/(3.0*3.0)
        
        // Optimization type
        XCTAssertEqual(.maximize    , spec.optimizationType)

        /* Training set */

        XCTAssertEqual([], spec.trainingSet)

    }

    static var allTests = [
        ("testCompileIntentSpec", testCompileIntentSpec)
    ]

}