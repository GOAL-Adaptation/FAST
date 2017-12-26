/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        API to controllers.
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

protocol Controller {
    var model: Model? { get }
    var window: UInt32 { get }

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule
}
