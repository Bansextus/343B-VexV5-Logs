#!/bin/bash
set -euo pipefail

# Usage:
#   ./tools/release_merge_from_prototypes.sh [prototype_branch] [main_branch]
#
# Defaults:
#   prototype_branch=codex/prototypes
#   main_branch=main

PROTO_BRANCH="${1:-codex/prototypes}"
MAIN_BRANCH="${2:-main}"

echo "Fetching latest refs..."
git fetch origin

echo "Checking out ${MAIN_BRANCH}..."
git checkout "${MAIN_BRANCH}"

echo "Updating ${MAIN_BRANCH} from origin..."
git pull --ff-only origin "${MAIN_BRANCH}"

echo "Merging ${PROTO_BRANCH} into ${MAIN_BRANCH}..."
git merge --no-ff "${PROTO_BRANCH}" -m "Release merge: ${PROTO_BRANCH} -> ${MAIN_BRANCH}"

echo "Pushing ${MAIN_BRANCH}..."
git push origin "${MAIN_BRANCH}"

echo "Release merge complete."
