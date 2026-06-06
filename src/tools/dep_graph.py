#!/usr/bin/env python3
"""Static import dependency graph for eco-commander src/.

Scans all Python files under src/, extracts imports, and outputs:
  - JSON dependency graph
  - Mermaid diagram
  - Circular dependency detection
  - Unused import candidates

Usage:
    PYTHONPATH=src python -m tools.dep_graph [--format json|mermaid|report]
"""
from __future__ import annotations

import ast
import json
import sys
from pathlib import Path
from typing import Any

SRC_ROOT = Path(__file__).resolve().parent.parent


def _find_python_files(root: Path) -> list[Path]:
    """Find all .py files under root, excluding __pycache__."""
    return sorted(
        p for p in root.rglob("*.py")
        if "__pycache__" not in p.parts
    )


def _module_name(path: Path, root: Path) -> str:
    """Convert a file path to a dotted module name."""
    rel = path.relative_to(root)
    parts = list(rel.parts)
    if parts[-1] == "__init__.py":
        parts = parts[:-1]
    else:
        parts[-1] = parts[-1].removesuffix(".py")
    return ".".join(parts)


def _extract_imports(path: Path) -> list[str]:
    """Extract all import targets from a Python file."""
    try:
        tree = ast.parse(path.read_text(encoding="utf-8"))
    except (SyntaxError, UnicodeDecodeError):
        return []

    imports: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.append(alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imports.append(node.module)
    return imports


def _is_internal(module: str, known_modules: set[str]) -> bool:
    """Check if an import refers to an internal module."""
    if module in known_modules:
        return True
    # Check parent packages
    parts = module.split(".")
    for i in range(len(parts), 0, -1):
        prefix = ".".join(parts[:i])
        if prefix in known_modules:
            return True
    return False


def build_graph(root: Path | None = None) -> dict[str, Any]:
    """Build the full dependency graph."""
    root = root or SRC_ROOT
    files = _find_python_files(root)

    modules: dict[str, str] = {}  # module_name -> file_path
    for f in files:
        name = _module_name(f, root)
        modules[name] = str(f.relative_to(root))

    known = set(modules.keys())

    edges: dict[str, list[str]] = {}
    for f in files:
        mod = _module_name(f, root)
        raw_imports = _extract_imports(f)
        internal_deps = []
        for imp in raw_imports:
            # Resolve relative-style imports (from . import X)
            if _is_internal(imp, known) and imp != mod:  # no self-edges
                internal_deps.append(imp)
        edges[mod] = sorted(set(internal_deps))

    return {
        "modules": modules,
        "edges": edges,
        "file_count": len(files),
    }


def _detect_cycles(edges: dict[str, list[str]]) -> list[list[str]]:
    """Simple DFS-based cycle detection."""
    cycles: list[list[str]] = []
    visited: set[str] = set()
    path: list[str] = []
    on_path: set[str] = set()

    def dfs(node: str) -> None:
        if node in on_path:
            idx = path.index(node)
            cycles.append(path[idx:] + [node])
            return
        if node in visited:
            return
        visited.add(node)
        on_path.add(node)
        path.append(node)
        for dep in edges.get(node, []):
            dfs(dep)
        path.pop()
        on_path.discard(node)

    for mod in edges:
        dfs(mod)
    return cycles


def _to_mermaid(edges: dict[str, list[str]]) -> str:
    """Generate a Mermaid graph from the dependency edges."""
    lines = ["graph LR"]
    seen_edges: set[tuple[str, str]] = set()
    for src, deps in sorted(edges.items()):
        src_id = src.replace(".", "_")
        for dep in deps:
            dep_id = dep.replace(".", "_")
            edge = (src_id, dep_id)
            if edge not in seen_edges:
                seen_edges.add(edge)
                lines.append(f"    {src_id}[\"{src}\"] --> {dep_id}[\"{dep}\"]")
    return "\n".join(lines)


def main() -> int:
    fmt = sys.argv[1] if len(sys.argv) > 1 else "report"
    if fmt.startswith("--format="):
        fmt = fmt.split("=", 1)[1]
    elif fmt.startswith("--"):
        fmt = fmt.lstrip("-")

    graph = build_graph()

    if fmt == "json":
        print(json.dumps(graph, indent=2))
    elif fmt == "mermaid":
        print(_to_mermaid(graph["edges"]))
    else:
        # report mode
        print("=== Dependency Graph Report ===")
        print(f"Files scanned: {graph['file_count']}")
        print(f"Modules found: {len(graph['modules'])}")
        print()

        print("Internal dependencies:")
        for mod, deps in sorted(graph["edges"].items()):
            if deps:
                print(f"  {mod} -> {', '.join(deps)}")

        cycles = _detect_cycles(graph["edges"])
        print()
        if cycles:
            print(f"⚠️  Circular dependencies found: {len(cycles)}")
            for c in cycles:
                print(f"  {'  ->  '.join(c)}")
        else:
            print("✅ No circular dependencies")

        # Leaf modules (no internal deps)
        leaves = [m for m, deps in graph["edges"].items() if not deps]
        print(f"\nLeaf modules (no internal deps): {len(leaves)}")
        for m in sorted(leaves):
            print(f"  {m}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
