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
#if os(Linux)
import Glibc
#endif
import CAffinity

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

private var currentUtilizedCores: Int? = nil

/** Default actuation command for a typical Linux system */
internal func actuateLinuxUtilizedCoresSystemConfigurationKnob(actuationPolicy: ActuationPolicy, utilizedCores: Int) -> Void {

    switch actuationPolicy {
      case .Actuate:

        if currentUtilizedCores == utilizedCores {
            Log.verbose("Not applying utilizedCores knob: \(utilizedCores) since that is the current number of utilized cores.")
            return
        }

        let activeCores = ProcessInfo.processInfo.activeProcessorCount
        if utilizedCores > activeCores  {
          Log.warning("Knob utilizedCores was set to \(utilizedCores) which is higher than the number of active cores (\(activeCores)). Using the lower number.")
        }

        // Call external C routine to set affinity for all threads in this process
        let numCores = CUnsignedInt(min(activeCores, utilizedCores))
	Log.verbose("Applying utilizedCores by restricting app to \(numCores) cores.")
	let coreMaskReturnCode = set_app_affinity(numCores)
        if coreMaskReturnCode == 0 {
            currentUtilizedCores = utilizedCores
	    Log.debug("Setting affinity for all threads succeeded.")
        } else if coreMaskReturnCode == -3 {
            Log.error("Error setting thread affinity. Did you forget to run as root?")
        } else if coreMaskReturnCode == -1 {
	    Log.error("Unable to get thread ID list, utilizedCores knob not available on this system.")
	    //TODO: fall back to shell command method instead?
	} else {
	    Log.error("Unknown error setting thread affinity.")
	}

      case .NoActuation:
        Log.info("Not applying system configuration knob (utilizedCores) due to active actuation policy.")
    }

}

private var currentCoreFrequency: Int? = nil

/** Default actuation command for a typical Linux system */
internal func actuateLinuxUtilizedCoreFrequencySystemConfigurationKnob(actuationPolicy: ActuationPolicy, utilizedCoreFrequency: Int) -> Void {

    switch actuationPolicy {
      case .Actuate:

        if currentCoreFrequency == utilizedCoreFrequency {
            Log.verbose("Not applying CPU frequency: \(utilizedCoreFrequency) since it is already active.")
            return
        }

        let dvfsFile = linuxDvfsGovernor == .Performance ? "scaling_max_freq" : "scaling_setspeed" // performance : userspace
        let activeCores = ProcessInfo.processInfo.activeProcessorCount
        let utilizedCoreRange = 0 ..< activeCores
        let freqString = String(utilizedCoreFrequency)
        let freqStringSize = freqString.count

        // Configure the Hardware to use the core frequencies dictated by the system configuration knobs

        Log.verbose("Applying CPU frequency: \(utilizedCoreFrequency) to all \(activeCores) active CPU cores.")

        for coreNumber in utilizedCoreRange {
           let utilizedCoreFrequencyFilename = "/sys/devices/system/cpu/cpu\(coreNumber)/cpufreq/\(dvfsFile)"
           Log.debug("Writing new frequency \(freqString) to \(utilizedCoreFrequencyFilename)")

           let fp = open(utilizedCoreFrequencyFilename, O_WRONLY)
           if fp == -1 {
              Log.error("Error opening frequency file for core \(coreNumber): \(utilizedCoreFrequencyFilename). Did you forget to run as root?")
              fatalError()
           }

           if pwrite(fp, freqString, freqStringSize, 0) == -1 {
              Log.error("Error writing string '\(freqString)' to \(utilizedCoreFrequencyFilename).")
           }

           close(fp)
        }

      case .NoActuation:
        Log.info("Not applying system configuration knobs (CPU frequency) due to active actuation policy.")
    }

}

//---------------------------------------
