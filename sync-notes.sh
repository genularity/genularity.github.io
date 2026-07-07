#!/bin/bash
# sync-notes.sh — copy publish:true notes from Obsidian vault to Quartz content/,
# then regenerate the homepage note list from whatever actually ended up published.
#
# Homepage is vault-native: the vault note with `quartz-homepage: true` in its
# frontmatter (see /home/node/obsidian/Notes/Home.md) is synced to
# content/index.md instead of its own filename. Everything in that note is
# hand-editable in Obsidian EXCEPT the region between the
# <!-- QUARTZ:NOTE-LIST-START --> / <!-- QUARTZ:NOTE-LIST-END --> markers and
# the <!-- QUARTZ:NOTE-COUNT --> placeholder, which are regenerated below from
# the actual published set every run.
#
# Usage: ./sync-notes.sh

VAULT="/home/node/obsidian/Notes"
CONTENT="$(dirname "$0")/content"

# Clear existing content entirely — index.md is now sourced from the vault
# homepage note (via quartz-homepage: true) like everything else, so there is
# no longer a standing exception to preserve here.
find "$CONTENT" -name "*.md" -delete 2>/dev/null

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
    ((SYNCED++))
  else
    ((SKIPPED++))
  fi
done < <(find "$VAULT" -name "*.md" ! -path "*/.obsidian/*" ! -path "*/copilot/*" -print0)

echo "Synced: $SYNCED notes | Skipped: $SKIPPED notes"

if [ -z "$HOMEPAGE_SRC" ]; then
  echo "WARNING: no vault note with 'quartz-homepage: true' found — content/index.md was not created this run."
fi

# --- Regenerate homepage note list from the CURRENT published set only ---
# Reads content/*.md (post-sync, i.e. ground truth of what's actually live)
# and rewrites the region between the NOTE-LIST markers in index.md, plus the
# NOTE-COUNT placeholder. Everything else in index.md is left untouched —
# it's normal hand-editable Obsidian content.
python3 - "$CONTENT" <<'PYEOF'
import sys, re, glob, os

content_dir = sys.argv[1]
index_path = os.path.join(content_dir, "index.md")

if not os.path.exists(index_path):
    sys.exit(0)

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
        summary = summary.split(". ")[0].rstrip(".")
    entries.append((title, summary))

list_md = "\n".join("- [[%s]]%s" % (title, (" — " + summary) if summary else "")
                     for title, summary in entries)

with open(index_path, "r", encoding="utf-8") as f:
    idx = f.read()

idx = idx.replace("<!-- QUARTZ:NOTE-COUNT -->", str(len(entries)))

new_idx, n = re.subn(
    r"<!-- QUARTZ:NOTE-LIST-START -->.*?<!-- QUARTZ:NOTE-LIST-END -->",
    "<!-- QUARTZ:NOTE-LIST-START -->\n" + list_md + "\n<!-- QUARTZ:NOTE-LIST-END -->",
    idx,
    flags=re.DOTALL,
)

if n == 0:
    print("WARNING: could not find QUARTZ:NOTE-LIST markers in index.md — note list left unchanged.")
else:
    idx = new_idx

with open(index_path, "w", encoding="utf-8") as f:
    f.write(idx)

print(f"Homepage note list regenerated: {len(entries)} note(s) — {', '.join(t for t, _ in entries)}")
PYEOF

# --- Strip dead cross-references before they ever reach the live site ---
# For every published note, remove any related:/wikilink entry that points at
# a note NOT in the current published set. This runs after the homepage
# regeneration above so it also covers links inside index.md itself.
# disableBrokenWikilinks in quartz.config.default.yaml is kept as a visual
# fallback in case something slips past this (e.g. a link added after this
# script last ran, before the next sync) — this step is the primary defense.
python3 - "$CONTENT" <<'PYEOF'
import sys, re, glob, os

content_dir = sys.argv[1]

# Build the set of valid link targets: every published note's title (no ext),
# matched case-sensitively against [[Title]] and [[Title|alias]] forms.
published_titles = set()
for path in glob.glob(os.path.join(content_dir, "*.md")):
    published_titles.add(os.path.splitext(os.path.basename(path))[0])

WIKILINK = re.compile(r"\[\[([^\]|#]+)(\|[^\]]*)?(#[^\]]*)?\]\]")

def target_is_dead(raw_target: str) -> bool:
    return raw_target.strip() not in published_titles

for path in glob.glob(os.path.join(content_dir, "*.md")):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    original = text

    fm_match = re.match(r"^(---\n)(.*?)(\n---\n)", text, re.DOTALL)
    removed_from = []

    if fm_match:
        fm_body = fm_match.group(2)
        # Drop related: list items that point at a non-published note.
        def _filter_related_line(m):
            target_match = WIKILINK.search(m.group(0))
            if target_match and target_is_dead(target_match.group(1)):
                removed_from.append(target_match.group(1))
                return ""
            return m.group(0)

        new_fm_body = re.sub(r'^\s*-\s*"?\[\[[^\]]+\]\]"?\s*$\n?', _filter_related_line, fm_body, flags=re.MULTILINE)
        if new_fm_body != fm_body:
            text = text[:fm_match.start(2)] + new_fm_body + text[fm_match.end(2):]

    # Body wikilinks: drop any pointing at a non-published note, keeping
    # surrounding text intact (unwrap to plain text rather than delete
    # the sentence around it).
    body_start = fm_match.end(3) if fm_match else 0
    head, body = text[:body_start], text[body_start:]

    def _unwrap_dead_link(m):
        target = m.group(1).strip()
        alias = m.group(2)
        if target_is_dead(target):
            removed_from.append(target)
            display = alias[1:] if alias else target
            return display
        return m.group(0)

    new_body = WIKILINK.sub(_unwrap_dead_link, body)
    text = head + new_body

    if text != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        uniq = sorted(set(removed_from))
        print(f"Stripped dead link(s) in {os.path.basename(path)}: {', '.join(uniq)}")
PYEOF
