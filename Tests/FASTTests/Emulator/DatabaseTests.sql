/* Disable foreign keys */
PRAGMA foreign_keys = 'off';

-- /* Begin transaction */
BEGIN;

/* Table data [Application] Record count: 4 */
INSERT INTO [Application]([rowid], [id], [name], [warmupInputNum]) VALUES(0, 0, 'RADAR', 2);
INSERT INTO [Application]([rowid], [id], [name], [warmupInputNum]) VALUES(1, 1, 'CaPSuLe', 2);
INSERT INTO [Application]([rowid], [id], [name], [warmupInputNum]) VALUES(2, 2, 'x264', 1);
INSERT INTO [Application]([rowid], [id], [name], [warmupInputNum]) VALUES(3, 3, 'incrementer', 2);

/* Table data [ApplicationConfiguration] Record count: 9 */
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(6, 6, 'Radar config ref');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(7, 7, 'x264 config ref');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(8, 8, 'Radar config 8');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(9, 9, 'Radar config 9');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(10, 10, 'Radar config 10');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(11, 11, 'x264 config 11');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(12, 12, 'x264 config 12');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(13, 13, 'incrementer config ref');
INSERT INTO [ApplicationConfiguration]([rowid], [id], [description]) VALUES(14, 14, 'incrementer config 14');

/* Table data [ApplicationConfiguration_Application_Knob] Record count: 29 */
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(1, 1, 8, 11, '1');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(2, 2, 9, 11, '4');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(3, 3, 10, 11, '8');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(4, 4, 9, 12, '2');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(5, 5, 8, 12, '4');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(6, 6, 10, 12, '8');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(7, 7, 10, 14, '1024');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(8, 8, 9, 14, '2048');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(9, 9, 8, 13, '8');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(10, 10, 9, 13, '32');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(11, 11, 6, 14, '64');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(12, 12, 11, 15, '4');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(13, 13, 12, 15, '5');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(14, 14, 12, 17, '1');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(15, 15, 11, 17, '2');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(16, 16, 7, 16, '1');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(17, 17, 11, 16, '2');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(18, 18, 7, 15, '12');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(19, 19, 7, 17, '7');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(20, 20, 6, 11, '1');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(21, 21, 6, 12, '1');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(22, 22, 6, 13, '8192');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(24, 24, 8, 14, '64');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(25, 25, 10, 13, '8192');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(26, 26, 12, 16, '10');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(27, 27, 13, 18, '10000000');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(28, 28, 13, 19, '1');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(29, 29, 14, 18, '12000000');
INSERT INTO [ApplicationConfiguration_Application_Knob]([rowid], [id], [applicationConfigurationId], [applicationKnobId], [knobValue]) VALUES(30, 30, 14, 19, '2');

/* Table data [ApplicationInputStream] Record count: 5 */
INSERT INTO [ApplicationInputStream]([rowid], [id], [name], [applicationId]) VALUES(1, 1, 'radar cmd1', 0);
INSERT INTO [ApplicationInputStream]([rowid], [id], [name], [applicationId]) VALUES(2, 2, 'radar cmd2', 0);
INSERT INTO [ApplicationInputStream]([rowid], [id], [name], [applicationId]) VALUES(3, 3, 'x264 cmd1', 2);
INSERT INTO [ApplicationInputStream]([rowid], [id], [name], [applicationId]) VALUES(4, 4, 'capsule cmd1', 1);
INSERT INTO [ApplicationInputStream]([rowid], [id], [name], [applicationId]) VALUES(5, 5, 'incrementer cmd1', 3);

/* Table data [ApplicationInputStream_ApplicationConfiguration] Record count: 4 */
INSERT INTO [ApplicationInputStream_ApplicationConfiguration]([rowid], [id], [applicationInputId], [applicationConfigurationID]) VALUES(1, 1, 1, 8);
INSERT INTO [ApplicationInputStream_ApplicationConfiguration]([rowid], [id], [applicationInputId], [applicationConfigurationID]) VALUES(2, 2, 1, 6);
INSERT INTO [ApplicationInputStream_ApplicationConfiguration]([rowid], [id], [applicationInputId], [applicationConfigurationID]) VALUES(3, 3, 3, 7);
INSERT INTO [ApplicationInputStream_ApplicationConfiguration]([rowid], [id], [applicationInputId], [applicationConfigurationID]) VALUES(4, 4, 5, 13);

/* Table data [ApplicationSystemInputLog] Record count: 11 */
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(1, 1, 1, 1, 1, 2300, 1200);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(2, 2, 1, 1, 2, 2400, 1300);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(3, 3, 1, 1, 3, 2500, 1400);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(4, 4, 2, 1, 1, 2000, 1100);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(5, 5, 2, 1, 2, 2100, 1150);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(6, 6, 2, 1, 3, 2200, 1250);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(7, 7, 3, 1, 1, 5500, 4000);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(8, 8, 3, 1, 2, 5700, 4100);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(9, 9, 4, 2, 1, 3100, 2100);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(10, 10, 4, 2, 2, 3250, 2230);
INSERT INTO [ApplicationSystemInputLog]([rowid], [id], [applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber], [deltaTime], [deltaEnergy]) VALUES(11, 11, 4, 2, 3, 3430, 2400);

