import Foundation
import LoggerAPI
import MulticonstrainedOptimizer

class MulticonstrainedIntentPreservingController : Controller {
    let model: Model? // Always defined for this Controller
    let window: UInt32
    let multiconstrainedLinearOptimizer: MulticonstrainedLinearOptimizer<Double>
    let intent: IntentSpec

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
        self.model = sortedModel
        self.window = window
        self.intent = intent
		let sizeOfConfigurations = model.getSizeOfConfigurations()
		let domain = sortedModel.getDomainArray().makeIterator()
        let constraintMeasureIdxs = [String](intent.constraints.keys).map { sortedModel.measureNames.index(of: $0) }
        var constraintBounds =  ([Double](intent.constraints.values))
        constraintBounds.append(Double(window))
        var constraintCoefficients = (constraintMeasureIdxs.map { c in domain.map { k in model[Int(k)].measureValues[c!] } })
        constraintCoefficients.append([Double](repeating: 1.0, count: sizeOfConfigurations))
  	    if (constraintMeasureIdxs.flatMap{ $0 }).count == constraintMeasureIdxs.count {
            self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in intent.costOrValue(model.getMeasureVectorFunction()(id))},
	        		domain: domain,
                    optimizationType: optimizationType,
                    constraintBounds: constraintBounds,
                    constraintCoefficients: constraintCoefficients 
                    )
        }
        else {
            Log.error("Intent inconsistent with active model: could not match constraint name '\(intent.constraints.keys)' stated in intent with a measure name in the active model, whose measures are: \(model.measureNames). ")
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

        let schedule = multiconstrainedLinearOptimizer.computeSchedule(window: window) // FIXME Pass meaningful tag for logging

        assert(schedule.count == window, "The size of schedule is \(schedule.count) and the window size has to be \(window)")

        return Schedule({ (i: UInt32) -> KnobSettings in
            return self.model![Int(schedule[Int(i)])].knobSettings},
		    // FIXME Implement oscillation detection
            oscillating: false)
    }
}
