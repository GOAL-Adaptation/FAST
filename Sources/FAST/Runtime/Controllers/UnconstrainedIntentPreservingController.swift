import Foundation
import LoggerAPI
import enum UnconstrainedOptimizer.OptimizationType
import UnconstrainedOptimizer

class UnconstrainedIntentPreservingController : Controller {
    let model: Model? // Always defined for this Controller
    let window: UInt32
    let discreteNaiveUnconstrainedOptimizer: DiscreteNaiveUnconstrainedOptimizer<Double>
    let intent: IntentSpec

    init?(_ model: Model,
          _ intent: IntentSpec,
          _ window: UInt32) {
        assert(intent.constraints.count == 0, "Unconstrained controller only works when there is no constraints.")
		let optimizationType: UnconstrainedOptimizer.OptimizationType
        switch intent.optimizationType {
        case .minimize:
            optimizationType = UnconstrainedOptimizer.OptimizationType.minimize
        case .maximize:
            optimizationType = UnconstrainedOptimizer.OptimizationType.maximize
        }
        self.model = model
        self.window = window
        self.intent = intent
        self.discreteNaiveUnconstrainedOptimizer =
            DiscreteNaiveUnconstrainedOptimizer<Double>( 
                objectiveFunction: {(x: UInt32) -> Double in intent.costOrValue(model.getMeasureVectorFunction()(x))},
                domain: model.getDomainArray().makeIterator(),
                optimizationType: optimizationType
                )
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

        let schedule = discreteNaiveUnconstrainedOptimizer.computeSchedule(window: window) // FIXME Pass meaningful tag for logging
        
        return Schedule({ (i: UInt32) -> KnobSettings in
            return self.model![Int(schedule[Int(i)])].knobSettings},
		// FIXME Implement oscillation detection
            oscillating: false) 
    }
}
