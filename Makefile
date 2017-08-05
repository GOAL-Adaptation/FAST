# FAST: An implicit programing language based on SWIFT
#
#       Build script
#
# author: Adam Duracz
#

UNAME := $(shell uname)
SPM_FLAGS_ALL := \
  -Xlinker -L/usr/local/lib \
  -Xlinker -lenergymon-default
RESOURCE_PATH := Sources/ExampleIncrementer
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
	-Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)/FASTPackageTests.xctest/Contents/Resources
endif
	
build: copy-resources-build
	swift build $(SPM_FLAGS)

test: copy-resources-test
	swift test $(SPM_FLAGS)

copy-resources-build:
	mkdir -p $(RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/incrementer.* $(RESOURCE_TARGET_PATH)
	
copy-resources-test:
	mkdir -p $(TEST_RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/incrementer.* $(TEST_RESOURCE_TARGET_PATH)

clean:
	rm Package.pins
	rm -rf .build/

rebuild: clean build

run: proteus_runtime_applicationExecutionMode := Adaptive
run:
	.build/debug/ExampleIncrementer

go: build run
	
all: rebuild run

profile: export proteus_runtime_applicationExecutionMode := ExhaustiveProfiling
profile: export proteus_runtime_profileSize := $(if $(TEST),$(TEST),1000)
profile: build run ## To select number of inputs to process when profiling: make size=<NUMBER_OF_RUNS> profile