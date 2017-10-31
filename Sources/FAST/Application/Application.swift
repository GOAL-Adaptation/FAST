/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic Application Protocols
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------
/** Application */

/** Generic Interface for an Application */
public protocol Application: TextApiModule {

  // Application has a name
  var name: String { get }
}

//---------------------------------------

public protocol StreamApplication {
  func initializeStream()
}
