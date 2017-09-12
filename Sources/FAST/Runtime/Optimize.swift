/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Optimize construct
 *
 *  authors: Adam Duracz, Ferenc Bartha
 */

//---------------------------------------

import Foundation
import Dispatch
import LoggerAPI
import FASTController

//---------------------------------------

fileprivate let key = ["proteus","runtime"]

/* A strategy for switching between KnobSettings, based on the input index. */
public class Schedule {
    let schedule: (_ progress: UInt32) -> KnobSettings
    init(_ schedule: @escaping (_ progress: UInt32) -> KnobSettings) {
        self.schedule = schedule
    }
    init(constant:  KnobSettings) {
        schedule = { (_: UInt32) in constant }
    }
    subscript(index: UInt32) -> KnobSettings {
        get {
            Log.debug("Querying schedule at index \(index)")
            return schedule(index)
        }
    }
}

/** Start the REST server in a low-priority background thread */
fileprivate func startRestServer() {
    DispatchQueue.global(qos: .utility).async {
        RestServer()
    }
}

/* Defines an optimization scope. Replaces a loop in a pure Swift program. */
public func optimize
    ( _ id: String
    , until shouldTerminate: @escaping @autoclosure () -> Bool = false
    , across windowSize: UInt32 = 20
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
    , _ routine: @escaping (Void) -> Void ) {

    startRestServer()

    /** Loop body for a given number of iterations (or infinitely, if iterations == nil) */
    func loop(iterations: UInt32? = nil, _ body: (Void) -> Void) {
        if let i = iterations {
            var localIteration: UInt32 = 0
            while localIteration < i && !shouldTerminate() && !Runtime.shouldTerminate {
                body()
                localIteration += 1
            }
        } else {
            while !shouldTerminate() && !Runtime.shouldTerminate {
                body()
            }
        }
    }
    
    if let intent = Runtime.loadIntent(id) {
        if let model = Runtime.loadModel(id) {

            // Initialize the controller with the knob-to-mesure model, intent and window size
            Runtime.initializeController(model, intent, windowSize)

            func runOnce() {
                // Initialize measuring device, that will update measures based on the samplingPolicy
                let measuringDevice = MeasuringDevice(samplingPolicy, windowSize, labels)
                // FIXME what if the counter overflows
                var iteration: UInt32 = 0 // iteration counter
                if let controllerModel = Runtime.controller.model {
                    var schedule: Schedule = Schedule(constant: controllerModel.getInitialConfiguration()!.knobSettings)
                    loop {
                        Runtime.measure("iteration", Double(iteration))
                        executeAndReportProgress(measuringDevice, routine)
                        iteration += 1
                        if iteration % windowSize == 0 {
                            let measureWindowAverages = Dictionary(measuringDevice.stats.map{ (n,s) in (n, s.windowAverage) })
                            schedule = Runtime.controller.getSchedule(intent, measureWindowAverages)
                        }
                        if Runtime.runtimeKnobs.applicationExecutionMode.get() == ApplicationExecutionMode.Adaptive {
                            // FIXME This should only apply when the schedule actually needs to change knobs
                            schedule[iteration % windowSize].apply()
                        }
                        Runtime.measure("iteration", Double(iteration))
                        // FIXME maybe stalling in scripted mode should not be done inside of optimize but somewhere else in an independent and better way
                        Runtime.reportProgress()
                    } 
                }
                else {
                    Log.error("Attempt to execute using controller with undefined model.")
                } 
            }

            Log.info("Application executing in \(Runtime.runtimeKnobs.applicationExecutionMode.get()) mode.")
            switch Runtime.runtimeKnobs.applicationExecutionMode.get() {
                case .ExhaustiveProfiling:

                    // Initialize measuring device, that will update measures at every input
                    let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, labels)

                    // Number of inputs to process when profiling a configuration
                    let defaultProfileSize:         UInt32 = UInt32(1000)
                    // File prefix of knob- and measure tables
                    let defaultProfileOutputPrefix: String = Runtime.application?.name ?? "fast"
                    
                    let profileSize         = initialize(type: UInt32.self, name: "profileSize",         from: key, or: defaultProfileSize)
                    let profileOutputPrefix = initialize(type: String.self, name: "profileOutputPrefix", from: key, or: defaultProfileOutputPrefix) 
                    
                    withOpenFile(atPath: profileOutputPrefix + ".knobtable") { (knobTableOutputStream: Foundation.OutputStream) in
                        withOpenFile(atPath: profileOutputPrefix + ".measuretable") { (measureTableOutputStream: Foundation.OutputStream) in

                            let knobSpace = intent.knobSpace()
                            let knobNames = Array(knobSpace[0].settings.keys).sorted()
                            let measureNames = intent.measures
                            
                            func makeRow(id: Any, rest: [Any]) -> String {
                                return "\(id)\(rest.reduce( "", { l,r in "\(l),\(r)" }))\n"
                            }

                            // Output headers for tables
                            let knobTableHeader = makeRow(id: "id", rest: knobNames)
                            knobTableOutputStream.write(knobTableHeader, maxLength: knobTableHeader.characters.count)
                            let measureTableHeader = makeRow(id: "id", rest: measureNames)
                            measureTableOutputStream.write(measureTableHeader, maxLength: measureTableHeader.characters.count)

                            for i in 0 ..< knobSpace.count {

                                let knobSettings = knobSpace[i]
                                Log.info("Start profiling of configuration: \(knobSettings).")
                                knobSettings.apply()
                                loop( iterations: profileSize
                                    , { executeAndReportProgress(measuringDevice, routine) } )

                                // Output profile entry as line in knob table
                                let knobValues = knobNames.map{ knobSettings.settings[$0]! }
                                let knobTableLine = makeRow(id: i, rest: knobValues)
                                knobTableOutputStream.write(knobTableLine, maxLength: knobTableLine.characters.count)
                                
                                // Output profile entry as line in measure table
                                let measureValues = measureNames.map{ measuringDevice.stats[$0]!.totalAverage }
                                let measureTableLine = makeRow(id: i, rest: measureValues)
                                measureTableOutputStream.write(measureTableLine, maxLength: measureTableLine.characters.count)
                                
                            }

                        }
                    }
                    
                // case .SelectiveProfiling(percentage: Int, extremeValues: Bool):

                default: // .Adaptive and .NonAdaptive
                    runOnce()
            }

        } else {
            Log.warning("No model loaded for optimize scope '\(id)'. Proceeding without adaptation.")
            loop(routine)
        }        
    } else {
        Log.warning("No intent loaded for optimize scope '\(id)'. Proceeding without adaptation.")
        loop(routine)
    }

    print("FAST application terminating.")

}