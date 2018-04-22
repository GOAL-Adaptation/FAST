/*
 *  pemu: Database driven emulator
 *
 *        Xilinx ZCU 102 Architecture
 *
 *  authors: Ferenc A Bartha, Adam Duracz
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import Foundation
import LoggerAPI

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","xilinxZcu"]

//-------------------------------

/** Xilinx ZCU 102 Scenario Knobs */
class XilinxZcuScenarioKnobs: TextApiModule {

    let name = "scenarioKnobs"
    var subModules = [String : TextApiModule]()

    // Scenario Knobs
    var availableCores       = Knob(name: "availableCores",       from: key, or: 4)
    var maximalCoreFrequency = Knob(name: "maximalCoreFrequency", from: key, or: 1200)

    init() {
        self.addSubModule(newModules: [availableCores, maximalCoreFrequency])
    }
}

/** Xilinx ZCU 102 System Configuration Knobs */
class XilinxZcuSystemConfigurationKnobs: TextApiModule {

    let name = "systemConfigurationKnobs"
    var subModules = [String : TextApiModule]()

    // System Configuration Knobs
    var utilizedCores         : Knob<Int>
    var utilizedCoreFrequency : Knob<Int>

    init(actuationPolicyKnob: Knob<ActuationPolicy>) {
        utilizedCores         = Knob(name: "utilizedCores",         from: key, or: 4)
        utilizedCoreFrequency = Knob(name: "utilizedCoreFrequency", from: key, or: 1200)
        #if os(Linux)
          utilizedCores.overridePostSetter(newPostSetter: { _, newValue in
            actuateLinuxUtilizedCoresSystemConfigurationKnob(actuationPolicy: actuationPolicyKnob.get(), utilizedCores: newValue)
          })
          utilizedCoreFrequency.overridePostSetter(newPostSetter: { _, newUtilizedCoreFrequency in
            let newUtilizedCoreFrequencyInHz = newUtilizedCoreFrequency * 1000 // Convert from MHz (which is used in the intent specification and default value) to Hz
            actuateLinuxUtilizedCoreFrequencySystemConfigurationKnob(actuationPolicy: actuationPolicyKnob.get(), utilizedCoreFrequency: newUtilizedCoreFrequencyInHz)
          })
        #endif

        self.addSubModule(newModules: [utilizedCores, utilizedCoreFrequency])
    }

}

/** Xilinx ZCU 102 Architecture */
class XilinxZcu: Architecture,
                 ClockAndEnergyArchitecture,
                 ScenarioKnobEnrichedArchitecture,
                 RealArchitecture,
                 EmulateableArchitecture {

    let name = "XilinxZcu"

    // Use the default System Measures
    var clockMonitor:  ClockMonitor  = DefaultClockMonitor()
    var energyMonitor: EnergyMonitor = CEnergyMonitor()

    var subModules = [String : TextApiModule]()

    typealias ScenarioKnobsType             = XilinxZcuScenarioKnobs
    typealias SystemConfigurationKnobsType  = XilinxZcuSystemConfigurationKnobs

    var scenarioKnobs             = ScenarioKnobsType()
    var systemConfigurationKnobs  : XilinxZcuSystemConfigurationKnobs

    var executionMode: Knob<ExecutionMode>

    unowned var runtime: Runtime

    var actuationPolicy = Knob(name: "actuationPolicy", from: key, or: ActuationPolicy.Actuate)

    /** Changing Execution Mode */
    public func changeExecutionMode(oldMode: ExecutionMode, newMode: ExecutionMode) -> Void {

        // Change applies only if the value has changed
        if oldMode != newMode {
            switch newMode {

                // Use the default System Measures
                case ExecutionMode.Default:
                    self.clockMonitor  = DefaultClockMonitor()
                    self.energyMonitor = CEnergyMonitor()

                // Use emulated system Measures
                case ExecutionMode.Emulated:
                    // Create an emulator
                    // TODO check application exictence and conformance
                    let emulator = Emulator(application: runtime.application! as! EmulateableApplication, 
                                            applicationInput: 1, // FIXME: set to 1 for now, Emulator should detect app input stream 
                                            architecture: self, 
                                            runtime: runtime)

                    // Assign it as monitors (Reference Counting will keep it alive as long as this is not changed)
                    self.clockMonitor  = emulator
                    self.energyMonitor = emulator
            }
            Log.info("Xilinx execution mode set to \(newMode): clockMonitor = \(clockMonitor) energyMonitor = \(energyMonitor)")
        }
    }

    /** Initialize the architecture */
    required init(runtime: Runtime) {
        self.runtime = runtime
        // FIXME initialize exectuionMode so that the callback function can be passed. This is very stupid
        self.executionMode = Knob(name: "executionMode", from: key, or: ExecutionMode.Default)
        self.systemConfigurationKnobs  = XilinxZcuSystemConfigurationKnobs(actuationPolicyKnob: actuationPolicy)
        self.executionMode = Knob(name: "executionMode", from: key, or: ExecutionMode.Default, preSetter: self.changeExecutionMode)
        // This is stupid too
        if executionMode.get() == ExecutionMode.Emulated {
            changeExecutionMode(oldMode: ExecutionMode.Default, newMode: ExecutionMode.Emulated)
        }
        self.addSubModule(newModules: [scenarioKnobs, systemConfigurationKnobs, executionMode, actuationPolicy])
        self.registerSystemMeasures(runtime: runtime)
    }

    /** Internal text API for Xilinx ZCU 102
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

    /**Xilinx ZCU 102: get status as a dictionary */
    public func getInternalStatus() -> [String : Any]? {
        return ["energy" : self.energyMonitor.readEnergy(), "time" : self.clockMonitor.readClock()]
    }

}

//-------------------------------
