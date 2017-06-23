/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        Emulateable Architecture
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------
/** Emulateable Architecture */

/** Execution Mode for Emulateable Architectures */
public enum ExecutionMode: String {
  case Default
  case Emulated
}

// ExecutionMode is initializable from a String
extension ExecutionMode: InitializableFromString {

  public init?(from text: String) {

    switch text {

      case "Default": 
        self = ExecutionMode.Default

      case "Emulated": 
        self = ExecutionMode.Emulated

      default:
        return nil

    }
  }
}

// Converting ExecutionMode to String
extension ExecutionMode: CustomStringConvertible {

  public var description: String {

    switch self {

      case ExecutionMode.Default: 
        return "Default"

      case ExecutionMode.Emulated: 
        return "Emulated"
       
    }
  }
}

/** Generic Interface for an Emulateable Architecture */
public protocol EmulateableArchitecture: Architecture {

  // Architecture State wil generate a Configuration Id
  func getConfigurationId(database: Database) -> Int

  // Architecture has an ExecutionMode
  var executionMode: Knob<ExecutionMode> { get }
}

//---------------------------------------
