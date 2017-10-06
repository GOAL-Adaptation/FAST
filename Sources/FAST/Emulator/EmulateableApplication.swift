/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        Emulateable Application
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------
/** Emulateable Application */

/** Generic Interface for an Emulateable Application */
public protocol EmulateableApplication: Application {

  /** Look up the id (in the database) of the current application configuration. */
  func getCurrentConfigurationId(database: Database) -> Int
}

//---------------------------------------
