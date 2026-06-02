#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

for test in "$DIR"/[0-9][0-9]-*.sh; do
  bash "$test"
done
