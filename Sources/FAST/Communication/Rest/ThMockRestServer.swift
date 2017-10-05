/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Mock of RESTful API to TH
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import Dispatch
import LoggerAPI
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["th","server","rest"]

class ThMockRestServer : RestServer {

    override func name() -> String? {
        return "TH mock REST server"
    }

    /* Dictionary representations of canned messages */

    static let intent = 
        "knobs       k1 = [1,2,3,4,5]   reference 5     \n" +
        "            k2 = [1,2,3,4]     reference 4     \n" +
        "            k3 = [1.1,2.2,3.3] reference 3.3   \n" +
        "measures    m1: Double                         \n" +
        "            m2: Double                         \n" +
        "intent      intent max(m1) such that m2 == 0.0 \n" +
        "trainingSet []"

    static let perturbation: [String : Any] = 
        [ "missionIntent"          : intent
        , "availableCores"         : 3
        , "availableCoreFrequency" : 2000000
        , "missionLength"          : 567
        , "sceneObfuscation"       : 0.0
        ]

    static let initializationParameters: [String : Any] = 
        [ "architecture"            : "ArmBigLittle"
        , "application"             : "incrementer"
        , "numberOfInputsToProcess" : 567
        , "adaptationEnabled"       : "true"
        , "statusInterval"          : 1
        , "randomSeed"              : 0
        , "initialConditions"       : perturbation
        ]

    /* Route configuration */

    @discardableResult override init(port: UInt16) {
  
        super.init(port: port)

        addSerialRoute(method: .post, uri: "/ready", handler: {
            request, response in

                Log.info("Received post to /ready endpoint.")

                self.addJsonBody( toResponse      : response
                                , json            : ThMockRestServer.initializationParameters
                                , jsonDescription : "initialization parameters"
                                , endpointName    : "ready" )

                response.completed() // HTTP 202

            }
        )

        server.addRoutes(self.routes)
        
    }

}

