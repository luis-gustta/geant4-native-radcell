#!/usr/bin/env python3
"""Prepare an isolated, short VascularTumor integration run.

Only the copied experiment is edited. The radiation source and physics
parameters remain unchanged. This is a software integration test, not a
quantitative dosimetry benchmark.
"""
import argparse
import ast
import re
import shutil
from pathlib import Path


def contains_call(node, object_name, method_name):
    return any(
        isinstance(item, ast.Call)
        and isinstance(item.func, ast.Attribute)
        and isinstance(item.func.value, ast.Name)
        and item.func.value.id == object_name
        and item.func.attr == method_name
        for item in ast.walk(node)
    )


def change_radiation_trigger(path: Path, trigger: int) -> None:
    source = path.read_text()
    tree = ast.parse(source, filename=str(path))
    candidates = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.If):
            continue
        if not any(isinstance(x, ast.Name) and x.id == "mcs" for x in ast.walk(node.test)):
            continue
        if any(contains_call(stmt, "radTransport", "Run") for stmt in node.body):
            candidates.append(node)

    if len(candidates) != 1:
        raise ValueError(
            f"Expected exactly one MCS-dependent radiation block in {path}, "
            f"found {len(candidates)}; refusing to alter the scientific model."
        )

    node = candidates[0]
    lines = source.splitlines(keepends=True)
    original = lines[node.lineno - 1]
    match = re.fullmatch(r"(\s*)if\s+.+:\s*(?:#.*)?\n?", original)
    if not match:
        raise ValueError(f"Radiation condition uses an unsupported layout at line {node.lineno}")
    lines[node.lineno - 1] = f"{match.group(1)}if mcs == {trigger}:\n"
    path.write_text("".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Source VascularTumor folder")
    parser.add_argument("--destination", type=Path, required=True, help="New isolated VascularTumor folder")
    parser.add_argument("--steps", type=int, default=20)
    parser.add_argument("--radiation-mcs", type=int, default=10)
    args = parser.parse_args()

    if not 0 < args.radiation_mcs < args.steps:
        parser.error("radiation-mcs must be positive and smaller than steps")
    if args.destination.exists():
        parser.error(f"Destination already exists: {args.destination}")

    xml = args.source / "Simulation/VascularTumor.xml"
    script = args.source / "Simulation/VascularTumorSteppables.py"
    if not xml.is_file() or not script.is_file():
        parser.error("Expected Simulation/VascularTumor.xml and VascularTumorSteppables.py")

    # Verify the source can be understood before copying it.
    ast.parse(script.read_text(), filename=str(script))
    xml_text = xml.read_text()
    if len(re.findall(r"<Steps>\s*\d+\s*</Steps>", xml_text)) != 1:
        parser.error("Expected exactly one <Steps> element")

    shutil.copytree(args.source, args.destination)
    dest_xml = args.destination / "Simulation/VascularTumor.xml"
    dest_script = args.destination / "Simulation/VascularTumorSteppables.py"
    dest_xml.write_text(
        re.sub(r"(<Steps>\s*)\d+(\s*</Steps>)",
               lambda m: m.group(1) + str(args.steps) + m.group(2),
               xml_text, count=1)
    )
    change_radiation_trigger(dest_script, args.radiation_mcs)

    # Known optional visualization paths in customized versions of VascularTumor.
    # Redirect these to this run instead of writing into another user's home.
    for name in ("VideoFrameSteppable.py", "VascularTumorSteppables.py"):
        file = args.destination / "Simulation" / name
        if not file.is_file():
            continue
        text = file.read_text()
        for key, folder in (
            ("radcell_video_frames", "video_frames"),
            ("radcell_voxel_frames", "voxel_frames"),
        ):
            text = re.sub(
                r"/home/[^/]+/Desktop/working_on/" + key,
                str(args.destination.parent.parent / folder),
                text,
            )
        file.write_text(text)

    # Confirm the modified Python script is syntactically valid.
    compile(dest_script.read_text(), str(dest_script), "exec")
    print(f"[RADCELL] Isolated model: {args.destination}")
    print(f"[RADCELL] CC3D steps: {args.steps}; radiation MCS: {args.radiation_mcs}")
    print("[RADCELL] Original RADCELL checkout was not modified.")


if __name__ == "__main__":
    main()
