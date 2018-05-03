//-------------------------------

import Foundation
import LoggerAPI

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","emulator","database"]

//-------------------------------

public protocol Database : TextApiModule {

    func getCurrentConfigurationId(application: Application) -> Int

    func getCurrentConfigurationId(architecture: Architecture) -> Int

    func getReferenceApplicationConfigurationID(application: String) -> Int

    func getReferenceSystemConfigurationID(architecture: String) -> Int

    func readDelta(
        application: String, 
        architecture: String, 
        appCfg applicationConfigurationID: Int, 
        appInp applicationInputID: Int, 
        sysCfg systemConfigurationID: Int, 
        processing progressCounter: Int) 
        -> (Double, Double)

}

//-------------------------------

// /** Select which input to read in Tape mode */
// func getInputNumberToRead(inputID: Int, maximalInputID: Int, warmupInputs: Int) -> Int {
      
//   // FIXME Add support for warmup iterations
//   assert(warmupInputs == 0)

//   // Assume the trace is [0,1,2]. To simulate an execution of length 8,
//   // we repeat the trace, reversing it at every repetition to ensure that
//   // consecutive readings are close, as follows:
//   // [0,1,2, 3,4,5, 6,7] // Emulated execution indices
//   // [0,1,2][2,1,0][0,1] // Traced execution indices
//   let traceSize = maximalInputID + 1
//   // Shift the inputID to the range 0 ..< traceSize
//   let inputIdShifted = inputID % traceSize
//   // How many times has the traced data been repeated so far?
//   let repetitionNumber = inputID / traceSize
//   // Is the current repetition reversed or not
//   let isRepetitionReversed = repetitionNumber % 2 == 1
//   // If we are in a reversed repetition, return (maximalInputID - inputIdShifted), otherwise return inputIdShifted.
//   let remappedInputNumber = isRepetitionReversed ? maximalInputID - inputIdShifted : inputIdShifted
//   assert(remappedInputNumber <= maximalInputID)

//   return remappedInputNumber

// }

//-------------------------------

/** Database Knobs */
class DatabaseKnobs: TextApiModule {

    let name = "databaseKnobs"
    var subModules = [String : TextApiModule]()

    // Database Knobs
    var readingMode = Knob(name: "readingMode", from: key, or: ReadingMode.Statistics)

    init() {
        self.addSubModule(newModule: readingMode)
    }

}

enum ReadingMode: String {
  case Statistics
  case Tape
}

extension ReadingMode: InitializableFromString {

  init?(from text: String) {

    switch text {

      case "Statistics": 
        self = ReadingMode.Statistics

      case "Tape": 
        self = ReadingMode.Tape

      default:
        return nil

    }
  }
}

extension ReadingMode: CustomStringConvertible {

  var description: String {

    switch self {

      case ReadingMode.Statistics: 
        return "Statistics"

      case ReadingMode.Tape: 
        return "Tape"
       
    }
  }
}

//-------------------------------