#!/bin/bash
# Checks publication safety using original repository samples and disposable outputs.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CLI=${1:-"$REPO_ROOT/.build/release/tubeline"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/tubeline-cli-output.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

fail() { echo "CLI output regression: $*" >&2; exit 1; }
count_models() { find "$1" -maxdepth 1 -type f -name '*.usdz' | wc -l | tr -d ' '; }
run() {
    if ! "$CLI" "$@" > "$WORK/run.log" 2>&1; then
        cat "$WORK/run.log" >&2
        fail "conversion failed"
    fi
}

mkdir -p "$WORK/a" "$WORK/b"
cp "$REPO_ROOT/Samples/heart.svg" "$WORK/a/icon.svg"
cp "$REPO_ROOT/Samples/plus-circle.svg" "$WORK/b/icon.svg"

# Independent processes plan the same name before any conversion finishes.
pids=()
for index in 1 2 3 4; do
    source="$WORK/a/icon.svg"
    if (( index % 2 == 0 )); then source="$WORK/b/icon.svg"; fi
    "$CLI" "$source" --facets 48 -o "$WORK/concurrent" > "$WORK/concurrent-$index.log" 2>&1 &
    pids+=("$!")
done
for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
        cat "$WORK"/concurrent-*.log >&2
        fail "a concurrent conversion failed"
    fi
done
[[ $(count_models "$WORK/concurrent") == 4 ]] || fail "concurrent exports replaced one another"

run "$WORK/a/icon.svg" "$WORK/b/icon.svg" -o "$WORK/batch"
[[ $(count_models "$WORK/batch") == 2 ]] || fail "same-name inputs in one batch collided"

run "$WORK/a/icon.svg" -o "$WORK/existing"
cp "$WORK/existing/icon.usdz" "$WORK/original.usdz"
run "$WORK/b/icon.svg" -o "$WORK/existing"
cmp -s "$WORK/original.usdz" "$WORK/existing/icon.usdz" || fail "default export replaced an existing file"
[[ $(count_models "$WORK/existing") == 2 ]] || fail "default export did not keep both files"

run "$WORK/b/icon.svg" -o "$WORK/existing" --replace
if cmp -s "$WORK/original.usdz" "$WORK/existing/icon.usdz"; then fail "--replace did not replace the requested file"; fi
[[ $(count_models "$WORK/existing") == 2 ]] || fail "--replace unexpectedly added another file"

if [[ -n $(find "$WORK" -type d -name '.Tubeline-*' -print -quit) ]]; then
    fail "a completed conversion left its staging directory behind"
fi
echo "CLI output checks passed: concurrent exports, batch names, keep both, and explicit replacement."
