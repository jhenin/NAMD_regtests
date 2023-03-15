# NAMD Regression Tests

This is a set of regression tests for NAMD, starting with tests for alchemical perturbation, with and without the IDWS scheme.

Created using the layout and scripts of the [Colvars](https://github.com/Colvars/colvars) regression tests.
Credits to Giacomo Fiorin for much of the scripting.

To run the tests:
```
cd Tests
./run_tests.sh [NAMD binary | namd2] [list of test directories to run | all tests]
```

Add option `-g` to generate reference outputs (overwriting current ones).
