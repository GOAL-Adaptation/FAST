RESOURCE_PATH=Sources/ExampleIncrementer
RESOURCE_TARGET_PATH=.build/debug
TEST_RESOURCE_TARGET_PATH=$(RESOURCE_TARGET_PATH)/FASTPackageTests.xctest/Contents/Resources

build: copy-resources-build
	swift build \
	  -Xlinker -L/usr/local/lib \
	  -Xlinker -L/usr/local/opt/lapack/lib \
	  -Xlinker -L/usr/local/opt/openblas/lib \
	  -Xlinker -L/usr/local/opt/sqlite/lib \
	  -Xlinker -lenergymon-default \
	  -Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget

test: copy-resources-test
	swift test \
	  -Xlinker -L/usr/local/lib \
	  -Xlinker -L/usr/local/opt/lapack/lib \
	  -Xlinker -L/usr/local/opt/openblas/lib \
	  -Xlinker -L/usr/local/opt/sqlite/lib \
	  -Xlinker -lenergymon-default \
	  -Xlinker -F/Library/Frameworks -Xlinker -framework -Xlinker IntelPowerGadget

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