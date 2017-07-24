/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Intent Specification Compiler
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import LoggerAPI
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer

//---------------------------------------

/**  */
class RestServer {

    let server = HTTPServer()
    var routes = Routes()

    @discardableResult init() {
        server.serverPort = initialize(type: UInt16.self, from: ["server","port","rest"]) ?? 1338
        routes.add(method: .get, uri: "/alive", handler: {
            _, response in
            response.status = Runtime.shouldTerminate ? .serviceUnavailable : .ok
            response.completed()
            }
        )
        routes.add(method: .post, uri: "/perturb", handler: {
            request, response in
            if let postBodyString = request.postBodyString {
                if let postBodyData = postBodyString.data(using: String.Encoding.utf8) {
                    do {

                        let json = try JSONSerialization.jsonObject(with: postBodyData) as! [String: Any]
                        Log.debug("Received valid JSON on /perturb endpoint: \(json)")
                        
                        // FIXME Use (definitions section of) Swagger specification to validate the input,
                        //       to make indexing and casts fail there instead, with detailed error information.
                        let missionIntent          = json["missionIntent"]!          as! String
                        let availableCores         = json["availableCores"]!         as! Int
                        let availableCoreFrequency = json["availableCoreFrequency"]! as! Int
                        let missionLength          = json["missionLength"]!          as! Int
                        let sceneObfuscation       = json["sceneObfuscation"]!       as! Double

                        // Change intent
                        // TODO Figure out if it is better to delay intent change/controller re-init until the end of the window
                        let intentSpec = Runtime.intentCompiler.compileIntentSpec(source: missionIntent)!
                        Runtime.reinitializeController(intentSpec)
                        
                        // FIXME Handle scenario knobs listed in the Perturbation JSON Schema: 
                        //       availableCores, availableCoreFrequency, missionLength, sceneObfuscation. 
                        //       This requires:
                        //       1) extending the Runtime with a handler for scenario knob setting,
                        //       2) adding missionLength and sceneObfuscation knobs, perhaps to a new 
                        //          "Environment" TextApiModule.

                        response.status = .ok // HTTP 202, which is default, but setting it for clarity

                    } catch let err {
                        Log.error("POST body sent to /perturb REST endpoint does not contain valid JSON: \(postBodyString). \(err)")
                        response.status = .notAcceptable // HTTP 406
                    }
                } 
                else {
                    Log.error("POST body sent to /perturb REST endpoint does not contain UTF8-encoded data: \(postBodyString).")
                    response.status = .notAcceptable // HTTP 406
                }
            }
            else {
                Log.error("Empty POST body sent to /perturb REST endpoint.")
                response.status = .notAcceptable // HTTP 406
            }
            response.completed()
        })
        routes.add(method: .post, uri: "/terminate", handler: {
            _, response in
            Runtime.shouldTerminate = true
            response.completed() // HTTP 202
            }
        )
        server.addRoutes(routes)
        do {
            try server.start()
            Log.info("REST server open on port \(server.serverPort).")
        } catch PerfectError.networkError(let err, let msg) {
            Log.warning("Network error thrown while starting REST server: \(err) \(msg).")
        } catch let err {
            Log.warning("Error thrown while starting REST server: \(err).")
        }

    }

}

