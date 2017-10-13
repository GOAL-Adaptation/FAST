/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of RestServer
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import PerfectLib
import XCTest
@testable import FAST

//---------------------------------------

class RestServerTests: XCTestCase {

    /** Expressinons encoded in JSON should serialize to the corresponding string representation. */
    func testMkExpressionString() {

        let literal        = try! "{ \"literal\": 2.0 }".jsonDecode()   as! [String: Any]
        let variableName   = try! "{ \"variableName\": \"x\" }".jsonDecode() as! [String: Any]
        let unaryOperator  = try! "{ \"operator\": \"-\", \"expression\": { \"literal\": 3.0 }  }".jsonDecode() as! [String: Any]
        let binaryOperator = try! "{ \"operator\": \"/\", \"leftExpression\": { \"literal\": 1.0 }, \"rightExpression\": { \"variableName\": \"x\" } }".jsonDecode() as! [String: Any]

        XCTAssertEqual("2.0",       RestServer.mkExpressionString(from: literal))
        XCTAssertEqual("x",         RestServer.mkExpressionString(from: variableName))
        XCTAssertEqual("(-3.0)",    RestServer.mkExpressionString(from: unaryOperator))
        XCTAssertEqual("(1.0 / x)", RestServer.mkExpressionString(from: binaryOperator))

    }

    /** An intent encoded in JSON should compile to the correct IntentSpec. */
    func testMkIntentString() {

        #if os(Linux)
        let bundle = Bundle.main
        #else
        let bundle = Bundle(for: type(of: self))
        #endif

        if let intentJsonFileContent = readFile(withName: "incrementer", ofType: "json", fromBundle: bundle),
           let intentJson            = try? intentJsonFileContent.jsonDecode(),
           let intentJsonDictionary  = intentJson as? [String:Any] {
            
            let intentStringFromJson = RestServer.mkIntentString(from: intentJsonDictionary)

            if let intentSpec = CompilerTests.compiler.compileIntentSpec(source: intentStringFromJson) {
                CompilerTests.checkIncrementer(spec: intentSpec)
            }
            else {
                XCTFail("Failed to compile intent parsed from 'incrementer.json' into an IntentSpec.")
            }

        }
        else {
            XCTFail("Failed to parse JSON from 'incrementer.json'.")
        }

    }

    static var allTests = [
        ("testMkIntentString",     testMkIntentString),
        ("testMkExpressionString", testMkExpressionString)           
    ]

}