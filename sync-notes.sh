#!/bin/bash
# sync-notes.sh — copy publish:true notes from Obsidian vault to Quartz content/,
# then regenerate the homepage note list and strip dead links from whatever
# actually ended up published.
#
# Homepage is vault-native: the vault note with `quartz-homepage: true` in its
# frontmatter (see /home/node/obsidian/Notes/GitHub Pages Home.md) is synced to
# content/index.md instead of its own filename. Everything in that note is
# hand-editable in Obsidian EXCEPT the region between the
# <!-- QUARTZ:NOTE-LIST-START --> / <!-- QUARTZ:NOTE-LIST-END --> markers,
# which is mechanically regenerated from the actual published set every run.
#
# The actual regeneration + dead-link-stripping logic lives in
# scripts/postprocess-content.py, NOT here — that script is also invoked by
# the GitHub Actions build (.github/workflows/deploy.yml), so it is the
# authoritative post-processing step regardless of whether this script was
# run locally first. Running it here too just gives fast local feedback.
#
# Usage: ./sync-notes.sh

set -euo pipefail

VAULT="/home/node/obsidian/Notes"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENT="$SCRIPT_DIR/content"

# Clear existing content entirely — index.md is sourced from the vault
# homepage note (via quartz-homepage: true) like everything else.
find "$CONTENT" -name "*.md" -delete 2>/dev/null || true

SYNCED=0
SKIPPED=0
HOMEPAGE_SRC=""

while IFS= read -r -d '' file; do
  if head -50 "$file" | grep -qE "^publish:\s*true"; then
    if head -50 "$file" | grep -qE "^quartz-homepage:\s*true"; then
      HOMEPAGE_SRC="$file"
      dest="$CONTENT/index.md"
    else
      rel="${file#$VAULT/}"
      dest="$CONTENT/$rel"
    fi
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    SYNCED=$((SYNCED+1))
  else
    SKIPPED=$((SKIPPED+1))
  fi
done < <(find "$VAULT" -name "*.md" ! -path "*/.obsidian/*" ! -path "*/copilot/*" -print0)

echo "Synced: $SYNCED notes | Skipped: $SKIPPED notes"

if [ -z "$HOMEPAGE_SRC" ]; then
  echo "WARNING: no vault note with 'quartz-homepage: true' found — content/index.md was not created this run."
fi

python3 "$SCRIPT_DIR/scripts/postprocess-content.py" "$CONTENT"
