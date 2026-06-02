# harness-sync tests

Scenario. Scenario-numbered scripts (`NN-<slug>.sh`) map 1:1 to acceptance scenarios in `the harness-sync spec`. Run individually or via `run-all.sh`. Each script is self-contained: builds a `mktemp -d` fixture (mock Agent0 source + mock consumer project target), invokes `.agent0/tools/sync-harness.sh`, asserts stdout/stderr/exit, cleans up via `trap`.
