/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        System utilities
 *
 *  author: Adam Duracz
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation
import LoggerAPI

//---------------------------------------

/** 
  * Execute a shell command with arguments in a given environment.
  * By default, the environment is inherited from the parent process.
  *
  * Returns the return code of the command and, optionally, what the command 
  * wrote to standard output.
  */
func executeInShell(_ command: String, arguments: [String] = [], environment: [String : String]? = ProcessInfo.processInfo.environment) -> (Int32,String?) {
    let process = Process()
    process.launchPath = command
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output: String? = String(data: data, encoding: String.Encoding.utf8)
    
    Log.debug("Executed shell command: '\(command)' with arguments: \(arguments). Its output was: '\(String(describing: output))'.")
    return (process.terminationStatus, output)
}