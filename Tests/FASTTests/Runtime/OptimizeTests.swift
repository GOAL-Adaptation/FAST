/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of the Optimize construct and supporting functions
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Dispatch
import XCTest
@testable import FAST

//---------------------------------------

class OptimizeTests: XCTestCase {

    func startThMockRestServer() -> RestServer {
        var thMockServer: RestServer? = nil
        // Start ThMockRestServer in a background thread
        DispatchQueue.global(qos: .utility).async {
            thMockServer = ThMockRestServer(port: RestClient.serverPort, address: RestClient.serverAddress)
            thMockServer!.start()
        }
        waitUntilUp(endpoint: "ready", host: RestClient.serverAddress, port: RestClient.serverPort, method: .post, description: "TH mock REST")
        return thMockServer!
    }

    func stopThMockRestServer(server: RestServer) {
        server.stop()
        waitUntilDown(endpoint: "ready", host: RestClient.serverAddress, port: RestClient.serverPort, method: .post, description: "TH mock REST")
    }

    /** 
     * If FAST is unable to load the intent or model files, an optimize should 
     * behave like a while(true) loop.
     */
    func testOptimizeWithoutIntentAndModel() {
        
        let thMockServer = startThMockRestServer()

        let threshold = 100
        var optimizeState: Int = 0
        var whileState: Int = 0

        optimize("NO_SUCH_INTENT", []) {
            if optimizeState < threshold {
                optimizeState += 1
            }
            else { Runtime.shouldTerminate = true }
        }

        while(true) {
            if whileState < threshold { 
                whileState += 1
            }
            else { break }
        }

        stopThMockRestServer(server: thMockServer)

        XCTAssertTrue(optimizeState == whileState)

    }

    /** 
     * Ensure that the REST API is brought up by the optimize construct.
     */
    func testThatOptimizeBringsUpTheRestServer() {
        
        let thMockServer = startThMockRestServer()

        optimize("NO_SUCH_INTENT", []) {

            let fastRestServerIsUp = 
                nil !=
                    RestClient.sendRequest( to         : "alive"
                                            , over       : "http"
                                            , at         : RestClient.serverAddress
                                            , onPort     : Runtime.restServerPort
                                            , withMethod : .post
                                            , withBody   : [:]
                                            , logErrors  : false
                                            )

            XCTAssertTrue(fastRestServerIsUp)

            Runtime.shouldTerminate = true
        }

        stopThMockRestServer(server: thMockServer)

    }

    /**
     * Test initializing a Perturbation from a "JSON" [String : Any] dictionary
     */
    func testPerturbationInit() {

        if let perturbation = Perturbation(json: ThMockRestServer.perturbation) {
            XCTAssertEqual(3, perturbation.availableCores)
        }
        else {
            XCTFail("Failed to initialize Perturbation from JSON: \(ThMockRestServer.perturbation).")
        }

    }

    static var allTests = [
        ("testThatOptimizeBringsUpTheRestServer", testThatOptimizeBringsUpTheRestServer),
        ("testOptimizeWithoutIntentAndModel", testOptimizeWithoutIntentAndModel),
        ("testPerturbationInit", testPerturbationInit)
    ]

}

