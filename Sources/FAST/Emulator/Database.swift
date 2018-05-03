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

/** Select which input to read in Tape mode */
func getInputNumberToRead(inputID: Int, maximalInputID: Int, warmupInputs: Int) -> Int {
    
    // FIXME Add support for warmup iterations
    assert(warmupInputs == 0)

    // A recorded input is directly read
    if inputID <= maximalInputID {
        return inputID

    // A "non-taped" input is randomly emulated from the "non-warmup" segment
    // TODO check if range is non-empty warmupInputs + 1 < maximalInputID
    } else {
        let extraInputs = inputID - maximalInputID
        let offsetRange = maximalInputID - (warmupInputs + 1)

        // offset \in 1 .. offsetRange
        let offset = (extraInputs % offsetRange == 0) ? offsetRange : (extraInputs % offsetRange)

        // Backward / Forward
        enum ReadingDirection {
        case Backward
        case Forward
        // NOTE extraInputs >= 1 is guaranteed
        }

        let readDirection: ReadingDirection
        
        readDirection = ( ((extraInputs - 1) / offsetRange) % 2 == 0 ) ? ReadingDirection.Backward : ReadingDirection.Forward

        // Read the tape back and forth

        // Backward reading from [maximalInputID]   - 1   to [warmupInputs + 1]
        // Forward  reading from [warmupInputs + 1] + 1   to [maximalInputID]
        return (readDirection == ReadingDirection.Backward) ? (maximalInputID - offset) : ((warmupInputs + 1) + offset)
    }

}

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