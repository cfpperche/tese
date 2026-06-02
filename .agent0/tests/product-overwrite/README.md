# product-overwrite tests

Scenario. Scenario-numbered scripts (`NN-<slug>.sh`) map 1:1 to acceptance scenarios in `the harness-sync spec`. Each exercises `.claude/skills/product/scripts/clear-target.sh` — the selective-clear script that replaces `/product`'s blunt `rm -r <out>` overwrite (Gap F). Run individually or via `run-all.sh`. Each script is self-contained: builds a `mktemp -d` fixture, invokes `clear-target.sh`, asserts which entries survived vs. were removed, cleans up via `trap`.
