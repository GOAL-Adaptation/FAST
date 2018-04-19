/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic Architecture Protocols
 *
 *  authors: Ferenc A Bartha, Adam Duracz
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation
import LoggerAPI
import Dispatch

//---------------------------------------

fileprivate let key = ["proteus","architecture"]

let linuxDvfsGovernor: LinuxDvfsGovernor = initialize(type: LinuxDvfsGovernor.self, name: "linuxDvfsGovernor", from: key, or: .Performance)

//---------------------------------------

/** Architecture */

/** Generic Interface for an Architecture */
public protocol Architecture: TextApiModule {

  // Architecture has a name
  var name: String { get }

  // Architecture has system measures
  var systemMeasures: Array<String> { get }
}

//---------------------------------------
/** Scenario Knob-enriched Architecture */

/** Generic Interface for a Scenario Knob-enriched Architecture */
public protocol ScenarioKnobEnrichedArchitecture: Architecture {

  // Architecture has Scenario Knobs
  associatedtype     ScenarioKnobsType : TextApiModule;
  var scenarioKnobs: ScenarioKnobsType  { get }

  // Architecture has System Configuration Knobs
  associatedtype                SystemConfigurationKnobsType : TextApiModule;
  var systemConfigurationKnobs: SystemConfigurationKnobsType { get }

}

//---------------------------------------
/** Architecture with ClockMonitor & EnergyMonitor */

/** Architecture with ClockMonitor & EnergyMonitor */
public protocol ClockAndEnergyArchitecture: Architecture {

  // Architecture has ClockMonitor
  var clockMonitor:  ClockMonitor  { get }

  // Architecture has EnergyMonitor
  var energyMonitor: EnergyMonitor { get }

  // Register System Measures
  func registerSystemMeasures(runtime: Runtime) -> Void
}

/** Default System Measures */
extension ClockAndEnergyArchitecture {

  // Architecture has system measures: time and energy
  var systemMeasures: Array<String> { return ["time", "systemEnergy"] }

  // Register System Measures
  func registerSystemMeasures(runtime: Runtime) {
    if runtime.isSystemMeasuresRegistered {
      Log.debug("ClockAndEnergyArchitecture.registerSystemMeasures_2 for \(self) clockMonitor = \(self.clockMonitor) energyMonitor = \(self.energyMonitor)")
      Log.verbose("System measures have been registered.")
      return
    }
    runtime.isSystemMeasuresRegistered = true

    Log.debug("ClockAndEnergyArchitecture.registerSystemMeasures_1 for \(self) clockMonitor = \(self.clockMonitor) energyMonitor = \(self.energyMonitor)")
    
    DispatchQueue.global(qos: .utility).async {
      while true {
        runtime.measure("time", self.clockMonitor.readClock())
        runtime.measure("systemEnergy", Double(self.energyMonitor.readEnergy()))
        usleep(1000) // Register system measures every millisecond
      }
    }
  }
}

//---------------------------------------
/** Real Architecture */

/** Actuation Policy for Real Architectures */
public enum ActuationPolicy: String {
  case Actuate
  case NoActuation
}

// Actuation Policy is initializable from a String
extension ActuationPolicy: InitializableFromString {

  public init?(from text: String) {

    switch text {

      case "Actuate":
        self = ActuationPolicy.Actuate

      case "NoActuation":
        self = ActuationPolicy.NoActuation

      default:
        return nil

    }
  }
}

// Converting ActuationPolicy to String
extension ActuationPolicy: CustomStringConvertible {

  public var description: String {

    switch self {

      case ActuationPolicy.Actuate:
        return "Actuate"

      case ActuationPolicy.NoActuation:
        return "NoActuation"

    }
  }
}

/** Generic Interface for a Real Architecture */
public protocol RealArchitecture: Architecture {

  // Architecture has Actuation Policy
  var actuationPolicy: Knob<ActuationPolicy> { get }

}

