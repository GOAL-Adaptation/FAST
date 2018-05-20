# FAST

A library for implicit programming.

## Dependencies

* The [energymon](https://github.mit.edu/proteus/energymon) library. To work with Swift 4.1, it must be compiled using `cmake -DBUILD_SHARED_LIBS=ON`.

## Environment

Typical environment setting for emulation:

```sh
export proteus_armBigLittle_executionMode=Emulated
export proteus_emulator_database_extensionLocation=/path/to/libsqlitefunctions.so 
export proteus_emulator_database_db=/path/to/pemuDB.db
```

Typical environment setting for profiling:

```sh
export proteus_runtime_applicationExecutionMode=ExhaustiveProfiling
export proteus_runtime_missionLength=100
```
