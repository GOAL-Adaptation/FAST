/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Communication Server
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

/** Communication Server Protocol */
protocol CommunicationServer: class {
    
    // Controls server shutdown
    var continueRunning: Bool { get set }

    // Starts the server
    func run(_ messageHandler: MessageHandler?)
}

//-------------------------------
