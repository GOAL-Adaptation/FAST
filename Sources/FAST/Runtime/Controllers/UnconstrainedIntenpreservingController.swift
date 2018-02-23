import Foundation
import LoggerAPI
import UnconstrainedOptimizer

class UnconstrainedIntentPreservingController : Controller {
    let model: Model? // Always defined for this Controller
    let window: UInt32
    let discreteNaiveUnconstrainedOptimizer: DiscreteNaiveUnconstrainedOptimizer<Double>
    let intent: IntentSpec

    init?(_ model: Model,
          _ intent: IntentSpec,
          _ window: UInt32) {
        let optimizationType: OptimizationType
        switch intent.optimizationType {
        case .minimize:
            optimizationType = .minimize
        case .maximize:
            optimizationType = .maximize
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
            return self.model![Int(schedule[Int(i)])].knobSettings
        })
    }
}
