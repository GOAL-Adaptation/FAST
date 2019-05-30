import Foundation
import LoggerAPI
import MulticonstrainedOptimizer

fileprivate let key = ["proteus","runtime"]

class MulticonstrainedIntentPreservingController : Controller {
    let model: Model? // Always defined for this Controller
    let window: UInt32
    var multiconstrainedLinearOptimizer: MulticonstrainedLinearOptimizer<Double>
    let intent: IntentSpec
    let constraintsLessOrEqualTo: [String : (Double, ConstraintType)]
    let constraintsGreaterOrEqualTo: [String : (Double, ConstraintType)]
    let constraintsEqualTo: [String : (Double, ConstraintType)]
    let constraintMeasureIdxs: [Int]
    let constraintMeasureIdxsLEQ: [Int]
    let constraintMeasureIdxsGEQ: [Int]
    let constraintMeasureIdxsEQ: [Int]
    let constraintBoundsLessOrEqualTo: [Double]
    let constraintBoundsGreaterOrEqualTo: [Double]
    var constraintBoundsEqualTo: [Double]
    var constraintCoefficientsLessOrEqualTo: [[Double]]
    var constraintCoefficientsGreaterOrEqualTo: [[Double]]
    var constraintCoefficientsEqualTo: [[Double]]
    let sizeOfConfigurations: Int
    let domain: IndexingIterator<Array<UInt32>>
    var lastSchedule: [UInt32]?
    var lastMeasureValues: [Int : [String : Double]]

    init?(_ model: Model,
          _ intent: IntentSpec,
          _ window: UInt32) {
        assert(intent.constraints.count > 0, "Multiconstraint controller only works when there are non-zero constraints.")
        let sortedModel = model.sorted(by: intent.constraints.keys.first!)
        let optimizationType: OptimizationType
        switch intent.optimizationType {
        case .minimize:
            optimizationType = .minimize
        case .maximize:
            optimizationType = .maximize
        }
        let domain = sortedModel.getDomainArray().makeIterator()
        self.model = sortedModel
        self.window = window
        self.intent = intent
        self.domain = domain
        sizeOfConfigurations = model.getSizeOfConfigurations()

        constraintsLessOrEqualTo = intent.constraints.filter {$0.1.1 == .lessOrEqualTo}
        constraintsGreaterOrEqualTo = intent.constraints.filter {$0.1.1 == .greaterOrEqualTo}
        constraintsEqualTo = intent.constraints.filter {$0.1.1 == .equalTo}
        constraintMeasureIdxs = [String](intent.constraints.keys).map { sortedModel.measureNames.index(of: $0)! }
        constraintMeasureIdxsLEQ = [String](constraintsLessOrEqualTo.keys).map { sortedModel.measureNames.index(of: $0)! }
        constraintMeasureIdxsGEQ = [String](constraintsGreaterOrEqualTo.keys).map { sortedModel.measureNames.index(of: $0)! }
        constraintMeasureIdxsEQ = [String](constraintsEqualTo.keys).map { sortedModel.measureNames.index(of: $0)! }
        constraintBoundsLessOrEqualTo =  [Double](constraintsLessOrEqualTo.values.map { $0.0 })
        constraintBoundsGreaterOrEqualTo =  [Double](constraintsGreaterOrEqualTo.values.map { $0.0 })
        constraintBoundsEqualTo =  [Double](constraintsEqualTo.values.map { $0.0 })
        constraintBoundsEqualTo.append(Double(1.0))
        constraintCoefficientsLessOrEqualTo = (constraintMeasureIdxsLEQ.map { c in domain.map { k in sortedModel[Int(k)].measureValues[c] } })
        constraintCoefficientsGreaterOrEqualTo = (constraintMeasureIdxsGEQ.map { c in domain.map { k in sortedModel[Int(k)].measureValues[c] } })
        constraintCoefficientsEqualTo = (constraintMeasureIdxsEQ.map { c in domain.map { k in sortedModel[Int(k)].measureValues[c] } })
        constraintCoefficientsEqualTo.append([Double](repeating: 1.0, count: sizeOfConfigurations)) 
        
        if (constraintMeasureIdxs.flatMap{ $0 }).count == constraintMeasureIdxs.count {
            switch intent.optimizationType { 
            case .maximize:
                self.multiconstrainedLinearOptimizer =
                    MulticonstrainedLinearOptimizer<Double>( 
                        objectiveFunction: {(id: UInt32) -> Double in intent.costOrValue(sortedModel.getMeasureVectorFunction()(id))},
                        domain: domain,
                        optimizationType: .maximize,
                        constraintBoundslt: constraintBoundsLessOrEqualTo,
                        constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                        constraintBoundseq: constraintBoundsEqualTo,
                        constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                        constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                        constraintCoefficientseq: constraintCoefficientsEqualTo
                        )
            case .minimize:
                self.multiconstrainedLinearOptimizer =
                    MulticonstrainedLinearOptimizer<Double>( 
                        objectiveFunction: {(id: UInt32) -> Double in -(intent.costOrValue(sortedModel.getMeasureVectorFunction()(id)))},
                        domain: domain,
                        optimizationType: .maximize,
                        constraintBoundslt: constraintBoundsLessOrEqualTo,
                        constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                        constraintBoundseq: constraintBoundsEqualTo,
                        constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                        constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                        constraintCoefficientseq: constraintCoefficientsEqualTo
                        )
            }
        }
        else {
            Log.error("Intent inconsistent with active model: could not match constraint name '\(intent.constraints.keys)' stated in intent with a measure name in the active model, whose measures are: \(sortedModel.measureNames). ")
            exit(1)
            return nil
        }

        //FIXME An alternative implementation should allow controller to update the current model itself
        lastMeasureValues = [Int: [String : Double]]()
        for i in 0..<sizeOfConfigurations {
            lastMeasureValues[i] = Dictionary(uniqueKeysWithValues: zip(sortedModel.measureNames, sortedModel[i].measureValues))
        }
    } 

