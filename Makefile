# FAST: An implicit programing language based on SWIFT
#
#       Build script
#
# author: Adam Duracz
#

APPNAME := incrementer

UNAME := $(shell uname)
SPM_FLAGS_ALL := \
  -Xlinker -lenergymon-default

RESOURCE_PATH := Sources/${APPNAME}
RESOURCE_TARGET_PATH := .build/debug

ifeq ($(UNAME), Linux)
SPM_FLAGS := \
  -Xlinker -L/usr/local/lib \
  $(SPM_FLAGS_ALL)
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)
endif

ifeq ($(UNAME), Darwin)
SPM_FLAGS := $(SPM_FLAGS_ALL) \
	-Xlinker -L/usr/local/lib \
  -Xlinker -L/usr/local/opt/lapack/lib \
  -Xlinker -L/usr/local/opt/openblas/lib \
  -Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)/FASTPackageTests.xctest/Contents/Resources
endif

build: copy-resources-build
	swift build -Xswiftc -suppress-warnings $(SPM_FLAGS)

test: export proteus_runtime_logLevel        := Error
test: export proteus_runtime_missionLength   := 1000
test: export proteus_runtime_address         := 0.0.0.0
test: export proteus_client_rest_serverPath  := 127.0.0.1
test: export proteus_client_rest_serverPort  := 8080
test: build copy-resources-test
	swift test $(SPM_FLAGS)

copy-resources-build:
	mkdir -p $(RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/${APPNAME}.* $(RESOURCE_TARGET_PATH)/

copy-resources-test:
	mkdir -p $(TEST_RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/incrementer.* $(TEST_RESOURCE_TARGET_PATH)/

clean:
	rm -rf .build/ *.resolved

rebuild: clean build

execute:              export proteus_runtime_address                          := 0.0.0.0
execute:              export proteus_client_rest_serverAddress                := brass-th
execute:              export proteus_client_rest_serverPort                   := 8080
execute:              export proteus_emulator_emulationDatabaseType           := Dict
execute:              export proteus_emulator_database_db                     := ./${APPNAME}.trace.json
execute:              export proteus_emulator_database_readingMode            := Statistics

execute:              export proteus_runtime_collectDetailedStatistics        := false
execute:              export proteus_runtime_suppressStatus                   := false
execute:              export proteus_runtime_minimumSecondsBetweenStatuses    := 0.0
execute:              export proteus_runtime_detailedStatus                   := false
execute:              export proteus_runtime_sendStatusToTestHarness          := false
execute:              export proteus_runtime_logToMemory                      := false

execute:              export proteus_armBigLittle_policy                      := Simple
execute:              export proteus_armBigLittle_availableBigCores           := 4
execute:              export proteus_armBigLittle_availableLittleCores        := 4
execute:              export proteus_armBigLittle_maximalBigCoreFrequency     := 2000
execute:              export proteus_armBigLittle_maximalLittleCoreFrequency  := 1400
execute:              export proteus_armBigLittle_utilizedBigCores            := 4
execute:              export proteus_armBigLittle_utilizedLittleCores         := 0

execute:              export proteus_xilinxZcu_policy                         := Simple
execute:              export proteus_xilinxZcu_availableCores                 := 4
execute:              export proteus_xilinxZcu_availableCoreFrequency         := 1200
execute:              export proteus_xilinxZcu_utilizedCores                  := 4
execute:              export proteus_xilinxZcu_utilizedCoreFrequency          := 1200

execute: copy-resources-build
	.build/debug/${APPNAME}

go:                     build run

all:                    rebuild run

run:              		export proteus_runtime_missionLength                    := 2000
run:               		export proteus_runtime_applicationExecutionMode         := Adaptive
run:               		export proteus_runtime_executeWithMachineLearning       := false
run:               		execute

run-scripted:      		export proteus_runtime_interactionMode                  := Scripted
run-scripted:      		run

run-harness:       		export proteus_runtime_executeWithTestHarness           := true
run-harness:       		run

run-harness-scripted:   export proteus_runtime_executeWithTestHarness           := true
run-harness-scripted:   run-scripted

emulate:           		export proteus_armBigLittle_executionMode               := Emulated
emulate:              	export proteus_armBigLittle_actuationPolicy             := NoActuation
emulate:           		export proteus_xilinxZcu_executionMode                  := Emulated
emulate:              	export proteus_xilinxZcu_actuationPolicy                := NoActuation
emulate:           		run

emulate-scripted:		export proteus_armBigLittle_executionMode               := Emulated
emulate-scripted:		export proteus_armBigLittle_actuationPolicy             := NoActuation
emulate-scripted:		export proteus_xilinxZcu_executionMode                  := Emulated
emulate-scripted:		export proteus_xilinxZcu_actuationPolicy                := NoActuation
emulate-scripted:  		run-scripted

evaluate:          		export proteus_runtime_executeWithTestHarness           := true
evaluate:          		emulate

evaluate-scripted: 		export proteus_runtime_executeWithTestHarness           := true
evaluate-scripted: 		emulate-scripted

# Run this application and produce the ${APPNAME}.*table files that are used to control this application in adaptive mode.
profile:           		export proteus_runtime_logLevel                         := Info
profile:           		export proteus_runtime_applicationExecutionMode         := ExhaustiveProfiling
profile:           		export proteus_runtime_missionLength                    := 200
profile:           		copy-resources-build execute ## To select number of inputs to process when profiling: make size=<NUMBER_OF_RUNS> profile

profile-bounds:    		export proteus_runtime_logLevel                         := Info
profile-bounds:    		export proteus_runtime_applicationExecutionMode         := EndPointsProfiling
profile-bounds:    		export proteus_runtime_missionLength                    := 200
profile-bounds:    		copy-resources-build execute ## To select number of inputs to process when profiling: make size=<NUMBER_OF_RUNS> profile

# Run this application and record the measured data in a JSON file named ${APPNAME}.trace.json.
# This file is to be used for emulation.
trace:           		export proteus_runtime_logLevel                         := Info
trace:           		export proteus_runtime_applicationExecutionMode         := EmulatorTracing
trace:           		export proteus_runtime_missionLength                    := 200
trace:           		copy-resources-build execute
