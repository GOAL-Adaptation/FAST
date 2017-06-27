/*
 *  pemu: Database driven emulator
 *
 *        Xilinx ZCU 102 Architecture
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import Foundation

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
    var maximalCoreFrequency = Knob(name: "maximalCoreFrequency", from: key, or: 1199999)

    init() {
        self.addSubModule(newModules: [availableCores, maximalCoreFrequency])
    }
}

/** Xilinx ZCU 102 System Configuration Knobs */
class XilinxZcuSystemConfigurationKnobs: TextApiModule {

    let name = "systemConfigurationKnobs"
    var subModules = [String : TextApiModule]()

    // System Configuration Knobs
    var utilizedCores         = Knob(name: "utilizedCores",         from: key, or: 4)
    var utilizedCoreFrequency = Knob(name: "utilizedCoreFrequency", from: key, or: 1199999)

    init() {
        self.addSubModule(newModules: [utilizedCores, utilizedCoreFrequency])
    }
}

/** Xilinx ZCU 102 Resource Usage Policy Module */
class XilinxZcuResourceUsagePolicyModule: TextApiModule {

    let name = "resourceUsagePolicyModule"
    var subModules = [String : TextApiModule]()

    // System Configuration Knobs
    var maintainedState = XilinxZcuSystemConfigurationKnobs()
    var policy          = Knob(name: "policy", from: key, or: ResourceUsagePolicy.Simple)

    init() {
        self.addSubModule(moduleName: "maintainedState", newModule: maintainedState)
        self.addSubModule(newModule: policy)
    }
}

