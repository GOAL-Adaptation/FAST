/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic Initialization Procedure
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation

//---------------------------------------

/** Attempt to inititalize a type T from reading external configuration settings */
func initialize<T>(type: T.Type, from key: [String]) -> T? {

    // TODO add readings from other places(xml,json,cfg,etc)
    // TODO log initialization in verbose mode 

    var newValue: T?

    if let TInitializable = T.self as? InitializableFromString.Type {
            
        // Try to read the environment
        if  let text = ProcessInfo.processInfo.environment[key.joined(separator: "_")],
            let value = TInitializable.init(from: text) {

                newValue = value as? T
        }
    }

    return newValue
}

/** Attempt to inititalize a type T from reading external configuration settings or default */
func initialize<T>(type: T.Type, from key: [String], or defaultValue: T?) -> T? {

    // Attempt to initialize from external readings
    var newValue: T? = initialize(type: T.self, from: key)
    
    // Try the default value, if any
    if newValue == nil {
        newValue = defaultValue
    }

    return newValue
}

/** Attempt to inititalize a type T from reading external configuration settings or default */
func initialize<T>(type: T.Type, name: String, from key: [String], or defaultValue: T?) -> T? {

    return initialize(type: T.self, from: key.appended(with: name), or: defaultValue)
}

/** Attempt to inititalize a type T from reading external configuration settings */
func initialize<T>(type: T.Type, name: String, from key: [String]) -> T? {

    return initialize(type: T.self, from: key.appended(with: name))
}

//---------------------------------------
