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

    init() {
        self.addSubModule(newModules: [availableBigCores, availableLittleCores, maximalBigCoreFrequency, maximalLittleCoreFrequency])
    }
}

/** ARM bigLITTLE System Configuration Knobs */
class ArmBigLittleSystemConfigurationKnobs: TextApiModule {

    let name = "systemConfigurationKnobs"
    var subModules = [String : TextApiModule]()

    // System Configuration Knobs
    var utilizedBigCores            = Knob(name: "utilizedBigCores",            from: key, or:       4)
    var utilizedLittleCores         = Knob(name: "utilizedLittleCores",         from: key, or:       0)
    var utilizedBigCoreFrequency    = Knob(name: "utilizedBigCoreFrequency",    from: key, or: 2000000)
    var utilizedLittleCoreFrequency = Knob(name: "utilizedLittleCoreFrequency", from: key, or:  200000)

    init() {
        self.addSubModule(newModules: [utilizedBigCores, utilizedLittleCores, utilizedBigCoreFrequency, utilizedLittleCoreFrequency])
    }
}

/** ARM bigLITTLE Resource Usage Policy Module */
class ArmBigLittleResourceUsagePolicyModule: TextApiModule {

    let name = "resourceUsagePolicyModule"
    var subModules = [String : TextApiModule]()

    // System Configuration Knobs
    var maintainedState = ArmBigLittleSystemConfigurationKnobs()
    var policy          = Knob(name: "policy", from: key, or: ResourceUsagePolicy.Simple)

    init() {
        self.addSubModule(moduleName: "maintainedState", newModule: maintainedState)
        self.addSubModule(newModule: policy)
    }
}

