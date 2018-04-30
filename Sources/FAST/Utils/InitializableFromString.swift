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

/** Extension for Bool */
extension Bool: InitializableFromString {

    public init?(from text: String) {
        if let value = Bool(text) {
            self = value
        } else {
            failedToInitialize("Bool", from: text)
            return nil
        }
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

/** Extension for UInt64 */
extension UInt64: InitializableFromString {

    public init?(from text: String) {
        if let value = UInt64(text) {
            self = value
        } else {
            failedToInitialize("UInt64", from: text)
            return nil
        }
    }

}

/** Extension for Double */
extension Double: InitializableFromString {

    public init?(from text: String) {
        if let value = Double(text) {
            self = value
        } else {
            failedToInitialize("Double", from: text)
            return nil
        }
    }

}

/** Extension for LinuxDvfsGovernor */
extension LinuxDvfsGovernor: InitializableFromString {

    public init?(from text: String) {
        switch text {
            case "performance": 
                self = .Performance
            case "userspace": 
                self = .Userspace
            default:
                failedToInitialize("linuxDvfsGovernor", from: text)
                return nil
        }
    }

}

/** Extension for ArchitectureName */
extension InitializationParameters.ArchitectureName : InitializableFromString {

    public init?(from text: String) {
        switch text {
            case "ArmBigLittle": 
                self = .ArmBigLittle
            case "XilinxZcu", "Xilinx": 
                self = .XilinxZcu
            default:
                failedToInitialize("ArchitectureName", from: text)
                return nil
        }
    }

}

/** Extension for ApplicationName */
extension InitializationParameters.ApplicationName : InitializableFromString {

    public init?(from text: String) {
        switch text {
            case "radar": 
                self = .radar
            case "x264": 
                self = .x264
            case "capsule": 
                self = .capsule
            case "incrementer": 
                self = .incrementer
            default:
                failedToInitialize("ApplicationName", from: text)
                return nil
        }
    }

}

/** LoggerAPI LoggerMessageType */
extension LoggerMessageType: InitializableFromString {

    public init?(from text: String) {
        switch text {
            case "Entry":
                self = .entry
            case "Exit":
                self = .exit
            case "Debug":
                self = .debug
            case "Verbose":
                self = .verbose
            case "Info":
                self = .info
            case "Warning":
                self = .warning
            case "Error":
                self = .error
            default:
                failedToInitialize("LoggerMessageType", from: text)
                return nil
        }
    }

}

//---------------------------------------

fileprivate func failedToInitialize(_ typeString: String, from text: String) {
    Log.warning("Failed to initialize \(typeString) from string '\(text)'.")
}

//---------------------------------------
