# NAMD Regression Tests
 
This is a set of regression tests for NAMD, starting with tests for alchemical perturbation, with and without the IDWS scheme.

Created using the layout and scripts of the [Colvars](https://github.com/Colvars/colvars) regression tests.
Credits to Giacomo Fiorin for much of the scripting.

## Running the tests
```
cd Tests
./run_tests.sh [NAMD binary | namd2] [list of test directories to run | all tests]
```

Add option `-g` to generate reference outputs (overwriting current ones). The reference outputs include the log file, the energy lines from the log, and the alchemical output if any.

## Abbreviations in directory names
- *Water*: simulation of a small water box
- *MD*: plain MD without alchemical transformation
- *alch*: making a water molecule alchemically disappear
- *ann*: annihilation (`alchDecouple off`)
- *dec*: decoupling (`alchDecouple on`) - for a single water molecule the result should be the same.
- *IDWS*: Interleaved Double-Wide Sampling (specifying `alchLambdaIDWS`)
- *noPME*: not enabling PME, as is done in all other tests
- *alchOutFreq*: using `alchOutFreq 12` as opposed to `alchOutFreq 4` in the other tests
- *CUDASOAint*: enables the GPU-resident mode of namd3 (fails on builds that do not support that feature)
- *GlobalMasterSync*: enables a Tcl script that outputs messages every timestep to troubleshoot synchronization issues with the GlobalMaster mechanism used by TclForces and Colvars

## How to create a new regression test
```
cd Tests
mkdir T_<My_Test>
cp T_Water_MD/test.namd T_<My_Test>
# Edit T_<My_Test>/test.namd to cutomize test
./run_tests -g <reference NAMD2 binary> T_<My_Test>
# Check that reference results in T_<My_Test>/AutoDiff are sensible
```
