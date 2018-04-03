import Foundation
import LoggerAPI
import FASTController

class IntentPreservingController : Controller {
    let model: Model? // Always defined for this Controller
    let window: UInt32
    let fastController: FASTController
    let intent: IntentSpec

    init?( _ model: Model
         , _ intent: IntentSpec
         , _ window: UInt32
         , _ missionLengthAndEnergyLimit: (UInt64, UInt64)? = nil) {
        let sortedModel = model.sorted(by: intent.constraintName)
        self.model = sortedModel
        self.window = window
        self.intent = intent
        if let constraintMeasureIdx = sortedModel.measureNames.index(of: intent.constraintName) {
            
            // If missionLength and energyLimit are defined, then wrap the user-defined
            // objective function from the intent so that it assigns sub-optimal objective
            // function value to schedules that use too much energy to meet missionLength 
            // on average. Otherwise use the unmodified user-defined objective function.
            var objectiveFunction: ([Double]) -> Double 
            if let (missionLength, energyLimit) = missionLengthAndEnergyLimit,
               let energyMeasureIdx      = sortedModel.measureNames.index(of: "energy"),
               let energyDeltaMeasureIdx = sortedModel.measureNames.index(of: "energyDelta"),
               let iterationMeasureIdx   = sortedModel.measureNames.index(of: "iteration") {
                func missionLengthRespectingObjectiveFunction(_ scheduleMeasureAverages: [Double]) -> Double {
                    
                    let energySinceStart   = UInt64(scheduleMeasureAverages[energyMeasureIdx])
                    let energyPerIteration = UInt64(scheduleMeasureAverages[energyDeltaMeasureIdx])
                    let iteration          = UInt64(scheduleMeasureAverages[iterationMeasureIdx])

                    let remainingIterations = missionLength - iteration

                    // If schedule consumes too much energy per input, make it sub-optimal
                    if energySinceStart + energyPerIteration * remainingIterations > energyLimit {
                        switch intent.optimizationType {
                            case .minimize: return  Double.infinity
                            case .maximize: return -Double.infinity
                        }
                    }
                    else {
                        return intent.costOrValue(scheduleMeasureAverages)
                    }

                }
                Log.debug("Using missionLength-respecting objective function.")
                objectiveFunction = missionLengthRespectingObjectiveFunction
            }
            else {
                Log.debug("Using missionLength-oblivious objective function.")
                objectiveFunction = intent.costOrValue
            } 

            self.fastController =
                FASTController( model: sortedModel.getFASTControllerModel()
                              , constraint: intent.constraint
                              , constraintMeasureIdx: constraintMeasureIdx
                              , window: window
                              , optType: intent.optimizationType
                              , ocb: objectiveFunction
                              , initialModelEntryIdx: sortedModel.initialConfigurationIndex!
                              )

        }
        else {
            Log.error("Intent inconsistent with active model: could not match constraint name '\(intent.constraintName)' stated in intent with a measure name in the active model, whose measures are: \(model.measureNames). ")
            exit(1)
            return nil
        }
    }

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
        // FIXME Replace global measure store with custom ordered collection that avoids this conversion
        // FIXME This code duplicates code in Intent.swift. Generalize both when doing the above.
        var values = [Double]()
        for measureName in self.model!.measureNames {
            if let v = measureValues[measureName] {
                values.append(v)
            }
            else {
                fatalError("Measure '\(measureName)', present in model, has not been registered in the application.")
            }
        }
        let s = fastController.computeSchedule(tag: 0, measures: values) // FIXME Pass meaningful tag for logging
        return Schedule({ (i: UInt32) -> KnobSettings in
            return self.model![Int(i) < s.nLowerIterations ? s.idLower : s.idUpper].knobSettings
        })
    }
}
