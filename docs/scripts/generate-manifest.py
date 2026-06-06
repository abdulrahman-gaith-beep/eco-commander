#!/usr/bin/env python3
"""Generate docs/MANIFEST.json from the filesystem — the machine-readable docs index.

Scans docs/ and emits an accurate, drift-free manifest: corpus stats, per-category
file lists, per-document metadata (title, sections, size, read-time), the ADR/diagram
registries, and a dependency graph derived from the ACTUAL inter-doc links.

Run from the repo root:  python3 docs/scripts/generate-manifest.py
Check-only (CI drift gate): python3 docs/scripts/generate-manifest.py --check
"""
from __future__ import annotations

import datetime
import json
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent
REPO = DOCS.parent
MANIFEST = DOCS / "MANIFEST.json"

# Human descriptions for each top-level docs area.
CATEGORY_DESC = {
    "overview": "Cross-cutting system overview and navigation",
    "tutorials": "Learning-oriented guided walkthroughs (Diataxis: tutorial)",
    "getting-started": "Onboarding: install, use, and troubleshoot (Diataxis: how-to)",
    "concepts": "Understanding-oriented explanations and mental models (Diataxis: explanation)",
    "examples": "Task-oriented cookbook scenarios (Diataxis: how-to)",
    "reference": "Technical reference: schemas, config, env vars, glossary (Diataxis: reference)",
    "subsystems": "Deep dives into each major subsystem",
    "operations": "Runbooks, security model, and performance for production operation",
    "contributing": "Contributor guidelines, testing, and governance",
    "adr": "Architecture Decision Records",
    "rfcs": "Request-for-comments design proposals",
    "migration": "Version-to-version upgrade notes",
    "diagrams": "Mermaid diagrams of system topology",
    "api": "Generated CLI reference",
    "scripts": "Documentation tooling: search, extraction, validation, generation",
}
WORDS_PER_MIN = 200
LINK_RE = re.compile(r"\[[^\]]+\]\(([^)]+)\)")
H1_RE = re.compile(r"^#\s+(.*)$", re.M)
H2_RE = re.compile(r"^##\s+(.*)$", re.M)


def category_of(rel: Path) -> str:
    return "overview" if rel.parent == Path(".") else rel.parts[0]


def title_of(text: str, fallback: str) -> str:
    m = H1_RE.search(text)
    return m.group(1).strip() if m else fallback


def sections_of(text: str) -> list[str]:
    return [h.strip() for h in H2_RE.findall(text)]


def doc_links(rel: Path, text: str) -> list[str]:
    """Return repo-relative paths of links from this doc to other docs/ markdown."""
    out: set[str] = set()
    for raw in LINK_RE.findall(text):
        link = raw.split("#", 1)[0].split("?", 1)[0].strip()
        if not link or link.startswith(("http://", "https://", "mailto:")):
            continue
        if not link.endswith(".md"):
            continue
        target = (DOCS / rel.parent / link).resolve()
        try:
            t_rel = target.relative_to(DOCS)
        except ValueError:
            continue  # link points outside docs/ (e.g. ../../CHANGELOG.md)
        if target.exists():
            out.add(str(t_rel))
    return sorted(out)


def build() -> dict:
    md_files = sorted(
        p.relative_to(DOCS) for p in DOCS.rglob("*.md") if ".git" not in p.parts
    )
    subdirs = sorted({p.parts[0] for p in md_files if len(p.parts) > 1})
    total_bytes = sum((DOCS / p).stat().st_size for p in md_files)

    documents, adr_docs, diagrams = [], [], []
    categories: dict[str, dict] = {}
    edges: list[list[str]] = []

    for rel in md_files:
        text = (DOCS / rel).read_text(encoding="utf-8", errors="replace")
        cat = category_of(rel)
        categories.setdefault(
            cat,
            {"path": "." if cat == "overview" else cat, "description": CATEGORY_DESC.get(cat, cat), "files": []},
        )["files"].append(rel.name if cat != "overview" else str(rel))

        title = title_of(text, rel.stem)
        rels = str(rel)

        if cat == "adr" and rel.name != "README.md":
            status = "accepted"
            sm = re.search(r"Status\s*\|\s*([^|]+)\|", text) or re.search(r"\*\*?Status\*\*?:?\s*([^\n]+)", text)
            if sm:
                status = sm.group(1).strip().rstrip("|").strip()
            adr_docs.append({"path": rels, "title": title, "status": status})
            continue
        if cat == "diagrams":
            diagrams.append({"path": rels, "type": "mermaid", "subject": title})
            continue

        links = doc_links(rel, text)
        for tgt in links:
            edges.append([rels, tgt])
        words = len(text.split())
        documents.append(
            {
                "path": rels,
                "title": title,
                "category": cat,
                "sections": sections_of(text),
                "size_bytes": (DOCS / rel).stat().st_size,
                "read_time_minutes": max(1, round(words / WORDS_PER_MIN)),
                "depends_on": links,
            }
        )

    # depended_by (reverse edges) for richer agent navigation
    rev: dict[str, list[str]] = {}
    for a, b in edges:
        rev.setdefault(b, []).append(a)
    for d in documents:
        d["depended_by"] = sorted(set(rev.get(d["path"], [])))

    for c in categories.values():
        c["files"] = sorted(set(c["files"]))

    return {
        "version": 2,
        "generated_by": "docs/scripts/generate-manifest.py",
        "generated": datetime.datetime.now().astimezone().replace(microsecond=0).isoformat(),
        "corpus_stats": {
            "total_files": len(md_files),
            "total_bytes": total_bytes,
            "categories": len(categories),
            "subdirectories": subdirs,
        },
        "categories": dict(sorted(categories.items())),
        "documents": documents,
        "adr_documents": adr_docs,
        "diagrams": diagrams,
        "dependency_graph": {
            "description": "Edges represent 'A links to B' (derived from actual markdown links)",
            "edges": sorted(edges),
        },
    }


def main() -> int:
    data = build()
    rendered = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        current = MANIFEST.read_text(encoding="utf-8") if MANIFEST.exists() else ""
        # ignore the volatile 'generated' timestamp when diffing
        norm = lambda s: re.sub(r'"generated":\s*"[^"]*"', '"generated": "_"', s)
        if norm(current) != norm(rendered):
            print("MANIFEST.json is STALE — run: python3 docs/scripts/generate-manifest.py", file=sys.stderr)
            return 1
        print("MANIFEST.json is up to date.")
        return 0
    MANIFEST.write_text(rendered, encoding="utf-8")
    print(f"Wrote {MANIFEST.relative_to(REPO)}: {data['corpus_stats']['total_files']} files, "
          f"{len(data['documents'])} documents, {len(data['diagrams'])} diagrams, "
          f"{len(data['adr_documents'])} ADRs, {len(data['dependency_graph']['edges'])} edges.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
