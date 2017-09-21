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

import SQLite
import LoggerAPI

//-------------------------------

/** ARM bigLITTLE Configuration ID from the Database */
extension Database {

    func getConfigurationId(architecture: ArmBigLittle) -> Int {

        var result: Int = 0

        let sqliteQuery =
            "SELECT SystemsConfigs.sysCfgID " + 
            "  FROM  ARM_bigLITTLE_knob_CoreMasks " +
            "        INNER JOIN SystemsConfigs ON SystemsConfigs.coreMask = ARM_bigLITTLE_knob_CoreMasks.coreMask " + 
            "        INNER JOIN Systems ON Systems.sysID = SystemsConfigs.sysID " + 
            " " + 
            " WHERE  Systems.sysName = :1 " + 
            "   AND  ARM_bigLITTLE_knob_CoreMasks.big_cores = :2 " + 
            "   AND  ARM_bigLITTLE_knob_CoreMasks.LITTLE_cores = :3 " + 
            "   AND  SystemsConfigs.big_Freq = :4 " + 
            "   AND  SystemsConfigs.LITTLE_Freq = :5"

        do {
	
	        try database.forEachRow(statement: sqliteQuery, doBindings: {
		
		        (statement: SQLiteStmt) -> () in
		
		            try statement.bind(position: 1, architecture.name)
                    try statement.bind(position: 2, architecture.systemConfigurationKnobs.utilizedBigCores.get())
                    try statement.bind(position: 3, architecture.systemConfigurationKnobs.utilizedLittleCores.get())
                    try statement.bind(position: 4, architecture.systemConfigurationKnobs.utilizedBigCoreFrequency.get())
                    try statement.bind(position: 5, architecture.systemConfigurationKnobs.utilizedLittleCoreFrequency.get())
	
	            })  {(statement: SQLiteStmt, i:Int) -> () in

                        result = statement.columnInt(position: 0)
                
                    }
	
        } catch let exception {
	        Log.error("Failed to read the ARM bigLITTLE Configuration ID from the emulation database: \(exception).")
            fatalError()
        }
        
        return result
    }
}

/** ARM bigLITTLE gets the Configuration Id from the Database*/
extension ArmBigLittle {
    
    func getConfigurationId(database: Database) -> Int {
        return database.getConfigurationId(architecture: self)
    }
}

//-------------------------------
