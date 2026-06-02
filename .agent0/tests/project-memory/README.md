# project-memory tests

Scenario. Scenario-numbered scripts (`NN-<slug>.sh`) map 1:1 to acceptance scenarios in `the harness-sync spec`. Run individually or via `run-all.sh`. Tests 02 + 04 are invariant guards (pass trivially before AND after impl — protect sync-harness manifest exclusion and SessionStart absence from future regression). Tests 01/03/05/06/07 are true RED until Phases 2-4 land.
