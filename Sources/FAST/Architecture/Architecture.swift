/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic Architecture Protocols
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation
import Venice

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

/** Resource Usage Policy for Scenario Knob-enriched Architectures */
public enum ResourceUsagePolicy: String {
  case Simple
  case Maintain
  case Maximal
}

// ResourceUsagePolicy is initializable from a String
extension ResourceUsagePolicy: InitializableFromString {

  public init?(from text: String) {

    switch text {

      case "Simple": 
        self = ResourceUsagePolicy.Simple

      case "Maintain": 
        self = ResourceUsagePolicy.Maintain

      case "Maximal": 
        self = ResourceUsagePolicy.Maximal

      default:
        return nil

    }
  }
}

// Converting ResourceUsagePolicy to String
extension ResourceUsagePolicy: CustomStringConvertible {

  public var description: String {

    switch self {

      case ResourceUsagePolicy.Simple: 
        return "Simple"

      case ResourceUsagePolicy.Maintain: 
        return "Maintain"

      case ResourceUsagePolicy.Maximal: 
        return "Maximal"
       
    }
  }
}

/** Generic Resource Usage Policy Module */
public protocol ResourceUsagePolicyModule: TextApiModule {

    // Maintained State (System Configuration Knobs)
    var maintainedState: TextApiModule { get set }

    // The active ResourceUsagePolicy
    var policy: Knob<ResourceUsagePolicy> { get }
}

/** Generic Interface for a Scenario Knob-enriched Architecture */
public protocol ScenarioKnobEnrichedArchitecture: Architecture {
  
  // Architecture has Scenario Knobs
  associatedtype     ScenarioKnobsType : TextApiModule;
  var scenarioKnobs: ScenarioKnobsType  { get }

  // Architecture has System Configuration Knobs
  associatedtype                SystemConfigurationKnobsType : TextApiModule;
  var systemConfigurationKnobs: SystemConfigurationKnobsType { get }

  // Architecture has Resource Usage Policy Module
  associatedtype                 ResourceUsagePolicyModuleType : TextApiModule;
  var resourceUsagePolicyModule: ResourceUsagePolicyModuleType { get }

  // Enforce the active Resource Usage Policy and ensure Consistency between Scenario and System Configuration Knobs
  func enforceResourceUsageAndConsistency() -> Void
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
  func registerSystemMeasures() -> Void
}

/** Default System Measures */
extension ClockAndEnergyArchitecture {

  // Architecture has system measures: time and energy
  var systemMeasures: Array<String> { return ["time", "energy"] } 

  // Register System Measures
  func registerSystemMeasures() -> Void {
    co {
        while true {
            let _ = Runtime.measure("energy", Double(self.energyMonitor.readEnergy()))
            let _ = Runtime.measure("time",          self.clockMonitor.readClock())
            nap(for: 1.millisecond)
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

  // Actuate System Configuration on Real Hardware
  func actuate() -> Void
}

//---------------------------------------
