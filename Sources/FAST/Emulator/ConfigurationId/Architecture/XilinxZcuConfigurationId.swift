/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        ARM bigLITTLE Architecture Configuration ID
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import PerfectSQLite
import LoggerAPI

//-------------------------------


/** Xilinx ZCU 102 gets the Configuration Id from the Database*/
extension XilinxZcu {
    
    func getCurrentConfigurationId(database: Database) -> Int {
        return database.getCurrentConfigurationId(architecture: self)
    }
}

//-------------------------------
