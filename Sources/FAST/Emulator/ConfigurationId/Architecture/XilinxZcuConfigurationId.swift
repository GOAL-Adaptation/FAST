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

//-------------------------------

/** Xilinx ZCU 102 Configuration ID from the Database */
extension Database {

    func getConfigurationId(architecture: XilinxZcu) -> Int {

        var result: Int = 0

        let sqliteQuery =
            "SELECT SystemsConfigs.sysCfgID " + 
            "  FROM  Xilinx_Zcu " +
            "        INNER JOIN SystemsConfigs ON SystemsConfigs.coreMask = ARM_bigLITTLE_knob_CoreMasks.coreMask " + 
            "        INNER JOIN Systems ON Systems.sysID = SystemsConfigs.sysID " + 
            " " + 
            " WHERE  Systems.sysName = :1 " + 
            "   AND  XilinxZcu.cores = :2 " + 
            "   AND  XilinxZcu.core_freq = :3 "

        do {
	
	        try database.forEachRow(statement: sqliteQuery, doBindings: {
		
		        (statement: SQLiteStmt) -> () in
		
		            try statement.bind(position: 1, architecture.name)
                    try statement.bind(position: 2, architecture.systemConfigurationKnobs.utilizedCores.get())
                    try statement.bind(position: 3, architecture.systemConfigurationKnobs.utilizedCoreFrequency.get())
		
	            })  {(statement: SQLiteStmt, i:Int) -> () in

                        result = statement.columnInt(position: 0)
                
                    }
	
        } catch {
	        
        }

        return result
    }
}

/** Xilinx ZCU 102 gets the Configuration Id from the Database*/
extension XilinxZcu {
    
    func getConfigurationId(database: Database) -> Int {
        return database.getConfigurationId(architecture: self)
    }
}

//-------------------------------