//-------------------------------
// TODO maintained state not implemented

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
    typealias ResourceUsagePolicyModuleType = XilinxZcuResourceUsagePolicyModule

    var scenarioKnobs             = ScenarioKnobsType()
    var systemConfigurationKnobs  = SystemConfigurationKnobsType()
    var resourceUsagePolicyModule = ResourceUsagePolicyModuleType()

    var executionMode: Knob<ExecutionMode>

    var actuationPolicy = Knob(name: "actuationPolicy", from: key, or: ActuationPolicy.NoActuation)

    func actuate() -> Void {

        // TODO add system calls here, the C code to be translated is included
        //  or one might create a small C library implementing actuate platform actuation and that'd be coupled along as energymon

/*
        // Configure the Hardware to use the number of cores dictated by the system configuration knobs
        static void configureCoreUtilization(uint64_t utilizedCores) {

            int returnValueOfSysCall = 0;
            char command[4096];

            char * coreMask;

            switch(utilizedCores) {
                case 1:
                    coreMask = "0"; break;
                case 2:
                    coreMask = "0,1"; break;
                case 3:
                    coreMask = "0,1,2"; break;
                case 4:
                    coreMask = "0,1,2,3"; break;
            }

            sprintf(command,
                    "ps -eLf | awk '(/%d/) && (!/awk/) {print $4}' | xargs -n1 taskset -c -p %s > /dev/null",
                    getpid(), coreMask);

            printf("Applying core allocation: %s\n", command);

            if (applySysCalls == 1) {

                returnValueOfSysCall = system(command);

                if (returnValueOfSysCall != 0) {
                    fprintf(stderr, "ERROR running taskset: %d\n",
                            returnValueOfSysCall);
                }
            }
        }

        // Configure the Hardware to use the core frequencies dictated by the system configuration knobs
        static void configureCoreFrequencies(uint64_t utilizedCoreFrequency) {

            int returnValueOfSysCall = 0;
            char command[4096];

            // NOTE: All cores share a clock so if we set cpu0, the other 3 change too.
            sprintf(command,
                    "echo %" PEMU_UINT64_T_PRINT " > /sys/devices/system/cpu/cpu0/cpufreq/%s",
                    utilizedCoreFrequency, dvfsFile);
            printf("Applying CPU frequency: %s\n", command);
            
            if (applySysCalls == 1) {
                
                returnValueOfSysCall = system(command);
                
                if (returnValueOfSysCall != 0) {
                    fprintf(stderr, "ERROR setting frequencies: %d\n",
                        returnValueOfSysCall);
                }             
            }
        }
*/

    }

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
                    // TODO check application exictence and conformance, Emulator should detect app input
                    let emulator = Emulator(application: Runtime.application! as! EmulateableApplication, applicationInput: 0, architecture: self)

                    // Assign it as monitors (Reference Counting will keep it alive as long as this is not changed)
                    self.clockMonitor  = emulator
                    self.energyMonitor = emulator
            }
        }
    }   

    /** Initialize the architecture */
    required init() {
        // FIXME initialize exectuionMode so that the callback function can be passed. This is very stupid
        self.executionMode = Knob(name: "executionMode", from: key, or: ExecutionMode.Default)
        // This is the real init
        self.executionMode = Knob(name: "executionMode", from: key, or: ExecutionMode.Default, preSetter: self.changeExecutionMode)
        // This is stupid too
        if executionMode.get() == ExecutionMode.Emulated {
            changeExecutionMode(oldMode: ExecutionMode.Default, newMode: ExecutionMode.Emulated)
        }
        self.addSubModule(newModules: [scenarioKnobs, systemConfigurationKnobs, resourceUsagePolicyModule, executionMode, actuationPolicy])
        self.registerSystemMeasures()
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
            }
             
            return result;
    }

    /**Xilinx ZCU 102: get status as a dictionary */
    public func getInternalStatus() -> [String : Any]? {
        return ["energy" : self.energyMonitor.readEnergy(), "time" : self.clockMonitor.readClock()]
    }

    /** Enforce the active Resource Usage Policy and ensure Consistency between Scenario and System Configuration Knobs */
    func enforceResourceUsageAndConsistency() -> Void {

        // Store the requested state
        struct RequestedState {
            let utilizedCores: Int
            let utilizedCoreFrequency: Int
        }

        let requestedState = RequestedState(utilizedCores:         systemConfigurationKnobs.utilizedCores.get(),
                                            utilizedCoreFrequency: systemConfigurationKnobs.utilizedCoreFrequency.get())

        //-------------------------------
        // Maximal Resource Usage Policy
        //
        // Maxes out system utilization on one type of cores, primarily on big
        if resourceUsagePolicyModule.policy.get() == ResourceUsagePolicy.Maximal {
        
            systemConfigurationKnobs.utilizedCores.set(                 scenarioKnobs.availableCores.get() )
            systemConfigurationKnobs.utilizedCoreFrequency.set(   scenarioKnobs.maximalCoreFrequency.get() )

            // Report if policy was applied
            if ((systemConfigurationKnobs.utilizedCores.get()         !=         requestedState.utilizedCores) ||
                (systemConfigurationKnobs.utilizedCoreFrequency.get() != requestedState.utilizedCoreFrequency) ){

                    // TODO: add

            }

        //-------------------------------
        // Maintained Resource Usage Policy
        //
        // Maintains a certain resource usage, able to recoup after multiple perturbations
        } else if resourceUsagePolicyModule.policy.get() == ResourceUsagePolicy.Maintain {

            // Enforce the `maintained state`
            systemConfigurationKnobs.utilizedCores.set(                      resourceUsagePolicyModule.maintainedState.utilizedCores.get())
            systemConfigurationKnobs.utilizedCoreFrequency.set(      resourceUsagePolicyModule.maintainedState.utilizedCoreFrequency.get())

            // Report if policy was applied
            if ((systemConfigurationKnobs.utilizedCores.get()         !=         requestedState.utilizedCores) ||
                (systemConfigurationKnobs.utilizedCoreFrequency.get() != requestedState.utilizedCoreFrequency) ){

                    // TODO: add

            }

        }

        //--------------------------------------------------------------
        // Policies
        //
        // NOTE: order matters!

        //-------------------------------
        // Consistency Policy (policy #1)
        //
        // Establish consistency if exists systemConfigurationKnob that violates its constraining scenarioKnob

        if (systemConfigurationKnobs.utilizedCores.get() > scenarioKnobs.availableCores.get()) {
            systemConfigurationKnobs.utilizedCores.set(   scenarioKnobs.availableCores.get())

        }


        if (systemConfigurationKnobs.utilizedCoreFrequency.get() > scenarioKnobs.maximalCoreFrequency.get()) {
            systemConfigurationKnobs.utilizedCoreFrequency.set(   scenarioKnobs.maximalCoreFrequency.get())

        }

        //-------------------------------
        //
        // Some assertions that point to invalid configurations (won't happen during normal use)
        assert( systemConfigurationKnobs.utilizedCores.get() > 0 );
    }
}

//-------------------------------
