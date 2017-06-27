/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Handling Messages
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

/** Handling messages */
class MessageHandler {
    
    let goodbyeMessage = "Connection is closing."
    let shutdownMessage = "FAST Application is shutting down."

    let quitCommand = "close"
    let shutdownCommand = "exit"

    //-------------------------------

    func handle(server: CommunicationServer, _ shouldKeepRunning: inout Bool, message: String) -> String? {

        /** A message is either a 
         *  - quit     : close this client connection
         *  - shutdown : close the FAST application
         *  - other    : delegated to the main text API
         */
        switch message {

            // Quit
            case self.quitCommand:
                shouldKeepRunning = false

                return self.goodbyeMessage

            // Shutdown
            case self.shutdownCommand:
                shouldKeepRunning      = false
                server.continueRunning = false

                // TODO finalizing logs and shutting down other units is to be initiated from here
                Runtime.shouldTerminate = true

                return self.shutdownMessage

            // text API
            default:
                return Runtime.apiModule.textApi(caller: "TCPServer", message: message.components(separatedBy: " "), progressIndicator: 0, verbosityLevel: VerbosityLevel.Verbose)
        }
    }
}

//-------------------------------
