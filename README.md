# FAST
   

FAST is an implementation of an implicit programming model. It is built as a lightweight extension of the Swift programming language with added programming constructs to express intents.  It also serves as a framework for developing both terminating and streaming applications that can adapt to meet dynamic changes in the operating environment and mission intent when running on hardware platforms supported by the FAST runtime.  Currently FAST supports the x86_64 platform running Ubuntu 16.04 and macOS 10.14, and the Xilinx ZCU102 running Ubuntu 16.04.  
  



## Building FAST

### Dependencies

* First build the [energymon](https://github.mit.edu/proteus/energymon) library. To work with Swift 4.1, it must be compiled using `cmake -DBUILD_SHARED_LIBS=ON`.
* FAST `Package.swift` declares all dependencies that will be fetched and built automatically before building FASt.

### Makefile
The FAST package comes with its own `Makefile` to facilitate the compilation of the FAST library and the `incrementer` example. It also provides targets to run `incrementer` in various modes.  To build FAST, simply run
```
make
```
## How to write a FAST program
As previously mentionned, FAST is a framework that facilitates the development of streaming applications such that, when running the control of FAST, they can adapt dynamically to satisfy their intent to optimize certain combination of measures while maintining certain constraint. The FAST package includes `incrementer`, an example of such an application. We now illustrate the development process of this application.   
  
Consider the following simple Swift application:
```
let threshold = 1000000
let step = 1
while (true) {
	var x = 0
	while (x < threshold) {
		x += step
	}
}
```
This program endlessly increments a variable x by a certain `step`, up to a certain `threshold`.  Each execution of the body of the outer while loop will take some time and consume some energy.  The amount of time used and energy consumed vary depending on the application parameters `threshold` and `step` and the hardware sysem on which the application is running.  The hardwware system itself has its own parameters such as the number of utilized cores and the utliized core frequency.  
  
Now suppose we want to be able to dynamically adjust `threshold`, `step`, the number of `utilizedCores`, and the `utilizedCoreFrequency` to minimize some expresssion involving the number of operations while maintaining certain performance constraint.  We will need to rewrite the above simple loop and express our constrained optmization problem in the form of of an intent specification file using FAST. We shall name our application `my_incrementer` to avoid naming conflict with the `incrementer` example included in the FAST package.  
  
We starts with using the Swift package manager to create a skeletal structure for a Swift executable program.

### Using Swift package manager
  
Run the following sequence of commands:
```
> mkdir my_incrementer
> cd my_incrementer
> swift package init --type executable
```
The Swift package manager will create an executable package named `my_incrementer` containing pre-made files with the following subdirectory structure.
```
Creating executable package: my_incrementer
Creating Package.swift
Creating README.md
Creating .gitignore
Creating Sources/
Creating Sources/my_incrementer/main.swift
Creating Tests/
```
We will proceed to fill out 
* `main.swift` to express our computation
* `Package.swift` to declare dependencies

and to add an *intent specification* file to formalize our constrained optmization problem.

### Add intent specification

The intent specification file declares the following.
* the ranges of  the `knobs`, i.e. parameters, of the application and the system that FAST can control dynamically, and their respective reference values used for initialization purpose
* the `measures` that can be observed by the FAST runtime
* the `intent` which encodes the constrained optimization in five parts:
	* name of the application
	* optimization type, one of min or max
	* the objective function, an expression in terms of the declared `measures`
	* the constraint goal, the value of the constraint `measure` that the runtime should achieve
* the training set for machine learning, which is not used at this point in time.

For our `my_incrementer` program, in the `Sources/my_incrementer/` subdirectory, we create an itent specification file named by convention `my_incrementer.intent` as follows.
```
knobs       threshold             = [200000, 1000000] reference 1000000
            step                  = [1,4]             reference 1
            utilizedCores         = [2, 4]            reference 4
            utilizedCoreFrequency = [600,1200]        reference 1200

measures    energy           : Double // System measure
            energyDelta      : Double // System measure
            latency          : Double // System measure
            performance      : Double // System measure
            powerConsumption : Double // System measure
            operations       : Double // Application measure
            quality          : Double // Application measure

intent      my_incrementer min(((operations * operations) / 2.0)) such that performance == 50.0

trainingSet []
```

### Use FAST `optimize` hook

The `FAST` runtime provides a hook function called `optimize` whose purpose is to replace the input processing loop of a streaming application.  The following is the signature of `optimize`.
```
public func optimize(
    _ id: String,
    _ knobs: [TextApiModule],
    usingRuntime providedRuntime: Runtime? = nil,
    architecture: String = "XilinxZcu",
    streamInit: (() -> Void)? = nil,
    until shouldTerminate: @escaping @autoclosure () -> Bool = false,
    across windowSize: UInt32 = 20,
    samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1),
    _ routine: @escaping () -> Void)
``` 

In the main function of the adpative application, we 
* first declares the application `knobs` using the FAST `Knob` class to match with those declared in the intent file
* then make a call to the `optimize` hook passing to it, at the minimum,
	* id, which is the name of the application
	* knobs, which is the list of the declared `knobs`, and
	* a lambda (aka closure) that represents the processing of an input unit with code to compute and record the application measures declared in the intent file.


Based on the code of the simple non-adaptive application listed above, we rewite `main.swift` for `my_incrementer` as follows:

```
import Foundation  // access essential data types, collections, and operating-system services provided by Swift
import FAST        // access FAST APIs

// Declare the application knobs to match with those declared in the intent file
let threshold = Knob("threshold", 1000000)
let step = Knob("step", 1)

// replace the outer loop of the simple non-adaptive application with the FAST runtime hook function optimize:
optimize("my_incrementer", [threshold, step]) {
    // closure passed to the optimze hook is the body of the outer loop in the non-adaptive application
    var x = 0
    var operations = 0.0 
    while(x < threshold.get()) {
        x += step.get()
        operations += 1
    }

    // Use the runtime measure function to record the application measures declared in the intent file
    measure("operations", operations)
    measure("quality", 1.0 / Double(step.get()))
}

```

### Package dependencies
The sole dependency of `my_incremeter` on FAST, is declared in `Package.swift` as follows.
```
// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "my_incrementer",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "git@github.mit.edu:proteus/FAST", .exact("1.5.4")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "my_incrementer",
            dependencies: ["FAST"]),
    ],
    swiftLanguageVersions: [4]
)

```

### Makefile
To facilitate buiding and running `my_incrementer`, we add a `Makefile` based on that of the FAST package.
```

APPNAME := my_incrementer

UNAME := $(shell uname)
SPM_FLAGS_ALL := \
  -Xlinker -lenergymon-default

RESOURCE_PATH := Sources/${APPNAME}
RESOURCE_TARGET_PATH := .build/debug

ifeq ($(UNAME), Linux)
SPM_FLAGS := \
  -Xlinker -L/usr/local/lib \
  $(SPM_FLAGS_ALL)
endif

ifeq ($(UNAME), Darwin)
SPM_FLAGS := $(SPM_FLAGS_ALL) \
	-Xlinker -L/usr/local/lib 
endif

build: copy-resources-build
	swift build -Xswiftc -suppress-warnings $(SPM_FLAGS)

copy-resources-build:
	mkdir -p $(RESOURCE_TARGET_PATH)
	cp $(RESOURCE_PATH)/${APPNAME}.* $(RESOURCE_TARGET_PATH)/

clean:
	rm -rf .build/ *.resolved

rebuild: clean build

execute:              export proteus_runtime_address                          := 0.0.0.0
execute:              export proteus_client_rest_serverAddress                := brass-th
execute:              export proteus_client_rest_serverPort                   := 8080
execute:              export proteus_emulator_emulationDatabaseType           := Dict
execute:              export proteus_emulator_database_db                     := ./${APPNAME}.trace.json
execute:              export proteus_emulator_database_readingMode            := Statistics


execute:              export proteus_xilinxZcu_policy                         := Simple
execute:              export proteus_xilinxZcu_availableCores                 := 4
execute:              export proteus_xilinxZcu_availableCoreFrequency         := 1200
execute:              export proteus_xilinxZcu_utilizedCores                  := 4
execute:              export proteus_xilinxZcu_utilizedCoreFrequency          := 1200

execute: copy-resources-build
	.build/debug/${APPNAME}

go:                     build run

all:                    rebuild run

run:                    export proteus_runtime_missionLength                    := 2000
run:                    export proteus_runtime_applicationExecutionMode         := Adaptive
run:                    export proteus_runtime_executeWithMachineLearning       := false
run:                    execute

emulate:                export proteus_armBigLittle_executionMode               := Emulated
emulate:                export proteus_armBigLittle_actuationPolicy             := NoActuation
emulate:                export proteus_xilinxZcu_executionMode                  := Emulated
emulate:              	export proteus_xilinxZcu_actuationPolicy                := NoActuation
emulate:                run

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

```
At this point we can build `my_incrementer` by running:
```
make
```

and run it by calling:
```
make run
```

The application will run but with not be able to meet its intent because we have not provided any *model* for FAST to control it.  The creation of the control *model* is done via *profiling*.

### Profiling
It is required that an application be _profiled_  before FAST can run it in the adaptive mode. Profiling an application entails running the application in each possible knob configuration declared in the intent file for a representative set of inputs, and recording the total average of each measure of interest.  Profiling produces three tables:

* a knob table containing all the possible knob configurations,
* a measue table containing the total average of each measure of interest for each of the knob configuration in the knob table.
* a variance table containing the variance of each measure of interest.  Tnis table is used for debugging purpose only and plays no role in the functioning of the application.

The knob table and the measurable constitute what is called the _model_. The FAST control component makes use of these two tables in order to enable the application to adapt and meet the intent specification dynamically.  
  
To profile, run:
```
make profile
```
**NOTE**:  
  
After profiling, the knob table, the measure table, and the variance table are produced in the root directory of the package.  They need to be moved to the `Sources/my_incrementer` and subsequently to be copied to the `.build/debug` sudirectory using the following command:

```
mv my_incrementer.*table Sources/my_incrementer
make
```
Now `my_incrementer` can run in the *adaptive* mode.

### Tracing

It is required that an application be _traced_ before FAST can run it in the _emukated_ mode.  Tracing entails:

* running the application on the real hardware platform in all possible application and system configurations specified in the intent specification, and
* saving the time and energy readings for each input unit are in a specific text file in JSON format labelled `my_incrementer.trace.json`.

This _trace_ file is used by FAST to run the application in _emulated_ mode.  
  
To trace, run:
```
make trace
```
**NOTE**:  
  
After profiling, the file `my_incrementer.trace.json` is produced in the root directory of the package.  It needs to be moved to the `Sources/my_incrementer` subdirectory and subsequently to be copied to the `.build/debug` sudirectory using the following command:

```
mv my_incrementer.trace.json Sources/my_incrementer
make
```
Now `my_incrementer` can run in the *emulated* mode via the command:
```
make emulate
```


