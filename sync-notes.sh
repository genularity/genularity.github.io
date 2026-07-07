#!/bin/bash
# sync-notes.sh — copy publish:true notes from Obsidian vault to Quartz content/,
# then regenerate the homepage note list from whatever actually ended up published.
# Usage: ./sync-notes.sh

VAULT="/home/node/obsidian/Notes"
CONTENT="$(dirname "$0")/content"

# Clear existing content (keep index.md — it's regenerated below, not synced from vault)
find "$CONTENT" -name "*.md" ! -name "index.md" -delete 2>/dev/null

SYNCED=0
SKIPPED=0

while IFS= read -r -d '' file; do
  if head -50 "$file" | grep -qE "^publish:\s*true"; then
    rel="${file#$VAULT/}"
    dest="$CONTENT/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$file" "$dest"
    ((SYNCED++))
  else
    ((SKIPPED++))
  fi
done < <(find "$VAULT" -name "*.md" ! -path "*/.obsidian/*" ! -path "*/copilot/*" -print0)

echo "Synced: $SYNCED notes | Skipped: $SKIPPED notes"

# --- Regenerate homepage note list from the CURRENT published set only ---
# This block reads content/*.md (post-sync, i.e. the ground truth of what's
# actually live) and rebuilds the "Start Here" list in index.md. It never
# reads a hand-maintained list — dead links from deleted notes can't
# accumulate here because the list is rebuilt from disk every run.
python3 - "$CONTENT" <<'PYEOF'
import sys, re, glob, os

content_dir = sys.argv[1]
index_path = os.path.join(content_dir, "index.md")

entries = []
for path in sorted(glob.glob(os.path.join(content_dir, "*.md"))):
    if os.path.basename(path) == "index.md":
        continue
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    fm_match = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    title = os.path.splitext(os.path.basename(path))[0]
    summary = ""
    if fm_match:
        fm = fm_match.group(1)
        t_match = re.search(r'^title:\s*"?([^"\n]+)"?\s*$', fm, re.MULTILINE)
        if t_match:
            title = t_match.group(1).strip()
        s_match = re.search(r"^summary:\s*>?\s*\n((?:^\s+.+\n?)+)", fm, re.MULTILINE)
        if s_match:
            summary = " ".join(l.strip() for l in s_match.group(1).splitlines()).strip()
        else:
            s_inline = re.search(r'^summary:\s*"?([^"\n]+)"?\s*$', fm, re.MULTILINE)
            if s_inline:
                summary = s_inline.group(1).strip()
    if summary:
        # trim to a single clause for the homepage list
        summary = summary.split(". ")[0].rstrip(".")
    entries.append((title, summary))

lines = []
list_md = "\n".join("- [[%s]]%s" % (title, (" — " + summary) if summary else "")
                     for title, summary in entries)

if not os.path.exists(index_path):
    body = f"""---
title: Home
publish: true
---

# Kent's Notes

Writing on AI architecture, agentic systems, and building things that actually work in production.

I'm an AI Architect based in Sweden. These notes are my thinking-out-loud — patterns I've found useful, ideas worth sharing, things I want to remember.

---

## Start Here

> [!example] Currently published
> {len(entries)} note(s) are live right now.

{list_md}

---

## Browse

Use the **explorer** on the left or hit `Ctrl+K` to search. The **graph view** on the right shows how notes connect.

---

*Updated automatically from my Obsidian vault.*
"""
    with open(index_path, "w", encoding="utf-8") as f:
        f.write(body)
    print(f"Homepage created with {len(entries)} note(s).")
else:
    with open(index_path, "r", encoding="utf-8") as f:
        idx = f.read()

    count_line = f"> {len(entries)} note(s) are live right now."
    idx = re.sub(r"^> .*note\(s\) are live right now\.$", count_line, idx, flags=re.MULTILINE)
    # Also normalize any hand-written variant (e.g. "Two notes are live right now...")
    # so it doesn't drift out of sync with the actual count on future edits.
    idx = re.sub(
        r"^> [A-Za-z0-9]+ notes? (?:are|is) live right now.*$",
        count_line,
        idx,
        flags=re.MULTILINE,
    )

    new_idx, n = re.subn(
        r"(## Start Here\n\n(?:> \[!example\].*\n(?:> .*\n)*\n)?)(?:- \[\[.*\]\].*\n)+",
        lambda m: m.group(1) + list_md + "\n",
        idx,
    )
    if n == 0:
        # Fallback: no matching block found, leave index.md untouched rather than corrupt it
        print("WARNING: could not locate 'Start Here' note list in index.md — left unchanged.")
    else:
        with open(index_path, "w", encoding="utf-8") as f:
            f.write(new_idx)
        print(f"Homepage note list regenerated: {len(entries)} note(s) — {', '.join(t for t, _ in entries)}")
PYEOF
