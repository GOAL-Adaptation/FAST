/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic Initialization Procedure
 *
 *  authors: Ferenc A Bartha, Adam Duracz
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation
import LoggerAPI

//---------------------------------------

/** Attempt to inititalize a type T from reading external configuration settings */
func initialize<T>(type: T.Type, from key: [String]) -> T? {

    // TODO add readings from other places(xml,json,cfg,etc)
    // TODO log initialization in verbose mode 
    Log.debug("Initializing value of type \(type): \(key.joined(separator: "_")).") // this is just to showcase the possibility

    var newValue: T?

    if let TInitializable = T.self as? InitializableFromString.Type {
            
        // Try to read the environment
        if  let text = ProcessInfo.processInfo.environment[key.joined(separator: "_")],
            let value = TInitializable.init(from: text) {

                newValue = value as? T
        }
    }

    if let nv = newValue {
        Log.verbose("Initializing value of type \(type): \(key.joined(separator: "_")) to '\(nv)'.")
    }

    return newValue
}

/** Attempt to inititalize a type T from reading external configuration settings or default */
func initialize<T>(type: T.Type, from key: [String], or defaultValue: T) -> T {

    // Attempt to initialize from external readings
    let newValue: T? = initialize(type: T.self, from: key)
    
    // If initialization failed, return the default value
    if let nv = newValue { 
        return nv           
    }
    else { 
        Log.verbose("Initializing value of type \(type): \(key.joined(separator: "_")) to default '\(defaultValue)'.")
        return defaultValue 
    }

}

/** Attempt to inititalize a type T from reading external configuration settings or default */
func initialize<T>(type: T.Type, name: String, from key: [String], or defaultValue: T) -> T {

    return initialize(type: T.self, from: key.appended(with: name), or: defaultValue)
}

/** Attempt to inititalize a type T from reading external configuration settings */
func initialize<T>(type: T.Type, name: String, from key: [String]) -> T? {

    return initialize(type: T.self, from: key.appended(with: name))
}

//---------------------------------------
