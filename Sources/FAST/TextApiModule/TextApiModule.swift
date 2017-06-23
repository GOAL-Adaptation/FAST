/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic Text-based API SubSystem
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation

//---------------------------------------

/** Generic Text API:
 *
 *  IN:
 *   caller:          String           =>   Identifying the caller
 *   message:         Array<String>    =>   Text message split into words
 *   progressCounter: Int              =>   Current word being processed
 *   verbosityLevel:  VerbosityLevel   =>   Controls the verbosity of the reply
 *
 *  OUT:
 *   result: String
 */

//---------------------------------------

/** Verbosity levels */
public enum VerbosityLevel {
    case Verbose
    case Minimal
}

//---------------------------------------

/** A TextApi module is an object that has a Text API and is a collection over other TextApi modules ~ subModules */
public protocol TextApiModule: AnyObject {

    // module's name
    var name: String { get }

    // uncategorized subModules
    var subModules: [String : TextApiModule] { get set }

    // managing subModules
    func addSubModule(newModule: TextApiModule) -> ()

    func addSubModule(moduleName: String, newModule: TextApiModule) -> ()

    // The module's textApi
    func textApi(caller:            String, 
                 message:           Array<String>, 
                 progressIndicator: Int, 
                 verbosityLevel:    VerbosityLevel) -> String

    // The modul's internal textApi
    func internalTextApi(caller:            String, 
                         message:           Array<String>, 
                         progressIndicator: Int, 
                         verbosityLevel:    VerbosityLevel) -> String

    // Getting the status
    func getStatus() -> [String : Any]?

    // Getting internal status
    func getInternalStatus() -> [String : Any]?

    // Setting the status
    func setStatus(newSettings: [String : Any]) -> ()

    // Setting internal status
    func setInternalStatus(newSettings: [String : Any]) -> ()
}

//---------------------------------------

// Implementation of subModule management
public extension TextApiModule {

    /** TextApiModule: addSubModule */
    func addSubModule(newModule: TextApiModule) -> () {

        // register the new subModule
        self.subModules.updateValue(newModule, forKey: newModule.name)
    }

    /** TextApiModule: addSubModule */
    func addSubModule(newModules: [TextApiModule]) -> () {

        // register the new subModule
        for newModule in newModules {
            self.subModules.updateValue(newModule, forKey: newModule.name)
        }
    }

    /** TextApiModule: addSubModule */
    func addSubModule(moduleName: String, newModule: TextApiModule) -> () {

        // register the new subModule
        self.subModules.updateValue(newModule, forKey: moduleName)
    }
}

//---------------------------------------

// Implementation of the textApi's common part
public extension TextApiModule {

    /** TextApiModule: textApi */
    func textApi(caller:            String, 
                 message:           Array<String>, 
                 progressIndicator: Int, 
                 verbosityLevel:    VerbosityLevel) -> String {

            var result: String = ""
    
            // Valid reading of the message
            if let currentTerm = (message.count > progressIndicator ? message[progressIndicator] : nil) {
        
                // get / set status
                if message.count > progressIndicator + 1 {

                    if message[progressIndicator + 1] == "status" {

                        // get status
                        if currentTerm == "get" {

                            if let status = self.getStatus() {

                                // TODO status is Dictionary [String : Any], the new custom types eventhough extend String are not recognized as Strings by the 
                                // JSONSerializer (See Utils/JSON.swift), hence a JSON object cannot be created automatically. Find a way to hack it or use another library or custom implementation
                                return String(describing: status)

                            } else {

                                return ""
                            }

                        // set status
                        } else if currentTerm == "set" {
                            // TODO join the rest of message (if exists) into one string, convert that to JSON and convert that to Dictionary, then issue the setStatus 
                        }
                    }
                }
                // get / set status issued a return by now, so the message is different

                // Handling of a subModule
                if self.subModules.keys.contains(currentTerm) {

                    // Delegate Query to subApi
                    return self.subModules[ currentTerm ]!.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 1, verbosityLevel: verbosityLevel)

                // Internal handling of the message
                } else {

                    return self.internalTextApi(caller: caller, message: message, progressIndicator: progressIndicator, verbosityLevel: verbosityLevel)
                }

            // Invalid reading of the message
            } else if verbosityLevel == VerbosityLevel.Verbose {

                result = "Erroneus progressIndicator!"
            }

            return result
    }
}

//---------------------------------------

// Implementation of getting and setting the status
public extension TextApiModule {
   
    /** TextApiModule: get status as a dictionary */
    func getStatus() -> [String : Any]? {

        var result = [String : Any]()

        // Iterate through all subModules
        for (subModuleName, subModule) in subModules {
            // The subModule has returned a status
            if let subModuleStatus = subModule.getStatus() {
                result.updateValue(subModuleStatus, forKey: subModuleName)
            }
        }

        // Add internal status, if any
        if let internalStatus = getInternalStatus() {
            result.merge(with: internalStatus)
        }

        // If we obtained a meaningful status, then return it
        if result.count > 0 {
            return result
        } else {
            return nil
        }
    }
   
    /** TextApiModule: set status from a dictionary */
    func setStatus(newSettings: [String : Any]) -> () {

        // Looping through all keys
        newSettings.forEach { key, value in 

            // Submodule Status
            if let subModule = subModules[key] {

                // Downcasting is checked for errors
                if let newSubSettings = value as? [String : Any] {
                    subModule.setStatus(newSettings: newSubSettings)
                }

            // Internal Status
            } else {
                setInternalStatus(newSettings: [key : value] as [String : Any])
            }
        }   
    }
}

//---------------------------------------

// Default implementations to be overriden by Modules with internal structure
public extension TextApiModule {

    /** Default for TextApiModule: empty name */
    var name: String { return "" }

    /** Default for TextApiModule: no subModules */
    var subModules: [String : TextApiModule] { 
        get { 
            return [String : TextApiModule]() 
        } 
        set(x) {

        } 
    }

    /** Default for TextApiModule: no internal text API */
    func internalTextApi(caller:            String, 
                         message:           Array<String>, 
                         progressIndicator: Int, 
                         verbosityLevel:    VerbosityLevel) -> String {
                             return "Invalid message!"
                         }

    /** Default for TextApiModule: internal status not gettable */
    func getInternalStatus() -> [String : Any]? {
        return nil
    }

    /** Default for TextApiModule: internal status not settable */
    func setInternalStatus(newSettings: [String : Any]) -> () {}
}

//---------------------------------------
