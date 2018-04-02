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
# Are we running on the ZCU102?
ifeq ($(shell uname -m), aarch64)
  # Yes, use 32-bit swift and libraries on 64-bit ARM machine
  SPM_FLAGS := \
    -Xcc -target -Xcc armv7l-linux-gnueabihf \
    -Xcc -I/usr/local/arm-linux-gnueabihf/include \
    -Xlinker -L/usr/lib/arm-linux-gnueabihf \
    -Xlinker -L/usr/local/arm-linux-gnueabihf/lib \
    $(SPM_FLAGS_ALL)

  # Override target for clang to force 32-bit build
  export CCC_OVERRIDE_OPTIONS:=\#^--target=arm-linux-gnueabihf s/aarch64-linux-gnu/arm-linux-gnueabihf/
else
  # No, assume x86 Linux
  SPM_FLAGS := \
    -Xlinker -L/usr/local/lib \
    $(SPM_FLAGS_ALL)
endif

TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)
endif

ifeq ($(UNAME), Darwin)
SPM_FLAGS := $(SPM_FLAGS_ALL) \
	-Xlinker -L/usr/local/lib \
  -Xlinker -L/usr/local/opt/lapack/lib \
  -Xlinker -L/usr/local/opt/openblas/lib \
  -Xlinker -L/usr/local/opt/sqlite/lib \
  -Xlinker -L/usr/local/opt/sqlite3/lib \
  -Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)/FASTPackageTests.xctest/Contents/Resources
endif

build: copy-resources-build
	swift build $(SPM_FLAGS)

test: export proteus_runtime_logLevel        := Error
test: export proteus_runtime_missionLength   := 1000
test: export proteus_runtime_address         := 0.0.0.0
test: export proteus_client_rest_serverPath  := 127.0.0.1
test: export proteus_client_rest_serverPort  := 8080
test: copy-resources-test
	swift test $(SPM_FLAGS)

copy-resources-build:
	mkdir -p $(RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/${APPNAME}.* $(RESOURCE_TARGET_PATH)/

copy-resources-test:
	mkdir -p $(TEST_RESOURCE_TARGET_PATH)
	cp Sources/FAST/Emulator/Database.sql $(TEST_RESOURCE_TARGET_PATH)/
	cp Tests/FASTTests/Emulator/DatabaseTests.sql $(TEST_RESOURCE_TARGET_PATH)/
	cp $(RESOURCE_PATH)/incrementer.* $(TEST_RESOURCE_TARGET_PATH)/

clean:
	rm -rf .build/

rebuild: clean build

execute:              export proteus_runtime_sceneObfuscation                 := 0.0
execute:              export proteus_runtime_address                          := 0.0.0.0
execute:              export proteus_client_rest_serverAddress                := brass-th
execute:              export proteus_client_rest_serverPort                   := 8080
execute:              export proteus_emulator_database_db                     := ./${APPNAME}_emulation.db
execute:              export proteus_emulator_database_readingMode            := Statistics

execute:              export proteus_armBigLittle_policy                      := Simple
execute:              export proteus_armBigLittle_actuationPolicy             := Actuate
execute:              export proteus_armBigLittle_availableBigCores           := 4
execute:              export proteus_armBigLittle_availableLittleCores        := 4
execute:              export proteus_armBigLittle_maximalBigCoreFrequency     := 2000
execute:              export proteus_armBigLittle_maximalLittleCoreFrequency  := 1400
execute:              export proteus_armBigLittle_utilizedBigCores            := 4
execute:              export proteus_armBigLittle_utilizedLittleCores         := 0

execute:              export proteus_xilinxZcu_policy                         := Simple
execute:              export proteus_xilinxZcu_actuationPolicy                := NoActuation
execute:              export proteus_xilinxZcu_availableCores                 := 4
execute:              export proteus_xilinxZcu_maximalCoreFrequency           := 1200
execute:              export proteus_xilinxZcu_utilizedCores                  := 4
execute:              export proteus_xilinxZcu_utilizedCoreFrequency          := 1200

execute: copy-resources-build
	.build/debug/${APPNAME}

go:                     build run

all:                    rebuild run

run:              		export proteus_runtime_missionLength                    := 2000
run:               		export proteus_runtime_applicationExecutionMode         := Adaptive
run:               		execute

run-scripted:      		export proteus_runtime_interactionMode                  := Scripted
run-scripted:      		run

run-harness:       		export proteus_runtime_executeWithTestHarness           := true
run-harness:       		run

run-harness-scripted:   export proteus_runtime_executeWithTestHarness           := true
run-harness-scripted:   run-scripted

emulate:           		export proteus_armBigLittle_executionMode               := Emulated
emulate:           		export proteus_xilinxZcu_executionMode                  := Emulated
emulate:           		run

emulate-scripted:  		export proteus_armBigLittle_executionMode               := Emulated
emulate-scripted:     export proteus_xilinxZcu_executionMode                  := Emulated
emulate-scripted:  		run-scripted

evaluate:          		export proteus_runtime_executeWithTestHarness           := true
evaluate:          		emulate

evaluate-scripted: 		export proteus_runtime_executeWithTestHarness           := true
evaluate-scripted: 		emulate-scripted

profile:           		export proteus_runtime_logLevel                         := Info
profile:           		export proteus_runtime_applicationExecutionMode         := ExhaustiveProfiling
profile:           		export proteus_runtime_missionLength                    := 200
profile:           		build execute ## To select number of inputs to process when profiling: make size=<NUMBER_OF_RUNS> profile

profile-bounds:    		export proteus_runtime_logLevel                         := Info
profile-bounds:    		export proteus_runtime_applicationExecutionMode         := EndPointsProfiling
profile-bounds:    		export proteus_runtime_missionLength                    := 200
profile-bounds:    		build execute ## To select number of inputs to process when profiling: make size=<NUMBER_OF_RUNS> profile

trace:           		export proteus_runtime_logLevel                         := Info
trace:           		export proteus_runtime_applicationExecutionMode         := EmulatorTracing
trace:           		export proteus_runtime_missionLength                    := 200
trace:           		build execute

create-emulation-db:
	make trace; \
	make profile; \
	mv ${APPNAME}.trace.sql $(RESOURCE_PATH); \
	mv ${APPNAME}.*table $(RESOURCE_PATH); \
	sqlite3 ${APPNAME}_emulation.db < ./Sources/FAST/Emulator/Database.sql; \
	sqlite3 ${APPNAME}_emulation.db < $(RESOURCE_PATH)/${APPNAME}.trace.sql