//---------------------------------------

/** Linux DVFS governor */
public enum LinuxDvfsGovernor: String {

  case Performance
  case Userspace

}

/** Default actuation command for a typical Linux system */
internal func actuateLinuxUtilizedCoresSystemConfigurationKnob(actuationPolicy: ActuationPolicy, utilizedCores: Int) -> Void {

    switch actuationPolicy {
      case .Actuate:

        let activeCores = ProcessInfo.processInfo.activeProcessorCount
        if utilizedCores > activeCores  {
          Log.warning("Knob utilizedCores was set to \(utilizedCores) which is higher than the number of active cores (\(activeCores)). Using the lower number.")
        }
        let utilizedCoreRange = 0 ..< min(activeCores, utilizedCores)

        // Configure the Hardware to use the number of cores dictated by the system configuration knobs

        let coreMask = utilizedCoreRange.map({String($0)}).joined(separator: ",")
        let pid = getpid()
        let utilizedCoresCommand = "/bin/sh"
        let utilizedCoresCommandArguments = ["-c", "ps -eLf | awk '(/\(pid)/) && (!/awk/) {print $4}' | xargs -n1 taskset -c -p \(coreMask) > /dev/null"] 

        Log.verbose("Applying utilizedCores as core allocation '\(coreMask)'.")
        Log.debug("Applying utilizedCores using core allocation command: \(utilizedCoresCommand) \(utilizedCoresCommandArguments.joined(separator: " ")).")

        let (coreMaskReturnCode, coreMaskOutput) = executeInShell(utilizedCoresCommand, arguments: utilizedCoresCommandArguments)
        if coreMaskReturnCode != 0 {
            Log.error("Error running taskset: \(coreMaskReturnCode). Output was: \(String(describing: coreMaskOutput)).")
        }

      case .NoActuation:
        Log.info("Not applying system configuration knob (utilizedCores) due to active actuation policy.")
    }

}

/** Default actuation command for a typical Linux system */
internal func actuateLinuxUtilizedCoreFrequencySystemConfigurationKnob(actuationPolicy: ActuationPolicy, utilizedCoreFrequency: Int) -> Void {

    switch actuationPolicy {
      case .Actuate:

        let dvfsFile = linuxDvfsGovernor == .Performance ? "scaling_max_freq" : "scaling_setspeed" // performance : userspace
        let activeCores = ProcessInfo.processInfo.activeProcessorCount
        let utilizedCoreRange = 0 ..< activeCores

        // Configure the Hardware to use the core frequencies dictated by the system configuration knobs

        Log.verbose("Applying CPU frequency: \(utilizedCoreFrequency) to all \(activeCores) active CPU cores.")

        for coreNumber in utilizedCoreRange {
          let utilizedCoreFrequencyCommand = "/usr/bin/sudo"
          let utilizedCoreFrequencyCommandArguments = ["/bin/sh", "-c", "/bin/echo \(utilizedCoreFrequency) > /sys/devices/system/cpu/cpu\(coreNumber)/cpufreq/\(dvfsFile)"]
          Log.debug("Setting frequency limit for core \(coreNumber): '\(utilizedCoreFrequencyCommand ) \(utilizedCoreFrequencyCommandArguments.joined(separator: " "))'.")
          let (utilizedCoreFrequencyReturnCode, utilizedCoreFrequencyOutput) = executeInShell(utilizedCoreFrequencyCommand, arguments: utilizedCoreFrequencyCommandArguments)
          if utilizedCoreFrequencyReturnCode != 0 {
              Log.error("Error setting frequency limit for core \(coreNumber): \(utilizedCoreFrequencyReturnCode). Output was: \(String(describing: utilizedCoreFrequencyOutput)).")
          }
        }

      case .NoActuation:
        Log.info("Not applying system configuration knobs (CPU frequency) due to active actuation policy.")
    }

  }

//---------------------------------------
