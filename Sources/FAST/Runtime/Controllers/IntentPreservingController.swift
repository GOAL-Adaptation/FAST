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
         , _ missionLengthAndEnergyLimit: (UInt64, UInt64)? = nil
         , _ sceneImportance: Double? ) {
        let modelSortedByConstraintMeasure = model.sorted(by: intent.constraintName)
        self.model = modelSortedByConstraintMeasure
        self.window = window
        self.intent = intent
        if let constraintMeasureIdx = modelSortedByConstraintMeasure.measureNames.index(of: intent.constraintName) {
            
            // TODO Gather statistics about how many configurations are filtered by each test parameter
            ////
            // missionLength test parameter
            ////
            // If missionLength and energyLimit are defined, then wrap the user-defined
            // objective function from the intent so that it assigns sub-optimal objective
            // function value to schedules that use too much energy to meet missionLength 
            // on average. Otherwise use the unmodified user-defined objective function.
            
            var objectiveFunctionAfterMissionLength: ([Double]) -> Double
            
            if 
                let (missionLength, energyLimit) = missionLengthAndEnergyLimit,
                let energyMeasureIdx      = modelSortedByConstraintMeasure.measureNames.index(of: "energy"),
                let energyDeltaMeasureIdx = modelSortedByConstraintMeasure.measureNames.index(of: "energyDelta"),
                let iterationMeasureIdx   = modelSortedByConstraintMeasure.measureNames.index(of: "iteration") 
            {
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
                objectiveFunctionAfterMissionLength = missionLengthRespectingObjectiveFunction
            }
            else {
                Log.debug("Using missionLength-oblivious objective function.")
                objectiveFunctionAfterMissionLength = intent.costOrValue
            }

            ////
            // sceneImportance test parameter
            ////
            let modelSortedByQualityMeasure = model.sorted(by: "quality")

            // If sceneImportance is defined, then wrap the user-defined objective function from 
            // the intent so that it assigns sub-optimal objective function value to schedules
            // that are estimated to produce a quality lower than minimumQuality.
            // Otherwise use the objectiveFunctionAfterMissionLength.
            var objectiveFunctionAfterMissionLengthAndSceneImportance: ([Double]) -> Double

            if 
                let importance = sceneImportance,
                let qualityMeasureIdx = modelSortedByQualityMeasure.measureNames.index(of: "quality"),
                let modelQualityMaxConfiguration = modelSortedByQualityMeasure.configurations.last,
                let modelQualityMinConfiguration = modelSortedByQualityMeasure.configurations.first
            {

                // Max and min average qualities from the model
                let modelQualityMax = modelQualityMaxConfiguration.measureValues[qualityMeasureIdx]
                let modelQualityMin = modelQualityMinConfiguration.measureValues[qualityMeasureIdx]

                // Tolerate deviations of this relative amount from the maximum
                // to account for runtime deviations from the model averages
                //
                // FIXME Compute this based on model variance information,
                //       or expose as a parameter.
                let qualityTolerance = 0.1

                // Estimate of the range of achievable qualities of any 
                // configuration by looking up in the model
                let modelQualityMaxMinDiff = modelQualityMax - modelQualityMin
                
                let sufficientQuality = modelQualityMin + importance * (1 - qualityTolerance) * modelQualityMaxMinDiff

                func importanceRespectingObjectiveFunction(_ scheduleMeasureAverages: [Double]) -> Double {

                    // Quality of this schedule
                    let quality = scheduleMeasureAverages[qualityMeasureIdx]

                    // If schedule does not produce a sufficiently high quality
                    if quality < sufficientQuality {
                        switch intent.optimizationType {
                            case .minimize: return  Double.infinity
                            case .maximize: return -Double.infinity
                        }
                    }
                    else {
                        return intent.costOrValue(scheduleMeasureAverages)
                    }

                }
                Log.debug("Using sceneImportance-respecting objective function.")
                objectiveFunctionAfterMissionLengthAndSceneImportance = importanceRespectingObjectiveFunction
            }
            else {
                Log.debug("Using sceneImportance-oblivious objective function.")
                objectiveFunctionAfterMissionLengthAndSceneImportance = intent.costOrValue
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
