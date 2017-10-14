# FAST: An implicit programing language based on SWIFT
#
#       Build script
#
# author: Adam Duracz
#

APPNAME := incrementer

UNAME := $(shell uname)
SPM_FLAGS_ALL := \
  -Xlinker -L/usr/local/lib \
  -Xlinker -lenergymon-default
RESOURCE_PATH := Sources/${APPNAME}
RESOURCE_TARGET_PATH := .build/debug

ifeq ($(UNAME), Linux)
SPM_FLAGS := $(SPM_FLAGS_ALL)
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)
endif
ifeq ($(UNAME), Darwin)
SPM_FLAGS := $(SPM_FLAGS_ALL) \
  -Xlinker -L/usr/local/opt/lapack/lib \
  -Xlinker -L/usr/local/opt/openblas/lib \
  -Xlinker -L/usr/local/opt/sqlite/lib \
  -Xlinker -L/usr/local/opt/sqlite3/lib \
  -Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)/FASTPackageTests.xctest/Contents/Resources
endif
	
build: copy-resources-build
	swift build $(SPM_FLAGS)

test: export proteus_runtime_logLevel           := Error
test: export proteus_runtime_inputsToProcess    := 1000
test: export proteus_client_rest_serverAddress  := 127.0.0.1
test: export proteus_client_rest_serverPort     := 8080
test: copy-resources-test
	swift test $(SPM_FLAGS)

copy-resources-build:
	mkdir -p $(RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/${APPNAME}.* $(RESOURCE_TARGET_PATH)/
	
copy-resources-test:
	mkdir -p $(TEST_RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/${APPNAME}.* $(TEST_RESOURCE_TARGET_PATH)/

clean:
	rm Package.pins
	rm -rf .build/

rebuild: clean build

execute:              export proteus_runtime_inputsToProcess                  := 100
execute:              export proteus_runtime_missionLength                    := 1000
execute:              export proteus_runtime_sceneObfuscation                 := 0.0
execute:              export proteus_client_rest_serverAddress                := brass-th
execute:              export proteus_client_rest_serverPort                   := 8080
execute:              export proteus_emulator_database_db                     := /Users/adam/project/FAST/Sources/ExampleIncrementer/incrementer.db
execute:              export proteus_emulator_database_readingMode            := Statistics
execute:              export proteus_armBigLittle_policy                      := Simple
execute:              export proteus_armBigLittle_actuationPolicy             := Actuate
execute:              export proteus_armBigLittle_availableBigCores           := 4
execute:              export proteus_armBigLittle_availableLittleCores        := 4
execute:              export proteus_armBigLittle_maximalBigCoreFrequency     := 2000000
execute:              export proteus_armBigLittle_maximalLittleCoreFrequency  := 1400000
execute:              export proteus_armBigLittle_utilizedBigCores            := 4
execute:              export proteus_armBigLittle_utilizedLittleCores         := 0
execute:              export proteus_armBigLittle_utilizedBigCoreFrequency    := 2000000
execute:              export proteus_armBigLittle_utilizedLittleCoreFrequency := 1400000
execute: copy-resources-build
	.build/debug/${APPNAME}

go:                     build run

all:                    rebuild run

run:               		export proteus_runtime_applicationExecutionMode         := Adaptive
run:               		execute

run-scripted:      		export proteus_runtime_interactionMode                  := Scripted
run-scripted:      		run

run-harness:       		export proteus_runtime_executeWithTestHarness           := true
run-harness:       		run

run-harness-scripted:   export proteus_runtime_executeWithTestHarness           := true
run-harness-scripted:   run-scripted
                                                                              
emulate:           		export proteus_armBigLittle_executionMode               := Emulated
emulate:           		run

emulate-scripted:  		export proteus_armBigLittle_executionMode               := Emulated
emulate-scripted:  		run-scripted

evaluate:          		export proteus_runtime_executeWithTestHarness           := true
evaluate:          		emulate

evaluate-scripted: 		export proteus_runtime_executeWithTestHarness           := true
evaluate-scripted: 		emulate-scripted

profile:           		export proteus_runtime_logLevel                         := Info
profile:           		export proteus_runtime_applicationExecutionMode         := ExhaustiveProfiling
profile:           		export proteus_runtime_profileSize                      := $(if $(TEST),$(TEST),100)
profile:           		build execute ## To select number of inputs to process when profiling: make size=<NUMBER_OF_RUNS> profile
