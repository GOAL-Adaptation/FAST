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

class OptimizeTests: FASTTestCase {

    func startThMockRestServer() -> RestServer {
        var thMockServer: RestServer? = nil
        // Start ThMockRestServer in a background thread
        DispatchQueue.global(qos: .utility).async {
            thMockServer = ThMockRestServer(port: RestClient.serverPort, address: RestClient.serverAddress, runtime: self.runtime)
            thMockServer!.start()
        }
        waitUntilUp(endpoint: "ready", host: RestClient.serverAddress, port: RestClient.serverPort, method: .post, description: "TH mock REST")
        return thMockServer!
    }

    func stopThMockRestServer(server: RestServer) {
        server.stop()
        waitUntilDown(endpoint: "ready", host: RestClient.serverAddress, port: RestClient.serverPort, method: .post, description: "TH mock REST")
    }

    func callFastRestServer
        ( endpoint      : String
        , method        : Request.Method  = .get
        , withBody json : [String : Any]? = [:]
        ) -> [String: Any]? {
        return
            RestClient.sendRequest( to         : endpoint
                                , over       : "http"
                                , at         : "0.0.0.0" //RestClient.serverAddress
                                , onPort     : self.runtime.restServerPort
                                , withMethod : method
                                , withBody   : json
                                , logErrors  : true
                                )
    }

    func withThMockRestServer(_ test: (RestServer) -> ()) {
        let thMockServer = startThMockRestServer()
        self.runtime.measure("time", 0.0)  // ensure "time" measurement exists for Optimize.optimize
        test(thMockServer)
        stopThMockRestServer(server: thMockServer)
    }

    /**
     * If FAST is unable to load the intent or model files, an optimize should
     * behave like a while(true) loop.
     */
    func testOptimizeWithoutIntentAndModel() {

        withThMockRestServer { _ in

            let threshold = 100
            var optimizeState: Int = 0
            var whileState: Int = 0

            optimize("NO_SUCH_INTENT", self.runtime) {
                if optimizeState < threshold {
                    optimizeState += 1
                }
                else { self.runtime.shouldTerminate = true }
            }

            while(true) {
                if whileState < threshold {
                    whileState += 1
                }
                else { break }
            }

            XCTAssertEqual(optimizeState, whileState)

        }

    }

    /**
     * Ensure that the REST API is brought up by the optimize construct.
     */
    func testThatOptimizeBringsUpTheRestServer() {

        withThMockRestServer { _ in

            optimize("NO_SUCH_INTENT", self.runtime) {

                let fastRestServerIsUp = nil != self.callFastRestServer(endpoint: "alive")

                XCTAssertTrue(fastRestServerIsUp)

                self.runtime.shouldTerminate = true
            }

        }

    }


    /**
     * Ensure that the REST API is brought up by the optimize construct.
     */
    func testBasicLLTestScenario() {

        withThMockRestServer { _ in

            optimize("NO_SUCH_INTENT", self.runtime) {

                let fastRestServerIsUp = nil != self.callFastRestServer(endpoint: "alive")

                XCTAssertTrue(fastRestServerIsUp)

                self.runtime.shouldTerminate = true
            }

        }

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
        ("testBasicLLTestScenario", testBasicLLTestScenario),
        ("testOptimizeWithoutIntentAndModel", testOptimizeWithoutIntentAndModel),
        ("testPerturbationInit", testPerturbationInit)
    ]

}
