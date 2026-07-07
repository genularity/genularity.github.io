#!/bin/bash
# publish.sh — the ONE command to run the entire Obsidian → Quartz → live
# site pipeline. No manual git or curl commands needed.
#
# What it does:
#   1. Sync publish:true vault notes into content/ (sync-notes.sh), which
#      also regenerates the homepage note list and strips dead links locally.
#   2. Show a git diff summary of what changed.
#   3. Commit and push to main — this triggers the GitHub Actions deploy
#      workflow (.github/workflows/deploy.yml), which re-runs the same
#      post-processing step authoritatively and builds/deploys the site.
#
# Usage: ./publish.sh ["optional commit message"]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "== Step 1/3: syncing vault notes =="
./sync-notes.sh

echo
echo "== Step 2/3: reviewing changes =="
git add -A content/

if git diff --cached --quiet; then
  echo "No changes to publish — content/ is already up to date with the vault."
  exit 0
fi

git diff --cached --stat -- content/

echo
echo "== Step 3/3: committing and pushing =="
MSG="${1:-Sync notes from vault}"
git commit -m "$MSG"
git push origin main

echo
echo "Pushed. GitHub Actions will build and deploy — check:"
echo "  https://github.com/genularity/genularity.github.io/actions"
echo "Live site (usually live within ~1-2 min after the workflow finishes):"
echo "  https://genularity.github.io/"
