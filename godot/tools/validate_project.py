#!/usr/bin/env python3
"""Structural validator for the Godot project.

This is NOT a substitute for opening the project in Godot. It cannot type-check
GDScript, resolve engine APIs, or tell you whether the street looks right. What
it does do is catch the specific class of mistake that is fatal, silent and easy
to make when scene files are authored by hand rather than by the editor:

  * a .tscn referencing an ext_resource path that does not exist on disk
  * a SubResource(...) / ExtResource(...) id that was never declared
  * a sub_resource declared after the resource that uses it (load order)
  * a `load_steps` count that disagrees with the actual resource count
  * a node whose `parent=` path names a node that is not in the file
  * project.godot naming an autoload or main scene that is missing
  * .gd files with unbalanced brackets or mixed indentation

Run:  python3 godot/tools/validate_project.py
Exit: 0 clean, 1 if any error was found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

SECTION = re.compile(r"^\[(\w+)([^\]]*)\]\s*$")
ATTR = re.compile(r'(\w+)\s*=\s*"([^"]*)"')
EXT_REF = re.compile(r'ExtResource\(\s*"([^"]+)"\s*\)')
SUB_REF = re.compile(r'SubResource\(\s*"([^"]+)"\s*\)')

errors: list[str] = []
warnings: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def res_to_path(res: str) -> Path | None:
    """Map a res:// path onto a real file."""
    if not res.startswith("res://"):
        return None
    return ROOT / res[len("res://") :]


# --------------------------------------------------------------------- scenes


def check_scene(path: Path) -> None:
    rel = path.relative_to(ROOT)
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()

    if not lines or not lines[0].startswith("[gd_scene"):
        err(f"{rel}: first line must be a [gd_scene ...] header")
        return

    declared_ext: dict[str, str] = {}   # id -> res path
    declared_sub: set[str] = set()
    node_names: set[str] = set()
    resource_count = 0
    # Track declaration order so we can catch forward references.
    seen_order: list[tuple[str, str]] = []

    current: str | None = None
    header_attrs: dict[str, str] = {}

    for n, line in enumerate(lines, 1):
        m = SECTION.match(line)
        if m:
            current = m.group(1)
            header_attrs = dict(ATTR.findall(m.group(2)))

            if current == "ext_resource":
                resource_count += 1
                rid = header_attrs.get("id", "")
                rpath = header_attrs.get("path", "")
                if not rid:
                    err(f"{rel}:{n}: ext_resource with no id")
                declared_ext[rid] = rpath
                seen_order.append(("ext", rid))
                target = res_to_path(rpath)
                if target is None:
                    err(f"{rel}:{n}: ext_resource path is not res://: {rpath!r}")
                elif not target.exists():
                    err(f"{rel}:{n}: ext_resource missing on disk: {rpath}")

            elif current == "sub_resource":
                resource_count += 1
                rid = header_attrs.get("id", "")
                if not rid:
                    err(f"{rel}:{n}: sub_resource with no id")
                declared_sub.add(rid)
                seen_order.append(("sub", rid))

            elif current == "node":
                name = header_attrs.get("name", "")
                parent = header_attrs.get("parent")
                if parent not in (None, ".") and parent != "":
                    # "A/B" must resolve against nodes already declared.
                    head = parent.split("/")[0]
                    if head != "." and head not in node_names:
                        err(
                            f"{rel}:{n}: node {name!r} has parent "
                            f"{parent!r} which is not declared above it"
                        )
                node_names.add(name)
            continue

        # Body lines: check every resource reference resolves.
        for rid in EXT_REF.findall(line):
            if rid not in declared_ext:
                err(f"{rel}:{n}: ExtResource({rid!r}) was never declared")
        for rid in SUB_REF.findall(line):
            if rid not in declared_sub:
                err(
                    f"{rel}:{n}: SubResource({rid!r}) is not declared, or is "
                    f"declared LATER in the file (Godot loads in file order)"
                )

    # load_steps: Godot writes resource_count + 1.
    m = re.search(r"load_steps=(\d+)", lines[0])
    if m:
        want = resource_count + 1
        got = int(m.group(1))
        if got != want:
            warn(
                f"{rel}:1: load_steps={got} but the file declares "
                f"{resource_count} resources (expected {want})"
            )
    elif resource_count:
        warn(f"{rel}:1: {resource_count} resources but no load_steps in header")


# ---------------------------------------------------------------- gdscript


def check_gd(path: Path) -> None:
    rel = path.relative_to(ROOT)
    text = path.read_text(encoding="utf-8")

    depth = {"(": 0, "[": 0, "{": 0}
    pairs = {")": "(", "]": "[", "}": "{"}
    for n, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0] if not line.lstrip().startswith("#") else ""
        # Strip string literals so brackets inside them do not count.
        code = re.sub(r'"[^"]*"', '""', code)
        code = re.sub(r"'[^']*'", "''", code)
        for ch in code:
            if ch in depth:
                depth[ch] += 1
            elif ch in pairs:
                depth[pairs[ch]] -= 1
                if depth[pairs[ch]] < 0:
                    err(f"{rel}:{n}: unbalanced {ch!r}")
                    depth[pairs[ch]] = 0

        if line.startswith(" ") and line.strip():
            err(f"{rel}:{n}: leading space — GDScript here is tab-indented")

    for opener, count in depth.items():
        if count:
            err(f"{rel}: {count} unclosed {opener!r} at end of file")


# ------------------------------------------------------------- project.godot


def check_project() -> None:
    path = ROOT / "project.godot"
    if not path.exists():
        err("project.godot is missing")
        return
    text = path.read_text(encoding="utf-8")

    m = re.search(r'run/main_scene="([^"]+)"', text)
    if not m:
        err("project.godot: no run/main_scene set")
    else:
        target = res_to_path(m.group(1))
        if target is None or not target.exists():
            err(f"project.godot: main_scene missing on disk: {m.group(1)}")

    for name, res in re.findall(r'^(\w+)="\*?(res://[^"]+)"$', text, re.M):
        target = res_to_path(res)
        if target is None or not target.exists():
            err(f"project.godot: autoload {name} -> missing {res}")

    if 'renderer/rendering_method="gl_compatibility"' not in text:
        warn(
            "project.godot: renderer is not gl_compatibility — the stated "
            "Android target is a low-end phone"
        )


def main() -> int:
    check_project()
    # Third-party addons are vendored; do not fail the project on their
    # internal scene/script quirks. Our gameplay content lives outside addons/.
    scenes = sorted(p for p in ROOT.rglob("*.tscn") if "addons" not in p.parts)
    scripts = sorted(p for p in ROOT.rglob("*.gd") if "addons" not in p.parts)
    for s in scenes:
        check_scene(s)
    for s in scripts:
        check_gd(s)

    print(f"checked {len(scenes)} scenes, {len(scripts)} scripts")
    for w in warnings:
        print(f"  WARN  {w}")
    for e in errors:
        print(f"  ERROR {e}")
    if errors:
        print(f"\nFAILED — {len(errors)} error(s)")
        return 1
    print(f"\nOK — no structural errors ({len(warnings)} warning(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
