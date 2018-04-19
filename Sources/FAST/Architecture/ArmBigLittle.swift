/*
 *  pemu: Database driven emulator
 *
 *        ARM bigLITTLE Architecture
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import Foundation
import LoggerAPI

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","armBigLittle"]

//-------------------------------

// CoreMask translations
fileprivate let coremask: [String : (Int, Int)] = [
    "0x1"  : (0, 1),
    "0x3"  : (0, 2),
    "0x7"  : (0, 3),
    "0xF"  : (0, 4),
    "0x10" : (1, 0),
    "0x30" : (2, 0),
    "0x70" : (3, 0),
    "0xF0" : (4, 0)
]

//-------------------------------

/** ARM bigLITTLE Scenario Knobs */
class ArmBigLittleScenarioKnobs: TextApiModule {

    let name = "scenarioKnobs"
    var subModules = [String : TextApiModule]()

    // Scenario Knobs
    var availableBigCores          = Knob(name: "availableBigCores",          from: key, or:       4)
    var availableLittleCores       = Knob(name: "availableLittleCores",       from: key, or:       4)
    var maximalBigCoreFrequency    = Knob(name: "maximalBigCoreFrequency",    from: key, or: 2000000)
    var maximalLittleCoreFrequency = Knob(name: "maximalLittleCoreFrequency", from: key, or: 1400000)

    unowned let runtime: Runtime

    /*
     *  - Limited availablility Scenario Knobs (available when utilizedBigCores > 0 OR utilizedLittleCores > 0) AND (utilizedBigCores == 0 OR utilizedLittleCores == 0)
     *
     *    - availableCores
     *    - maximalCoreFrequency
     */
    func internalTextApi(caller:            String,
                        message:           Array<String>,
                        progressIndicator: Int,
                        verbosityLevel:    VerbosityLevel) -> String {

        var result: String = ""

        let currentArchitecture = runtime.architecture as! ArmBigLittle

        if message[progressIndicator] == "availableCores" {

            if (currentArchitecture.systemConfigurationKnobs.utilizedBigCores.get() > 0 && currentArchitecture.systemConfigurationKnobs.utilizedLittleCores.get() == 0) {

                result = availableBigCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 1, verbosityLevel: verbosityLevel)

            } else if (currentArchitecture.systemConfigurationKnobs.utilizedBigCores.get() == 0 && currentArchitecture.systemConfigurationKnobs.utilizedLittleCores.get() > 0) {

                result = availableLittleCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 1, verbosityLevel: verbosityLevel)
            }

        } else if message[progressIndicator] == "maximalCoreFrequency" {

            if (currentArchitecture.systemConfigurationKnobs.utilizedBigCores.get() > 0 && currentArchitecture.systemConfigurationKnobs.utilizedLittleCores.get() == 0) {

                result = maximalBigCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 1, verbosityLevel: verbosityLevel)

            } else if (currentArchitecture.systemConfigurationKnobs.utilizedBigCores.get() == 0 && currentArchitecture.systemConfigurationKnobs.utilizedLittleCores.get() > 0) {

                result = maximalLittleCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 1, verbosityLevel: verbosityLevel)
            }
        } else {

            // TODO add error msg based on verbosity level
        }

        return result
    }

    init(runtime: Runtime) {
        self.runtime = runtime
        self.addSubModule(newModules: [availableBigCores, availableLittleCores, maximalBigCoreFrequency, maximalLittleCoreFrequency])
    }
}

/** ARM bigLITTLE System Configuration Knobs */
class ArmBigLittleSystemConfigurationKnobs: TextApiModule {

    let name = "systemConfigurationKnobs"
    var subModules = [String : TextApiModule]()

    // System Configuration Knobs
    var utilizedBigCores            : Knob<Int>
    var utilizedLittleCores         : Knob<Int>
    var utilizedBigCoreFrequency    : Knob<Int>
    var utilizedLittleCoreFrequency : Knob<Int>

    /*
     *  - Limited availablility & Derived System Configuration Knobs (available when utilizedBigCores > 0 OR utilizedLittleCores > 0) AND (utilizedBigCores == 0 OR utilizedLittleCores == 0)
     *
     *    Limited Availablility System Configuration Knobs
     *    - utilizedCores
     *    - utilizedCoreFrequency
     *
     *    Derived System Configuration Knobs
     *    - utilizedCoreMask
     *    - utilizedCoreFrequencies
     */
    func internalTextApi(caller:            String,
                        message:           Array<String>,
                        progressIndicator: Int,
                        verbosityLevel:    VerbosityLevel) -> String {

        var result: String = ""

        if message[progressIndicator + 1] == "utilizedCores" {

            if (self.utilizedBigCores.get() > 0 && self.utilizedLittleCores.get() == 0) {

                result = self.utilizedBigCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

            } else if (self.utilizedBigCores.get() == 0 && self.utilizedLittleCores.get() > 0) {

                result = self.utilizedLittleCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)
            }

        } else if message[progressIndicator + 1] == "utilizedCoreFrequency" {

            if (self.utilizedBigCores.get() > 0 && self.utilizedLittleCores.get() == 0) {

                result = self.utilizedBigCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

            } else if (self.utilizedBigCores.get() == 0 && self.utilizedLittleCores.get() > 0) {

                result = self.utilizedLittleCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)
            }