//-------------------------------
// TODO maintained state not implemented

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
    typealias ResourceUsagePolicyModuleType = ArmBigLittleResourceUsagePolicyModule

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
            static void configureCoreUtilization(uint64_t utilizedBigCores,
                                                uint64_t utilizedLittleCores) {

                int returnValueOfSysCall = 0;
                char command[4096];

                sprintf(command,
                        "ps -eLf | awk '(/%d/) && (!/awk/) {print $4}' | xargs -n1 taskset -p %s > /dev/null",
                        getpid(), armBigLittleKnob(SystemConfiguration, "utilizedCoreMask", "get", "", Simple));

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
            static void configureCoreFrequencies(uint64_t utilizedBigCoreFrequency,
                                                uint64_t utilizedLittleCoreFrequency) {

                int returnValueOfSysCall = 0;
                char command[4096];

                unsigned int i = 0;
                char* freqs = armBigLittleKnob(SystemConfiguration, "utilizedCoreFrequencies", "get", "", Simple);
                char* freq = strtok(freqs, ",");
                while (freq != NULL) {
                    if (freq[0] != '-') {
                        sprintf(command,
                                "echo %lu > /sys/devices/system/cpu/cpu%u/cpufreq/%s",
                                strtoul(freq, NULL, 0), i, dvfsFile);
                        printf("Applying CPU frequency: %s\n", command);

                        if (applySysCalls == 1) {

                            returnValueOfSysCall = system(command);

                            if (returnValueOfSysCall != 0) {
                                fprintf(stderr, "ERROR setting frequencies: %d\n",
                                        returnValueOfSysCall);
                            }

                        }

                    }
                    freq = strtok(NULL, ",");
                    i++;
                }
                free(freqs);
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

    /** Internal text API for ARM bigLITTLE
     *  - Limited availablility knobs (available when utilizedBigCores > 0 OR utilizedLittleCores > 0) AND (utilizedBigCores == 0 OR utilizedLittleCores == 0)
     *
     *    Scenario Knobs
     *    - availableCores
     *    - maximalCoreFrequency
     *
     *    System Configuration Knobs
     *    - utilizedCores
     *    - utilizedCoreFrequency
     *
     * - Derived knobs
     *
     *   SystemConfiguration Knobs
     *   - utilizedCoreMask
     *   - utilizedCoreFrequencies
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
    
            // Limited availability Scenario Knobs
            if message[progressIndicator] == "scenarioKnobs" {

                if message[progressIndicator + 1] == "availableCores" {

                    if (systemConfigurationKnobs.utilizedBigCores.get() > 0 && systemConfigurationKnobs.utilizedLittleCores.get() == 0) {

                        result = scenarioKnobs.availableBigCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    } else if (systemConfigurationKnobs.utilizedBigCores.get() == 0 && systemConfigurationKnobs.utilizedLittleCores.get() > 0) {

                        result = scenarioKnobs.availableLittleCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    }

                } else if message[progressIndicator + 1] == "maximalCoreFrequency" {

                    if (systemConfigurationKnobs.utilizedBigCores.get() > 0 && systemConfigurationKnobs.utilizedLittleCores.get() == 0) {

                        result = scenarioKnobs.maximalBigCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    } else if (systemConfigurationKnobs.utilizedBigCores.get() == 0 && systemConfigurationKnobs.utilizedLittleCores.get() > 0) {

                        result = scenarioKnobs.maximalLittleCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    }

                }

            // Limited availability System Configuration Knobs
            } else if message[progressIndicator] == "systemConfigurationKnobs" {

                if message[progressIndicator + 1] == "utilizedCores" {

                    if (systemConfigurationKnobs.utilizedBigCores.get() > 0 && systemConfigurationKnobs.utilizedLittleCores.get() == 0) {

                        result = scenarioKnobs.availableBigCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    } else if (systemConfigurationKnobs.utilizedBigCores.get() == 0 && systemConfigurationKnobs.utilizedLittleCores.get() > 0) {

                        result = scenarioKnobs.availableLittleCores.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    }

                } else if message[progressIndicator + 1] == "utilizedCoreFrequency" {

                    if (systemConfigurationKnobs.utilizedBigCores.get() > 0 && systemConfigurationKnobs.utilizedLittleCores.get() == 0) {

                        result = systemConfigurationKnobs.utilizedBigCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    } else if (systemConfigurationKnobs.utilizedBigCores.get() == 0 && systemConfigurationKnobs.utilizedLittleCores.get() > 0) {

                        result = systemConfigurationKnobs.utilizedLittleCoreFrequency.textApi(caller: caller, message: message, progressIndicator: progressIndicator + 2, verbosityLevel: verbosityLevel)

                    }

                // Derived System Configuration Knobs
                } else if message[progressIndicator + 1] == "utilizedCoreMask" {

                    // TODO

                } else if message[progressIndicator + 1] == "utilizedCoreFrequencies" {

                    // TODO

                }

            // System measures
            } else if message[progressIndicator] == "energy" && message[progressIndicator + 1] == "get" {

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

    /** ARM bigLITTLE: get status as a dictionary */
    public func getInternalStatus() -> [String : Any]? {
        return ["energy" : self.energyMonitor.readEnergy(), "time" : self.clockMonitor.readClock()]
    }

    /** Enforce the active Resource Usage Policy and ensure Consistency between Scenario and System Configuration Knobs */
    func enforceResourceUsageAndConsistency() -> Void {

        // Store the requested state
        let requestedState = ArmBigLittleSystemConfigurationKnobs()
        requestedState.utilizedBigCores.set(                      systemConfigurationKnobs.utilizedBigCores.get())
        requestedState.utilizedBigCoreFrequency.set(      systemConfigurationKnobs.utilizedBigCoreFrequency.get())
        requestedState.utilizedLittleCores.set(                systemConfigurationKnobs.utilizedLittleCores.get())
        requestedState.utilizedLittleCoreFrequency.set( systemConfigurationKnobs.utilizedLittleCoreFrequency.get())

        //-------------------------------
        // Maximal Resource Usage Policy
        //
        // Maxes out system utilization on one type of cores, primarily on big
        if resourceUsagePolicyModule.policy.get() == ResourceUsagePolicy.Maximal {
        
            if scenarioKnobs.availableBigCores.get() > 0 {

                systemConfigurationKnobs.utilizedBigCores.set(                 scenarioKnobs.availableBigCores.get() )
                systemConfigurationKnobs.utilizedBigCoreFrequency.set(   scenarioKnobs.maximalBigCoreFrequency.get() )
                systemConfigurationKnobs.utilizedLittleCores.set(                                                  0 )
                systemConfigurationKnobs.utilizedLittleCoreFrequency.set(                          otherCoreFrequency)

            } else {

                systemConfigurationKnobs.utilizedBigCores.set(                                                           0 )
                systemConfigurationKnobs.utilizedBigCoreFrequency.set(                                   otherCoreFrequency)
                systemConfigurationKnobs.utilizedLittleCores.set(                 scenarioKnobs.availableLittleCores.get() )
                systemConfigurationKnobs.utilizedLittleCoreFrequency.set(   scenarioKnobs.maximalLittleCoreFrequency.get() )

            }

            // Report if policy was applied
            if ((systemConfigurationKnobs.utilizedBigCores.get()            !=            requestedState.utilizedBigCores.get()) ||
                (systemConfigurationKnobs.utilizedBigCoreFrequency.get()    !=    requestedState.utilizedBigCoreFrequency.get()) ||
                (systemConfigurationKnobs.utilizedLittleCores.get()         !=         requestedState.utilizedLittleCores.get()) ||
                (systemConfigurationKnobs.utilizedLittleCoreFrequency.get() != requestedState.utilizedLittleCoreFrequency.get()) ){

                    // TODO: add

            }

        //-------------------------------
        // Maintained Resource Usage Policy
        //
        // Maintains a certain resource usage, able to recoup after multiple perturbations
        } else if resourceUsagePolicyModule.policy.get() == ResourceUsagePolicy.Maintain {

            // Enforce the `maintained state`
            systemConfigurationKnobs.utilizedBigCores.set(                      resourceUsagePolicyModule.maintainedState.utilizedBigCores.get())
            systemConfigurationKnobs.utilizedBigCoreFrequency.set(      resourceUsagePolicyModule.maintainedState.utilizedBigCoreFrequency.get())
            systemConfigurationKnobs.utilizedLittleCores.set(                resourceUsagePolicyModule.maintainedState.utilizedLittleCores.get())
            systemConfigurationKnobs.utilizedLittleCoreFrequency.set(resourceUsagePolicyModule.maintainedState.utilizedLittleCoreFrequency.get())

            // Report if policy was applied
            if ((systemConfigurationKnobs.utilizedBigCores.get()            !=            requestedState.utilizedBigCores.get()) ||
                (systemConfigurationKnobs.utilizedBigCoreFrequency.get()    !=    requestedState.utilizedBigCoreFrequency.get()) ||
                (systemConfigurationKnobs.utilizedLittleCores.get()         !=         requestedState.utilizedLittleCores.get()) ||
                (systemConfigurationKnobs.utilizedLittleCoreFrequency.get() != requestedState.utilizedLittleCoreFrequency.get()) ){

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

        if (systemConfigurationKnobs.utilizedBigCores.get() > scenarioKnobs.availableBigCores.get()) {
            systemConfigurationKnobs.utilizedBigCores.set(   scenarioKnobs.availableBigCores.get())

        }

        if (systemConfigurationKnobs.utilizedLittleCores.get() > scenarioKnobs.availableLittleCores.get()) {
            systemConfigurationKnobs.utilizedLittleCores.set(   scenarioKnobs.availableLittleCores.get())

        }

        if (systemConfigurationKnobs.utilizedBigCoreFrequency.get() > scenarioKnobs.maximalBigCoreFrequency.get()) {
            systemConfigurationKnobs.utilizedBigCoreFrequency.set(   scenarioKnobs.maximalBigCoreFrequency.get())

        }

        if (systemConfigurationKnobs.utilizedLittleCoreFrequency.get() > scenarioKnobs.maximalLittleCoreFrequency.get()) {
            systemConfigurationKnobs.utilizedLittleCoreFrequency.set(   scenarioKnobs.maximalLittleCoreFrequency.get())

        }

        //-------------------------------
        // Resiliency policy (policy #2)
        //  - activated if after Check #1 applied to requestedState there are no cores utilized
        //  - tries to schedule onto primarily big cores
        //
        // NOTE
        //  Typical situation is when one core type is made unavailable for the software and the utilization needs to be automatically ported onto the cores of other type
        if (((systemConfigurationKnobs.utilizedBigCores.get() == 0) && (systemConfigurationKnobs.utilizedLittleCores.get() == 0)) &&
            ((scenarioKnobs.availableBigCores.get() > 0) || (scenarioKnobs.availableLittleCores.get() > 0))) {

            // schedule onto big cores
            if scenarioKnobs.availableBigCores.get() > 0 {
               systemConfigurationKnobs.utilizedBigCores.set(           min(scenarioKnobs.availableBigCores.get(),       ((requestedState.utilizedBigCores.get() > 0) ? requestedState.utilizedBigCores.get()         : requestedState.utilizedLittleCores.get())))
               systemConfigurationKnobs.utilizedBigCoreFrequency.set(   min(scenarioKnobs.maximalBigCoreFrequency.get(), ((requestedState.utilizedBigCores.get() > 0) ? requestedState.utilizedBigCoreFrequency.get() : requestedState.utilizedLittleCoreFrequency.get())))
               systemConfigurationKnobs.utilizedLittleCoreFrequency.set(otherCoreFrequency )

            // schedule onto LITTLE cores
            } else {
                systemConfigurationKnobs.utilizedLittleCores.set(        min(scenarioKnobs.availableLittleCores.get(),       ((requestedState.utilizedLittleCores.get() > 0) ? requestedState.utilizedLittleCores.get()         : requestedState.utilizedBigCores.get())))
                systemConfigurationKnobs.utilizedLittleCoreFrequency.set(min(scenarioKnobs.maximalLittleCoreFrequency.get(), ((requestedState.utilizedLittleCores.get() > 0) ? requestedState.utilizedLittleCoreFrequency.get() : requestedState.utilizedBigCoreFrequency.get())))
                systemConfigurationKnobs.utilizedBigCoreFrequency.set(   otherCoreFrequency )

            }

        }

        //-------------------------------
        // Inactive Core Policy (policy #3)
        //
        // Ensuring that inactive cores are running on the lowest frequency setting
        if ((systemConfigurationKnobs.utilizedBigCores.get() == 0) && (systemConfigurationKnobs.utilizedBigCoreFrequency.get() != otherCoreFrequency)) {
            systemConfigurationKnobs.utilizedBigCoreFrequency.set( otherCoreFrequency);

        }

        if ((systemConfigurationKnobs.utilizedLittleCores.get() == 0) && (systemConfigurationKnobs.utilizedLittleCoreFrequency.get() != otherCoreFrequency)) {
            systemConfigurationKnobs.utilizedLittleCoreFrequency.set( otherCoreFrequency);

        }

        //-------------------------------
        //
        // Some assertions that point to invalid configurations (won't happen during normal use)
        assert( ((systemConfigurationKnobs.utilizedBigCores.get() > 0) || (systemConfigurationKnobs.utilizedLittleCores.get() > 0)) && (!((systemConfigurationKnobs.utilizedBigCores.get() > 0) && (systemConfigurationKnobs.utilizedLittleCores.get() > 0))));
    }
}

//-------------------------------
