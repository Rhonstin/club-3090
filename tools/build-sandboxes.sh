#!/usr/bin/env bash
# Build benchlocal-cli sandbox Docker images (hermesagent-20, bugfind-15, cli-40).
# Clones benchlocal-cli to a temp dir, builds images, then cleans up.
set -euo pipefail

REPO="https://github.com/noonghunna/benchlocal-cli"
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "[build-sandboxes] cloning $REPO ..."
git clone --depth=1 "$REPO" "$TMPDIR/benchlocal-cli"

echo "[build-sandboxes] building sandbox images ..."
bash "$TMPDIR/benchlocal-cli/tools/build-sandboxes.sh"

echo "[build-sandboxes] done."
