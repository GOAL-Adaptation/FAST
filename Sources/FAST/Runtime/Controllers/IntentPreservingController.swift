import Foundation
import LoggerAPI
import FASTController

class IntentPreservingController : Controller {
    
    let model              : Model? // Always defined for this Controller
    let window             : UInt32
    let fastController     : FASTController
    let intent             : IntentSpec

    let missionLength      : UInt64
    let energyLimit        : UInt64?
    let enforceEnergyLimit : Bool
    let sceneImportance    : Double?

    init?( _ model: Model
         , _ intent: IntentSpec
         , _ window: UInt32
         , _ missionLength: UInt64
         , _ energyLimit: UInt64?
         , _ enforceEnergyLimit: Bool
         , _ sceneImportance: Double? 
         ) 
    {

        let modelSortedByConstraintMeasure = model.sorted(by: intent.constraintName)

        self.model              = modelSortedByConstraintMeasure
        self.window             = window
        self.intent             = intent
        self.missionLength      = missionLength
        self.energyLimit        = energyLimit
        self.enforceEnergyLimit = enforceEnergyLimit
        self.sceneImportance    = sceneImportance

        if let constraintMeasureIdx = modelSortedByConstraintMeasure.measureNames.index(of: intent.constraintName) {
            
            // TODO Gather statistics about how many configurations are filtered by each test parameter

            ////
            // missionLength parameter
            ////

            var objectiveFunctionAfterMissionLength: ([Double]) -> Double
            
            // If enforceEnergyLimit is true, then wrap the user-specified intent.costOrValue
            // so that it assigns sub-optimal objective function value to schedules that use
            // too much energy to meet missionLength on average. 
            // Otherwise use the unmodified currentObjectiveFunction.

            if 
                enforceEnergyLimit,
                let theEnergyLimit        = energyLimit,
                let energyMeasureIdx      = model.measureNames.index(of: "energy"),
                let energyDeltaMeasureIdx = model.measureNames.index(of: "energyDelta"),
                let iterationMeasureIdx   = model.measureNames.index(of: "iteration")
            {

                func missionLengthRespectingObjectiveFunction(_ scheduleMeasureAverages: [Double]) -> Double {
                    
                    let energySinceStart   = UInt64(scheduleMeasureAverages[energyMeasureIdx])
                    let energyPerIteration = UInt64(scheduleMeasureAverages[energyDeltaMeasureIdx])
                    let iteration          = UInt64(scheduleMeasureAverages[iterationMeasureIdx])

                    let remainingIterations = missionLength - iteration

                    // If schedule consumes too much energy per input, make it sub-optimal
                    if energySinceStart + energyPerIteration * remainingIterations > theEnergyLimit {
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
                objectiveFunctionAfterMissionLength = missionLengthRespectingObjectiveFunction

            }
            else {
                Log.debug("Using missionLength-oblivious objective function.")
                objectiveFunctionAfterMissionLength = intent.costOrValue
            }

            ////
            // sceneImportance parameter
            ////

            let objectiveFunctionAfterMissionLengthAndSceneImportance : ([Double]) -> Double

            // If sceneImportance is defined, then wrap the currentObjectiveFunction from 
            // so that it assigns sub-optimal objective function value to schedules
            // that are estimated to produce a quality lower than minimumQuality.
            // Otherwise use the unmodified currentObjectiveFunction.

            let modelSortedByQualityMeasure = model.sorted(by: "quality")

            if 
                let importance = sceneImportance,
                let qualityMeasureIdx = modelSortedByQualityMeasure.measureNames.index(of: "quality"),
                let modelQualityMaxConfiguration = modelSortedByQualityMeasure.configurations.last,
                let modelQualityMinConfiguration = modelSortedByQualityMeasure.configurations.first
            {

                // Max and min average qualities from the model
                let modelQualityMax = modelQualityMaxConfiguration.measureValues[qualityMeasureIdx]
                let modelQualityMin = modelQualityMinConfiguration.measureValues[qualityMeasureIdx]

                // Estimate of the range of achievable qualities of any 
                // configuration by looking up in the model
                let modelQualityMaxMinDiff = modelQualityMax - modelQualityMin
                
                let sufficientQuality = modelQualityMin + importance * modelQualityMaxMinDiff

                func importanceRespectingObjectiveFunction(_ scheduleMeasureAverages: [Double]) -> Double {

                    // Quality of this schedule
                    let quality = scheduleMeasureAverages[qualityMeasureIdx]
                    // If schedule does not produce a sufficiently high quality
                    if quality < sufficientQuality {
                        Log.debug("Filtering schedule with insufficient quality \(quality) < \(sufficientQuality).")
                        switch intent.optimizationType {
                            case .minimize: return  Double.infinity
                            case .maximize: return -Double.infinity
                        }
                    }
                    else {
                        Log.debug("Not filtering schedule with sufficient quality \(quality) >= \(sufficientQuality).")
                        return objectiveFunctionAfterMissionLength(scheduleMeasureAverages)
                    }

                }

                Log.debug("Using sceneImportance-respecting objective function based on sufficient quality \(sufficientQuality).")
                objectiveFunctionAfterMissionLengthAndSceneImportance = importanceRespectingObjectiveFunction

            }
            else {
                Log.debug("Using sceneImportance-oblivious objective function.")
                objectiveFunctionAfterMissionLengthAndSceneImportance = objectiveFunctionAfterMissionLength
            }

            self.fastController =
                FASTController( model: modelSortedByConstraintMeasure.getFASTControllerModel()
                              , constraint: intent.constraint
                              , constraintMeasureIdx: constraintMeasureIdx
                              , window: window
                              , optType: intent.optimizationType
                              , ocb: objectiveFunctionAfterMissionLengthAndSceneImportance
                              , initialModelEntryIdx: modelSortedByConstraintMeasure.initialConfigurationIndex!
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
