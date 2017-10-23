/* Disable foreign keys */
PRAGMA foreign_keys = 'off';

/* Begin transaction */
BEGIN;

/* Database properties */
PRAGMA auto_vacuum = 0;
PRAGMA encoding = 'UTF-8';
PRAGMA page_size = 4096;

/* Drop table [Application] */
DROP TABLE IF EXISTS [main].[Application];

/* Table structure [Application] */
CREATE TABLE [main].[Application](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [name] TEXT UNIQUE, 
    [warmupInputNum] INTEGER);

/* Drop table [ApplicationConfiguration] */
DROP TABLE IF EXISTS [main].[ApplicationConfiguration];

/* Table structure [ApxplicationConfiguration] */
CREATE TABLE [main].[ApplicationConfiguration](
    [id] INTEGER PRIMARY KEY, 
    [description] TEXT);

/* Drop table [ApplicationConfiguration_Application_Knob] */
DROP TABLE IF EXISTS [main].[ApplicationConfiguration_Application_Knob];

/* Table structure [ApplicationConfiguration_Application_Knob] */
CREATE TABLE [main].[ApplicationConfiguration_Application_Knob](
    [id] INTEGER PRIMARY KEY, 
    [applicationConfigurationId] INTEGER REFERENCES ApplicationConfiguration([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [applicationKnobId] INTEGER REFERENCES Application_Knob([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [knobValue] TEXT, 
    UNIQUE([applicationConfigurationId], [applicationKnobId]));

/* Drop table [ApplicationInputStream] */
DROP TABLE IF EXISTS [main].[ApplicationInputStream];

/* Table structure [ApplicationInputStream] */
CREATE TABLE [main].[ApplicationInputStream](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [name] TEXT NOT NULL, 
    [applicationId] INTEGER NOT NULL REFERENCES Application([id]) ON DELETE CASCADE ON UPDATE CASCADE);

/* Drop table [ApplicationInputStream_ApplicationConfiguration] */
DROP TABLE IF EXISTS [main].[ApplicationInputStream_ApplicationConfiguration];

/* Table structure [ApplicationInputStream_ApplicationConfiguration] */
CREATE TABLE [main].[ApplicationInputStream_ApplicationConfiguration](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [applicationInputId] INTEGER CONSTRAINT [lnk_ApplicationInput_AppicationInput_ApplicationConfiguration_Application_knob] REFERENCES ApplicationInputStream([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [applicationConfigurationID] INTEGER REFERENCES ApplicationConfiguration([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    CONSTRAINT [unique_id] UNIQUE([applicationInputId], [applicationConfigurationID]));

/* Drop table [ApplicationSystemInputLog] */
DROP TABLE IF EXISTS [main].[ApplicationSystemInputLog];

/* Table structure [ApplicationSystemInputLog] */
CREATE TABLE [main].[ApplicationSystemInputLog](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [applicationInputStream_applicationConfigurationId] INTEGER NOT NULL REFERENCES ApplicationInputStream_ApplicationConfiguration([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [systemConfigurationId] INTEGER NOT NULL REFERENCES SystemConfiguration([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [inputNumber] INTEGER NOT NULL, 
    [deltaTime] INTEGER, 
    [deltaEnergy] INTEGER, 
    CONSTRAINT [unique_applicationConfiguration_Application_KnobId_systemConfigurationId_inputNumber] UNIQUE([applicationInputStream_applicationConfigurationId], [systemConfigurationId], [inputNumber]));

/* Drop table [Application_Knob] */
DROP TABLE IF EXISTS [main].[Application_Knob];

/* Table structure [Application_Knob] */
CREATE TABLE [main].[Application_Knob](
    [id] INTEGER PRIMARY KEY, 
    [applicationId] INTEGER REFERENCES Application([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [knobId] INTEGER REFERENCES Knob([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [knobType] TEXT, 
    [knobReferenceValue] TEXT, 
    UNIQUE([applicationId], [knobId]));

/* Drop table [JobLogParameter] */
DROP TABLE IF EXISTS [main].[JobLogParameter];

/* Table structure [JobLogParameter] */
CREATE TABLE [main].[JobLogParameter](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [applicationId] INTEGER REFERENCES Application([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [energyOutlier] DOUBLE, 
    [tapeNoise] DOUBLE, 
    [timeOutlier] DOUBLE);

/* Drop table [Knob] */
DROP TABLE IF EXISTS [main].[Knob];

/* Table structure [Knob] */
CREATE TABLE [main].[Knob](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [name] TEXT NOT NULL UNIQUE);

/* Drop table [System] */
DROP TABLE IF EXISTS [main].[System];

/* Table structure [System] */
CREATE TABLE [main].[System](
    [id] INTEGER PRIMARY KEY NOT NULL, 
    [name] TEXT NOT NULL);

/* Drop table [SystemConfiguration] */
DROP TABLE IF EXISTS [main].[SystemConfiguration];

/* Table structure [SystemConfiguration] */
CREATE TABLE [main].[SystemConfiguration](
    [id] INTEGER PRIMARY KEY, 
    [description] TEXT);

/* Drop table [SystemConfiguration_System_Knob] */
DROP TABLE IF EXISTS [main].[SystemConfiguration_System_Knob];

/* Table structure [SystemConfiguration_System_Knob] */
CREATE TABLE [main].[SystemConfiguration_System_Knob](
    [id] INTEGER PRIMARY KEY, 
    [systemKnobId] INTEGER REFERENCES System_Knob([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [systemConfigurationId] INTEGER REFERENCES SystemConfiguration([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [knobValue] TEXT, 
    UNIQUE([systemKnobId], [systemConfigurationId]));

/* Drop table [System_Knob] */
DROP TABLE IF EXISTS [main].[System_Knob];

/* Table structure [System_Knob] */
CREATE TABLE [main].[System_Knob](
    [id] INTEGER PRIMARY KEY, 
    [systemId] INTEGER REFERENCES System([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [knobId] INTEGER REFERENCES Knob([id]) ON DELETE CASCADE ON UPDATE CASCADE, 
    [knobType] TEXT, 
    [knobReferenceValue] TEXT, 
    UNIQUE([systemId], [knobId]));

/* Commit transaction */
COMMIT;

/* Enable foreign keys */
PRAGMA foreign_keys = 'on';