/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Knob is a TextApiModule
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

/** Extending a Knob to be a TextApiModule */
extension Knob: TextApiModule {

    /** Knob: initialize from external configuration */
    public convenience init(from key: [String], or defaultValue: T, preSetter: @escaping Action = {_,_ in }, postSetter: @escaping Action = {_,_ in }) {

        // Attempt to get initial value
        let newValue = initialize(type: T.self, from: key)

        // Initialize the knob if initial value and name have been obtained successfully
        if let name  = key.last {
            if let value = newValue {
                self.init(name, value, preSetter, postSetter)
            } else { // Failed to initialize the knob
                Log.verbose("Failed to initailze knob of type \(T.self) from key: \(key). Using default value: \(defaultValue).")
                self.init(name, defaultValue, preSetter, postSetter)
            }
        }
        else {
            let failMessage = "Cannot initailze knob (of type \(T.self)) from an empty key, as the last entry in the key is used as the knob name."
            Log.error(failMessage)
            fatalError(failMessage)
        }

    }

    /** Knob: initialize from external configuration */
    public convenience init(name: String, from key: [String], or defaultValue: T, preSetter: @escaping Action = {_,_ in }, postSetter: @escaping Action = {_,_ in }) {
        self.init(from: key.appended(with: name), or: defaultValue, preSetter: preSetter, postSetter: postSetter)
    }

    /** Knob: internal Text API */
    public func internalTextApi(caller:            String, 
                                message:           Array<String>, 
                                progressIndicator: Int, 
                                verbosityLevel:    VerbosityLevel) -> String {

            var result: String = ""
    
            // Get the value
            if (message[progressIndicator] == "get") {
            
                result = String(describing: self.get())

                // Creating a verbose answer
                if verbosityLevel == VerbosityLevel.Verbose {
                    result = self.name + " is set to " + result + "."
                }

            // Set the value
            } else if (message[progressIndicator] == "set") && (message[progressIndicator + 1] == "to") {
            
                // Check if T is initializable from a string
                if  let TInitializable = T.self as? InitializableFromString.Type, 
                    let newValueTry    = TInitializable.init(from: message[ progressIndicator + 2]),
                    let newValue       = newValueTry as? T {

                        self.set(newValue)

                        // Creating a verbose answer
                        if verbosityLevel == VerbosityLevel.Verbose {
                            result = "Attempting to set " + self.name + " to " + message[ progressIndicator + 2] + "."
                        }

                } else if (verbosityLevel == VerbosityLevel.Verbose) {

                    result = self.name + ": Could not set " + self.name + " to " + message[ progressIndicator + 2] + "."

                }

            // Invalid message
            } else if (verbosityLevel == VerbosityLevel.Verbose) {

                result = self.name + ": invalid message received."

            }

            return result;
    }

    /** Knob: get status as a dictionary */
    public func getInternalStatus() -> [String : Any]? {
        return ["value" : self.value]
    }

    /** Knob: set status from a dictionary */
    public func setInternalStatus(newSettings: [String : Any]) -> () {
        if let newValue = newSettings[ self.name ] {
            self.setter(newValue)
        }
    }

}

//---------------------------------------
