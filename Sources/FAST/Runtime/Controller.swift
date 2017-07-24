import FASTController

protocol Controller {

    var model: Model { get }
    var window: UInt32 { get }

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule

}

class ConstantController : Controller {

    let model = Model()

    let window: UInt32 = 1

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
        return Schedule({ (_: UInt32) -> KnobSettings in 
            return KnobSettings([:]) 
        })
    }

}

class IntentPreservingController : Controller {

    let model: Model
    let window: UInt32
    let fastController: FASTController

    init(_ model: Model,
         _ intent: IntentSpec,
         _ window: UInt32) {
        self.model = model.sorted(by: intent.constraintName)
        self.window = window
        let constraintMeasureIdx = model.measureNames.index(of: intent.constraintName)! // FIXME Add error handling
        self.fastController = 
            FASTController( model: model.getFASTControllerModel()
                          , constraint: intent.constraint
                          , constraintMeasureIdx: constraintMeasureIdx
                          , window: window
                          , optType: intent.optimizationType
                          , ocb: intent.costOrValue
                          , initialModelEntryIdx: model.initialConfigurationIndex!
                          )
    }

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
        // FIXME Replace global measure store with custom ordered collection that avoids this conversion
        var values = [Double]()
        for measureName in model.measureNames {
            if let v = measureValues[measureName] {
                values.append(v)
            }
            else {
                fatalError("Measure '\(measureName)', present in model, has not been registered in the application.") 
            }
        }
        let s = fastController.computeSchedule(tag: 0, measures: values) // FIXME Pass meaningful tag for logging
        return Schedule({ (i: UInt32) -> KnobSettings in 
            return self.model[Int(i) < s.nLowerIterations ? s.idLower : s.idUpper].knobSettings
        })
    }

}
