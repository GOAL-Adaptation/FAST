RESOURCE_PATH := Sources/ExampleIncrementer
RESOURCE_TARGET_PATH := .build/debug
TEST_RESOURCE_TARGET_PATH := $(RESOURCE_TARGET_PATH)/FASTPackageTests.xctest/Contents/Resources
UNAME := $(shell uname)

SPM_FLAGS_ALL := \
  -Xlinker -L/usr/local/lib \
  -Xlinker -L/usr/local/opt/lapack/lib \
  -Xlinker -L/usr/local/opt/openblas/lib \
  -Xlinker -L/usr/local/opt/sqlite/lib \
  -Xlinker -lenergymon-default

ifeq ($(UNAME), Linux)
SPM_FLAGS := $(SPM_FLAGS_ALL)
endif
ifeq ($(UNAME), Darwin)
SPM_FLAGS := $(SPM_FLAGS_ALL) \
	-Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget
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

run:
	.build/debug/ExampleIncrementer

go: build run

all: rebuild run