/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  Types that are (fallibly) initializable from a String
 *
 *  authors: Ferenc A Bartha, Adam Duracz
 */

//---------------------------------------

import LoggerAPI

//---------------------------------------

/** The protocol for a fallible initializer */
public protocol InitializableFromString {

    init?(from text: String)

}

//---------------------------------------
/** Extensions to built-in SWIFT types */

// TODO add ints, doubles, standard types

/** Extension for String */
extension String: InitializableFromString {

    public init?(from text: String) {
        self = text
    }

}

/** Extension for Int */
extension Int: InitializableFromString {

    public init?(from text: String) {
        if let value = Int(text) {
            self = value
        } else {
            failedToInitialize("Int", from: text)
            return nil
        }
    }

}

/** Extension for UInt16 */
extension UInt16: InitializableFromString {

    public init?(from text: String) {
        if let value = UInt16(text) {
            self = value
        } else {
            failedToInitialize("UInt16", from: text)
            return nil
        }
    }

}

/** Extension for UInt32 */
extension UInt32: InitializableFromString {

    public init?(from text: String) {
        if let value = UInt32(text) {
            self = value
        } else {
            failedToInitialize("UInt32", from: text)
            return nil
        }
    }

}

/** Extension for ApplicationExecutionMode */
extension ApplicationExecutionMode: InitializableFromString {

    public init?(from text: String) {
        switch text {
            case "Adaptive": 
                self = .Adaptive
            case "NonAdaptive": 
                self = .NonAdaptive
            case "ExhaustiveProfiling": 
                self = .ExhaustiveProfiling
            default:
                failedToInitialize("ApplicationExecutionMode", from: text)
                return nil
        }
    }

}

//---------------------------------------

fileprivate func failedToInitialize(_ typeString: String, from text: String) {
    Log.warning("Failed to initialize \(typeString) from string '\(text)'.")
}

//---------------------------------------