    /** Update coefficients for our linear optimizer according to a customary statistical model:
        new estimate = (weight * estimated discepency + (1-weight)) * previous estimate
        where estimated discrepency = current measure / estimated measure for last schedule */
    func updateCoefficients(weight: Double, measureValues: [String : Double]) {
        assert(lastSchedule != nil, "You can only update coefficients when there is at least one schedule run.")
        
        // Estimating discrepency
        for (key, value) in measureValues {
            if model!.measureNames.contains(key) {
                var estimatedMeasure = 0.0 // estimate the expected measure value for last schedule from the measure value table
                for configurationId in lastSchedule! {
                    estimatedMeasure += lastMeasureValues[Int(configurationId)]![key]!
                }

                estimatedMeasure /= Double(lastSchedule!.count)

                for i in 0..<sizeOfConfigurations {
                    if estimatedMeasure != 0.0 {
                       lastMeasureValues[i]![key]! *= (weight * (value / estimatedMeasure) + (1.0 - weight))
                    }
                    else {
                        Log.warning("estimatedMeasure was 0.0, not updaing lastMeasureValues[\(i)][\(key)]")
                    }
                }
            }
        }

        // Updating the optimization solver
        constraintCoefficientsLessOrEqualTo = (constraintMeasureIdxsLEQ.map { c in domain.map { k in lastMeasureValues[Int(k)]![model!.measureNames[c]]! } })
        constraintCoefficientsGreaterOrEqualTo = (constraintMeasureIdxsGEQ.map { c in domain.map { k in lastMeasureValues[Int(k)]![model!.measureNames[c]]! } })
        constraintCoefficientsEqualTo = (constraintMeasureIdxsEQ.map { c in domain.map { k in lastMeasureValues[Int(k)]![model!.measureNames[c]]! } })
        constraintCoefficientsEqualTo.append([Double](repeating: 1.0, count: sizeOfConfigurations)) 
        let measureVectorFunction = {(id: UInt32) in Array(self.lastMeasureValues[Int(id)]!.values)}
        let costOrValue = intent.costOrValue
        
        switch intent.optimizationType { 
        case .maximize:
            self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in costOrValue(measureVectorFunction(id))}, 
                    domain: domain,
                    optimizationType: .maximize,
                    constraintBoundslt: constraintBoundsLessOrEqualTo,
                    constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                    constraintBoundseq: constraintBoundsEqualTo,
                    constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                    constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                    constraintCoefficientseq: constraintCoefficientsEqualTo
                    )
        case .minimize:
            self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in costOrValue(measureVectorFunction(id))},
                    domain: domain,
                    optimizationType: .maximize,
                    constraintBoundslt: constraintBoundsLessOrEqualTo,
                    constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                    constraintBoundseq: constraintBoundsEqualTo,
                    constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                    constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                    constraintCoefficientseq: constraintCoefficientsEqualTo
                    )
        }        
    }
    
    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
       let weight = initialize(type: Double.self, name: "weightForFeedbackControl", from: key, or: 0.1)
       if lastSchedule != nil {
            updateCoefficients(weight: weight, measureValues: measureValues)
        }
        let schedule = multiconstrainedLinearOptimizer.computeSchedule(window: window) // FIXME Pass meaningful tag for logging
        assert(schedule.count == window, "The size of schedule is \(schedule.count) and the window size has to be \(window)")
        lastSchedule = schedule

        return Schedule({ (i: UInt32) -> KnobSettings in
            return self.model![Int(schedule[Int(i)])].knobSettings},
            // FIXME Implement oscillation detection
            oscillating: false)
    }
}
