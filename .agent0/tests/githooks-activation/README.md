# githooks-activation tests

Scenario. Scenario-numbered scripts (`NN-<slug>.sh`) map 1:1 to acceptance scenarios in `the harness-sync spec`. Run individually or via `run-all.sh`. Each script builds a `mktemp -d` fixture (mock project with/without `.githooks/`, with/without `git config core.hooksPath`), invokes `.agent0/hooks/session-start.sh` with `$CLAUDE_PROJECT_DIR` set, asserts the presence/absence of the `=== githooks-activation ===` advisory block, cleans up via `trap`.