        // Derived System Configuration Knobs
        } else if message[progressIndicator + 1] == "utilizedCoreMask" {

            // TODO

        } else if message[progressIndicator + 1] == "utilizedCoreFrequencies" {

            // TODO

        } else {

                // TODO add error msg based on verbosity level
        }

        return result
    }

    init() {
        utilizedBigCores            = Knob(name: "utilizedBigCores",            from: key, or:       4)
        utilizedLittleCores         = Knob(name: "utilizedLittleCores",         from: key, or:       0)
        utilizedBigCoreFrequency    = Knob(name: "utilizedBigCoreFrequency",    from: key, or: 2000000)
        utilizedLittleCoreFrequency = Knob(name: "utilizedLittleCoreFrequency", from: key, or:  200000)

        self.addSubModule(newModules: [utilizedBigCores, utilizedLittleCores, utilizedBigCoreFrequency, utilizedLittleCoreFrequency])
    }

}

/** ARM bigLITTLE Architecture */
class ArmBigLittle: Architecture,
                    ClockAndEnergyArchitecture,
                    ScenarioKnobEnrichedArchitecture,
                    RealArchitecture,
                    EmulateableArchitecture {

    let name = "ARM-big.LITTLE" // TODO in DB is "ARM-big.LITTLE"

    // Use the default System Measures
    var clockMonitor:  ClockMonitor  = DefaultClockMonitor()
    var energyMonitor: EnergyMonitor = CEnergyMonitor()

    let otherCoreFrequency = 200000

    var subModules = [String : TextApiModule]()

    typealias ScenarioKnobsType             = ArmBigLittleScenarioKnobs
    typealias SystemConfigurationKnobsType  = ArmBigLittleSystemConfigurationKnobs

    var scenarioKnobs             : ScenarioKnobsType
    var systemConfigurationKnobs  : SystemConfigurationKnobsType

    var executionMode: Knob<ExecutionMode>

    unowned var runtime: Runtime

    var actuationPolicy = Knob(name: "actuationPolicy", from: key, or: ActuationPolicy.NoActuation)

    /** Changing Execution Mode */
    public func changeExecutionMode(oldMode: ExecutionMode, newMode: ExecutionMode) -> Void {

        // Change applies only if the value has changed
        if oldMode != newMode {
            switch newMode {

                // Use the default System Measures
                case ExecutionMode.Default:
                    self.clockMonitor  = DefaultClockMonitor()
                    self.energyMonitor = CEnergyMonitor()

                    self.subModules = [:]
                    self.addSubModule(newModules: [self.scenarioKnobs, self.systemConfigurationKnobs, self.executionMode, self.actuationPolicy])

                // Use emulated system Measures
                case ExecutionMode.Emulated:
                    // Create an emulator
                    // TODO check application exictence and conformance
                    let emulator = Emulator(application: runtime.application! as! EmulateableApplication, 
                                            applicationInput: 1, // FIXME: set to 1 for now; Emulator should detect app input stream
                                            architecture: self, 
                                            runtime: runtime)

                    // Assign it as monitors (Reference Counting will keep it alive as long as this is not changed)
                    self.clockMonitor  = emulator
                    self.energyMonitor = emulator

                    self.subModules = [:]
                    self.addSubModule(newModules: [self.scenarioKnobs, self.systemConfigurationKnobs, self.executionMode, self.actuationPolicy, emulator])
            }

            Log.verbose("Changed architecture execution mode to \(newMode).")
        }
    }

    /** Initialize the architecture */
    required init(runtime: Runtime) {
        self.runtime = runtime
        self.scenarioKnobs = ScenarioKnobsType(runtime: runtime)
        // FIXME initialize exectuionMode so that the callback function can be passed. This is very stupid
        self.executionMode = Knob(name: "executionMode", from: key, or: ExecutionMode.Default)
        self.systemConfigurationKnobs  = SystemConfigurationKnobsType()
        self.executionMode = Knob(name: "executionMode", from: key, or: ExecutionMode.Default, preSetter: self.changeExecutionMode)
        // This is stupid too
        if executionMode.get() == ExecutionMode.Emulated {
            changeExecutionMode(oldMode: ExecutionMode.Default, newMode: ExecutionMode.Emulated)
        } else {
            changeExecutionMode(oldMode: ExecutionMode.Emulated, newMode: ExecutionMode.Default)
        }

        Log.info("Initialized architecture \(name) in \(executionMode.get()) mode.")

        self.addSubModule(newModules: [scenarioKnobs, systemConfigurationKnobs, executionMode, actuationPolicy])
        self.registerSystemMeasures(runtime: runtime)
    }

    /** Internal text API for ARM bigLITTLE
     *
     *  - System measures
     *    - energy
     *    - time
     */
    func internalTextApi(caller:            String,
                         message:           Array<String>,
                         progressIndicator: Int,
                         verbosityLevel:    VerbosityLevel) -> String {

            var result: String = ""

            // System measures
            if message[progressIndicator] == "energy" && message[progressIndicator + 1] == "get" {

                result = String(self.energyMonitor.readEnergy())

                if verbosityLevel == VerbosityLevel.Verbose {
                    result = "Energy counter is: " + result + " microjoules."
                }

            } else if message[progressIndicator] == "time" && message[progressIndicator + 1] == "get" {

                result = String(self.clockMonitor.readClock())

                if verbosityLevel == VerbosityLevel.Verbose {
                    result = "Clock shows: " + result + "."
                }
            } else {

                // TODO add error msg based on verbosity level
            }

            return result;
    }

    /** ARM bigLITTLE: get status as a dictionary */
    public func getInternalStatus() -> [String : Any]? {
        return ["energy" : self.energyMonitor.readEnergy(), "time" : self.clockMonitor.readClock()]
    }

}

//-------------------------------
