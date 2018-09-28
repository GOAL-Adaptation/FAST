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
         , _ runtime: Runtime
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
            // Derive a sub-optimal value for the objective function, by evaluating it
            // over the measure averages for each configuration found in the model.
            ////
            // FIXME Throw proper errors instead of using !
            var subOptimalObjectiveFunctionValue: Double = {
                let measureIndexMapping = intent.measures.map{ model.measureNames.index(of: $0)! }
                let environments: [[Double]] = model.configurations.map{ (c : Configuration) in
                    measureIndexMapping.map{ c.measureValues[$0] }
                }
                let objectiveFunctionValues = environments.map{ intent.costOrValue($0) }
                let objectiveFunctionValueMin = objectiveFunctionValues.min()!
                let objectiveFunctionValueMax = objectiveFunctionValues.max()!
                let objectiveFunctionValueRange = objectiveFunctionValueMax - objectiveFunctionValueMin
                switch intent.optimizationType {
                    case .minimize: return objectiveFunctionValueMax + objectiveFunctionValueRange
                    case .maximize: return objectiveFunctionValueMin - objectiveFunctionValueRange
                }
            }()
            Log.debug("Using \(subOptimalObjectiveFunctionValue) as the sub-optimal objective function value to filter configurations.")

            ////
            // missionLength parameter
            ////

            var objectiveFunctionAfterMissionLength: ([Double]) -> Double
            
            // If enforceEnergyLimit is true, then wrap the user-specified intent.costOrValue
            // so that it assigns sub-optimal objective function value to schedules that use
            // too much energy to meet missionLength on average. 
            // Otherwise use the unmodified currentObjectiveFunction.

            if enforceEnergyLimit {
                if
                    let theEnergyLimit        = energyLimit,
                    let energyMeasureIdx      = model.measureNames.index(of: "energy"),
                    let energyDeltaMeasureIdx = model.measureNames.index(of: "energyDelta")
                {

                    func missionLengthRespectingObjectiveFunction(_ scheduleMeasureAverages: [Double]) -> Double {
                        
                        let energySinceStart   = UInt64(scheduleMeasureAverages[energyMeasureIdx])
                        let energyPerIteration = UInt64(scheduleMeasureAverages[energyDeltaMeasureIdx])
                        let iteration          = UInt64(runtime.getMeasure("iteration") ?? 0.0)

                        let remainingIterations = missionLength - iteration

                        let projectedTotalEnergy = energySinceStart + energyPerIteration * remainingIterations

                        // If schedule consumes too much energy per input, make it sub-optimal
                        if projectedTotalEnergy > theEnergyLimit {
                            Log.debug("Filtering schedule with excessive total energy \(projectedTotalEnergy) > \(theEnergyLimit).")
                            return subOptimalObjectiveFunctionValue
                        }
                        else {
                            Log.debug("Not filtering schedule with total energy \(projectedTotalEnergy) <= \(theEnergyLimit).")
                            return intent.costOrValue(scheduleMeasureAverages)
                        }

                    }

                    Log.debug("Using missionLength-respecting objective function based on energy limit \(theEnergyLimit).")
                    objectiveFunctionAfterMissionLength = missionLengthRespectingObjectiveFunction
                }
                else {
                    let failMessage = "Unable to read measures required for constructing the missionLength-respecting objective function: energyLimit \(energyLimit),  energyMeasureIdx \(model.measureNames.index(of: "energy")), energyDeltaMeasureIdx \(model.measureNames.index(of: "energyDelta")), iterationMeasureIdx \(model.measureNames.index(of: "iteration")), model.measureNames \(model.measureNames)."
                    Log.error(failMessage)
                    fatalError(failMessage)
                }

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
                let importance = sceneImportance, importance > 0.0,
                let qualityMeasureIdx = modelSortedByQualityMeasure.measureNames.index(of: "quality"),
                let modelQualityMaxConfiguration = modelSortedByQualityMeasure.configurations.last,
                let modelQualityMinConfiguration = modelSortedByQualityMeasure.configurations.first
            {
                
                // Computes the range of achievable quality measure values, 
                // given the constraint goal, by looking at the current model
                func computeAchievableQualityRange(constraintGoal: Double) -> (Double,Double) {
                    var (qualityMin,qualityMax): (Double,Double) = (Double.infinity,-Double.infinity)
                    for upper in 0 ..< model.configurations.count {
                        for lower in 0 ..< model.configurations.count {
                            let constraintUpper = model.getMeasureValue(upper, measureName: intent.constraintName)
                            let constraintLower = model.getMeasureValue(lower, measureName: intent.constraintName)
                            let qualityUpper = model.getMeasureValue(upper, measureName: "quality")
                            let qualityLower = model.getMeasureValue(lower, measureName: "quality")
                            // Proportion of time that should be spent in the lower configuration
                            let percentInLower = constraintUpper <= constraintLower
                                               ? 0.0
                                               : ((constraintUpper * constraintLower) - (constraintGoal * constraintLower)) 
                                                 / 
                                                 ((constraintUpper * constraintGoal) - (constraintGoal * constraintLower))
                            let quality = percentInLower * qualityLower + (1 - percentInLower) * qualityUpper
                            qualityMin = quality < qualityMin ? quality : qualityMin
                            qualityMax = quality > qualityMax ? quality : qualityMax
                        }
                    }
                    return (qualityMin,qualityMax)
                }

                let (qualityMin,qualityMax) = computeAchievableQualityRange(constraintGoal: intent.constraint)

                let sufficientQuality = qualityMin + importance * (qualityMax - qualityMin)

                func importanceRespectingObjectiveFunction(_ scheduleMeasureAverages: [Double]) -> Double {

                    // Quality of this schedule
                    let quality = scheduleMeasureAverages[qualityMeasureIdx]
                    // If schedule does not produce a sufficiently high quality
                    if quality < sufficientQuality {
                        Log.debug("Filtering schedule with insufficient quality \(quality) < \(sufficientQuality).")
                        return subOptimalObjectiveFunctionValue
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

            // Enable logging to standard output
            self.fastController.logFile = FileHandle.standardOutput

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
        return Schedule(
            { (i: UInt32) -> KnobSettings in
                return self.model![Int(i) < s.nLowerIterations ? s.idLower : s.idUpper].knobSettings
            }, 
            oscillating: s.oscillating
        )
    }
}
