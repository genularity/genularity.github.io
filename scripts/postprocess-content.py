#!/usr/bin/env python3
"""
postprocess-content.py — regenerate the homepage note list and strip dead
cross-references from whatever is currently in content/.

This is the AUTHORITATIVE post-processing step. It runs in two places:
  1. Locally, via sync-notes.sh, right after mirroring the vault (fast
     feedback / local preview parity with what will actually go live).
  2. In CI (.github/workflows/deploy.yml), right before `npx quartz build`.

CI running this step is what makes the live site correct even if content/
was edited or committed by hand without running sync-notes.sh first — CI is
the last word on what's actually published, not a trust-the-committer step.

Usage: postprocess-content.py <content_dir>
"""
import sys
import re
import glob
import os
import hashlib

def main():
    if len(sys.argv) < 2:
        print("Usage: postprocess-content.py <content_dir>", file=sys.stderr)
        sys.exit(1)

    content_dir = sys.argv[1]
    regenerate_note_list(content_dir)
    strip_dead_links(content_dir)


def regenerate_note_list(content_dir):
    """Rewrite the region between QUARTZ:NOTE-LIST-START/END markers in
    index.md from the actual published set in content/*.md. Also checks the
    hand-written 'themes' paragraph for staleness against the published set."""
    index_path = os.path.join(content_dir, "index.md")
    if not os.path.exists(index_path):
        print("WARNING: no content/index.md found — skipping note list regeneration.")
        return

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

    # Themes staleness check — the "themes" paragraph is hand/agent-written
    # prose, not mechanically generated. We hash the sorted published title
    # set and compare against themes-hash in frontmatter; mismatch means the
    # prose is stale and needs a human/agent rewrite.
    current_hash = hashlib.sha256("|".join(sorted(t for t, _ in entries)).encode()).hexdigest()[:12]
    fm_match = re.match(r"^---\n(.*?)\n---\n", idx, re.DOTALL)
    stored_hash = None
    if fm_match:
        h_match = re.search(r'^themes-hash:\s*"?([a-f0-9]*)"?\s*$', fm_match.group(1), re.MULTILINE)
        if h_match:
            stored_hash = h_match.group(1)

    if stored_hash != current_hash:
        print(f"WARNING: homepage themes paragraph is STALE (hash {stored_hash!r} != current {current_hash!r}).")
        print(f"  The published note set changed since the themes paragraph was last written by hand/agent.")
        print(f"  Rewrite the paragraph between QUARTZ:THEMES-START/END in the vault homepage note,")
        print(f"  then set themes-hash: \"{current_hash}\" in its frontmatter.")


def strip_dead_links(content_dir):
    """Remove any related:/wikilink entry pointing at a note NOT in the
    current published set, before it ever reaches the live site."""
    published_titles = set()
    for path in glob.glob(os.path.join(content_dir, "*.md")):
        published_titles.add(os.path.splitext(os.path.basename(path))[0])

    wikilink = re.compile(r"\[\[([^\]|#]+)(\|[^\]]*)?(#[^\]]*)?\]\]")

    def target_is_dead(raw_target):
        return raw_target.strip() not in published_titles

    for path in glob.glob(os.path.join(content_dir, "*.md")):
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
        original = text

        fm_match = re.match(r"^(---\n)(.*?)(\n---\n)", text, re.DOTALL)
        removed_from = []

        if fm_match:
            fm_body = fm_match.group(2)

            def _filter_related_line(m):
                target_match = wikilink.search(m.group(0))
                if target_match and target_is_dead(target_match.group(1)):
                    removed_from.append(target_match.group(1))
                    return ""
                return m.group(0)

            new_fm_body = re.sub(r'^\s*-\s*"?\[\[[^\]]+\]\]"?\s*$\n?', _filter_related_line, fm_body, flags=re.MULTILINE)
            if new_fm_body != fm_body:
                text = text[:fm_match.start(2)] + new_fm_body + text[fm_match.end(2):]

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

        new_body = wikilink.sub(_unwrap_dead_link, body)
        text = head + new_body

        if text != original:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
            uniq = sorted(set(removed_from))
            print(f"Stripped dead link(s) in {os.path.basename(path)}: {', '.join(uniq)}")


if __name__ == "__main__":
    main()
