#!/usr/bin/env bash
# Verify scripts/MANIFEST.yaml against the actual filesystem.
#
# Checks:
#   1. Every path listed in MANIFEST.yaml exists on disk
#   2. Line counts match actual wc -l output
#   3. Every .sh file in scripts/ (except this one) has a MANIFEST entry
#
# Usage: scripts/verify-manifest.sh
#        scripts/verify-manifest.sh --fix   (update line counts in-place)
#
# @category  ci
# @depends   python3, pyyaml
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$REPO_ROOT/scripts/MANIFEST.yaml"
FIX_MODE=0
[ "${1:-}" = "--fix" ] && FIX_MODE=1


if [ ! -f "$MANIFEST" ]; then
  echo "✗ MANIFEST.yaml not found at $MANIFEST" >&2
  exit 1
fi

# ── 1. Check listed paths exist + line counts match ─────────────────
python3 - "$MANIFEST" "$REPO_ROOT" "$FIX_MODE" <<'PY'
import sys
import yaml
from pathlib import Path

manifest_path = Path(sys.argv[1])
repo_root = Path(sys.argv[2])
fix_mode = sys.argv[3] == "1"

data = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
errors = 0
fixes = {}  # path -> actual line count

def check_item(item, base):
    """Check a script/library entry exists and has correct line count."""
    global errors
    path = base / item["path"]
    if not path.exists():
        print(f"  ✗ missing: {item['path']}")
        errors += 1
        return

    if "lines" in item:
        actual = sum(1 for _ in path.open(encoding="utf-8"))
        expected = item["lines"]
        if actual != expected:
            print(f"  ✗ line count mismatch: {item['path']} — manifest says {expected}, actual is {actual}")
            errors += 1
            fixes[item["path"]] = (expected, actual)
        else:
            print(f"  ✓ {item['path']} ({actual} lines)")
    else:
        print(f"  ✓ {item['path']} (no line count to verify)")

scripts_dir = repo_root / "scripts"
print("── Checking scripts ──")
for item in data.get("scripts", []):
    check_item(item, scripts_dir)

print("\n── Checking libraries ──")
for item in data.get("libraries", []):
    check_item(item, scripts_dir)

print("\n── Checking configs ──")
for item in data.get("configs", []):
    path = scripts_dir / item["path"]
    if path.exists():
        print(f"  ✓ {item['path']}")
    else:
        print(f"  ✗ missing: {item['path']}")
        errors += 1

print("\n── Checking plist templates ──")
for item in data.get("plist_templates", []):
    path = scripts_dir / item["path"]
    if path.exists():
        print(f"  ✓ {item['path']}")
    else:
        print(f"  ✗ missing: {item['path']}")
        errors += 1

# ── 2. Check for unlisted .sh files ──
listed_paths = set()
for section in ("scripts", "libraries"):
    for item in data.get(section, []):
        listed_paths.add(item["path"])

print("\n── Checking for unlisted scripts ──")
for sh in sorted(scripts_dir.glob("*.sh")):
    rel = sh.name
    if rel == "verify-manifest.sh":
        continue
    if rel not in listed_paths:
        print(f"  ⚠ not in MANIFEST: {rel}")
        errors += 1
for sh in sorted((scripts_dir / "lib").glob("*.sh")):
    rel = f"lib/{sh.name}"
    if rel not in listed_paths:
        print(f"  ⚠ not in MANIFEST: {rel}")
        errors += 1

# ── 3. Fix mode ──
if fix_mode and fixes:
    text = manifest_path.read_text(encoding="utf-8")
    for path, (old, new) in fixes.items():
        # Replace "lines: OLD" near the path context
        text = text.replace(f"    lines: {old}", f"    lines: {new}", 1)
    manifest_path.write_text(text, encoding="utf-8")
    print(f"\n✓ Fixed {len(fixes)} line count(s) in MANIFEST.yaml")

print(f"\n── Summary ── {errors} issue(s) found")
sys.exit(1 if errors > 0 else 0)
PY