/* Table data [Application_Knob] Record count: 9 */
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(11, 11, 0, 1, 'INTEGER', '1');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(12, 12, 0, 2, 'INTEGER', '1');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(13, 13, 0, 4, 'INTEGER', '8192');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(14, 14, 0, 7, 'INTEGER', '64');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(15, 15, 2, 3, 'INTEGER', '12');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(16, 16, 2, 6, 'INTEGER', '1');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(17, 17, 2, 5, 'INTEGER', '7');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(18, 18, 3, 13, 'INTEGER', '10000000');
INSERT INTO [Application_Knob]([rowid], [id], [applicationId], [knobId], [knobType], [knobReferenceValue]) VALUES(19, 19, 3, 14, 'INTEGER', '1');

/* Table data [JobLogParameter] Record count: 3 */
INSERT INTO [JobLogParameter]([rowid], [id], [applicationId], [energyOutlier], [tapeNoise], [timeOutlier]) VALUES(1, 1, 0, 64, 0.001953125, 16);
INSERT INTO [JobLogParameter]([rowid], [id], [applicationId], [energyOutlier], [tapeNoise], [timeOutlier]) VALUES(2, 2, 2, 65, 0.001953567, 17);
INSERT INTO [JobLogParameter]([rowid], [id], [applicationId], [energyOutlier], [tapeNoise], [timeOutlier]) VALUES(3, 3, 3, 66, 0.001953213, 18);

/* Table data [Knob] Record count: 14 */
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(1, 1, 'cdr');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(2, 2, 'fdr');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(3, 3, 'me');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(4, 4, 'numBeams');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(5, 5, 'subMe');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(6, 6, 'referenceFrames');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(7, 7, 'numRanges');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(8, 8, 'bigFrequency');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(9, 9, 'littleFrequency');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(10, 10, 'coreMask');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(11, 11, 'utilizedCores');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(12, 12, 'utilizedCoreFrequency');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(13, 13, 'threshold');
INSERT INTO [Knob]([rowid], [id], [name]) VALUES(14, 14, 'step');

/* Table data [System] Record count: 2 */
INSERT INTO [System]([rowid], [id], [name]) VALUES(0, 0, 'ARM-big.LITTLE');
INSERT INTO [System]([rowid], [id], [name]) VALUES(1, 1, 'XilinxZcu');

/* Table data [SystemConfiguration] Record count: 8 */
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(1, 1, 'ODROID config ref');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(2, 2, 'Xilinx config ref');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(3, 3, 'ODROID config 3');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(4, 4, 'Xilinx config 4');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(5, 5, 'ODROID foo');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(13, 13, 'ODROID bar 2');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(15, 15, 'some description');
INSERT INTO [SystemConfiguration]([rowid], [id], [description]) VALUES(17, 17, '');

/* Table data [SystemConfiguration_System_Knob] Record count: 14 */
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(1, 1, 1, 1, '2000000');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(2, 2, 2, 1, '1400000');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(3, 3, 4, 1, '0xF0');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(4, 4, 5, 2, '4');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(5, 5, 6, 2, '1200');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(6, 6, 1, 3, '400000');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(7, 7, 2, 3, '1400000');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(8, 8, 4, 3, '0xF');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(9, 9, 5, 4, '3');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(10, 10, 6, 4, '400');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(11, 11, 1, 5, '2000000');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(12, 12, 2, 5, '1400000');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(13, 13, 4, 5, '0xF');
INSERT INTO [SystemConfiguration_System_Knob]([rowid], [id], [systemKnobId], [systemConfigurationId], [knobValue]) VALUES(14, 14, 1, 13, '2000000');

/* Table data [System_Knob] Record count: 5 */
INSERT INTO [System_Knob]([rowid], [id], [systemId], [knobId], [knobType], [knobReferenceValue]) VALUES(1, 1, 0, 8, 'INTEGER', '2000000');
INSERT INTO [System_Knob]([rowid], [id], [systemId], [knobId], [knobType], [knobReferenceValue]) VALUES(2, 2, 0, 9, 'INTEGER', '1400000');
INSERT INTO [System_Knob]([rowid], [id], [systemId], [knobId], [knobType], [knobReferenceValue]) VALUES(4, 4, 0, 10, 'TEXT', '0xF0');
INSERT INTO [System_Knob]([rowid], [id], [systemId], [knobId], [knobType], [knobReferenceValue]) VALUES(5, 5, 1, 11, 'INTEGER', '4');
INSERT INTO [System_Knob]([rowid], [id], [systemId], [knobId], [knobType], [knobReferenceValue]) VALUES(6, 6, 1, 12, 'INTEGER', '1200');

-- /* Commit transaction */
COMMIT;

/* Enable foreign keys */
PRAGMA foreign_keys = 'on';