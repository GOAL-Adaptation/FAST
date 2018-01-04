/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        TCP Socket Server
 *
 *  author: Ferenc A Bartha, Adam Duracz
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 *
 *  Core functionalities implemented in this file are based on
 *  the example provided by IBM for BlueSocket
 */

//-------------------------------

import Foundation
import Dispatch
import LoggerAPI
import Socket

//-------------------------------

/** TCP Socket Server
        based on IBM-Swift/BlueSocket
*/
class TcpSocketServer: CommunicationServer {

    static let bufferSize = 8192

    let port: Int
    let family: Socket.ProtocolFamily

    var listenSocket: Socket? = nil

    var continueRunning = true

    var connectedSockets = [Int32: Socket]()
    let socketLockQueue = DispatchQueue(label: "TcpSocketServer.socketLockQueue")

    var messageHandler: MessageHandler?

    private unowned let runtime: __Runtime

    /** TcpSocketServer.init: set the port, use IPV4 */
    init(port: Int, runtime: __Runtime) {
        self.runtime = runtime
        self.port = port
        self.family = .inet
    }

    /** TcpSocketServer.init: set the port, set family */
    init(port: Int, family: Socket.ProtocolFamily, runtime: __Runtime) {
        self.runtime = runtime
        self.port = port
        self.family = family
    }

    /** TcpSocketServer.deinit */
    deinit {

        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }
        self.listenSocket?.close()
    }

    //-------------------------------

    /** TcpSocketServer.run: start the TCP Server */
    func run(_ newMessageHandler: MessageHandler?) {

        // Register handling method for messages
        if let messageHandler = newMessageHandler {
            self.messageHandler = messageHandler
        }
        assert(self.messageHandler != nil)

        // Define asynchronous queue, QoS: responsiveness and performance
        let queue = DispatchQueue.global(qos: .utility)

        queue.async { [unowned self] in

            do {
                // Create a socket
                try self.listenSocket = Socket.create(family: self.family)

                guard let socket = self.listenSocket else {
                    Log.error("Unable to unwrap socket")
                    return
                }

                // Listen on port
                try socket.listen(on: self.port)

                Log.info("Run: Listening on port: \(socket.listeningPort)")

                // Accepting connections
                repeat {
                    let newSocket = try socket.acceptClientConnection()

                    Log.info("Accepted connection from: \(newSocket.remoteHostname) on port \(newSocket.remotePort)")
                    Log.verbose("Socket Signature: \(newSocket.signature?.description ?? "no signature")")

                    self.addNewConnection(socket: newSocket)

                } while self.continueRunning

            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    Log.error("Unexpected error...")
                    return
                }

                if self.continueRunning {

                    Log.error("Error reported:\n \(socketError.description)")

                }
            }
        }
    }

    //-------------------------------

    /** TcpSocketServer.addNewConnection: register new connection */
    func addNewConnection(socket: Socket) {

        // Add the new socket to the list of connected sockets...
        socketLockQueue.sync { [unowned self, socket] in
            self.connectedSockets[socket.socketfd] = socket
        }

        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .utility)

        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in

            var shouldKeepRunning = true

            var readData = Data(capacity: TcpSocketServer.bufferSize)

            do {

                repeat {
                    let bytesRead = try socket.read(into: &readData)

                    if bytesRead > 0 {
                        guard let response = self.messageHandler!.handle(server: self, &shouldKeepRunning, message: String(data: readData, encoding: .utf8)!) else {

                            Log.error("Error decoding response...")
                            readData.count = 0
                            break
                        }
                        try socket.write(from: response)
                    }

                    if bytesRead == 0 {

                        shouldKeepRunning = false
                        break
                    }

                    readData.count = 0

                } while shouldKeepRunning

                // Shutdown was issued
                if !self.continueRunning {
                    self.shutdownServer()
                }

                Log.info("Socket: \(socket.remoteHostname):\(socket.remotePort) closed...")
                socket.close()

                self.socketLockQueue.sync { [unowned self, socket] in
                    self.connectedSockets[socket.socketfd] = nil
                }

            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    Log.error("Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)...")
                    return
                }
                if self.continueRunning {
                    Log.error("Error reported by connection at \(socket.remoteHostname):\(socket.remotePort):\n \(socketError.description)")
                }
            }
        }
    }

    //-------------------------------

    func shutdownServer() {
        Log.error("Shutdown in progress...")
        continueRunning = false

        // Close all open sockets...
        for socket in connectedSockets.values {
            socket.close()
        }

        listenSocket?.close()

        DispatchQueue.main.sync {
            exit(0)
        }

        runtime.shutdown()
    }
}

//-------------------------------
