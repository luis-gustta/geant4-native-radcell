#!/usr/bin/env python3
"""Check that a VascularTumor steppable constructs the headless RADCELL run mode.

Equivalent Python expressions are recognized using the standard-library AST,
not by matching an exact spelling of the string concatenation.
"""
import ast
import sys
from pathlib import Path


_SIMULATION_ID = object()


def _parts(node):
    """Flatten constant-string concatenations and self.simulationID."""
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return [node.value]
    if (
        isinstance(node, ast.Attribute)
        and node.attr == "simulationID"
        and isinstance(node.value, ast.Name)
        and node.value.id == "self"
    ):
        return [_SIMULATION_ID]
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left, right = _parts(node.left), _parts(node.right)
        if left is not None and right is not None:
            return left + right
    if isinstance(node, ast.JoinedStr):
        flattened = []
        for part in node.values:
            if isinstance(part, ast.FormattedValue):
                if part.conversion != -1 or part.format_spec is not None:
                    return None
                flattened_part = _parts(part.value)
                if flattened_part != [_SIMULATION_ID]:
                    return None
                flattened.extend(flattened_part)
            elif isinstance(part, ast.Constant) and isinstance(part.value, str):
                flattened.append(part.value)
            else:
                return None
        return flattened
    return None


def is_headless_runmode_expression(node):
    parts = _parts(node)
    if parts is None or parts.count(_SIMULATION_ID) != 1:
        return False
    index = parts.index(_SIMULATION_ID)
    return "".join(parts[:index]) == "out " and parts[index + 1:] == []


def check_source(source):
    """Return true if an active assignment builds 'out ' + self.simulationID."""
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            assigned = any(
                isinstance(target, ast.Name) and target.id == "runMode"
                for target in node.targets
            )
            expression = node.value
        elif isinstance(node, ast.AnnAssign):
            assigned = isinstance(node.target, ast.Name) and node.target.id == "runMode"
            expression = node.value
        else:
            continue
        if assigned and expression is not None and is_headless_runmode_expression(expression):
            return True
    return False


def main():
    if len(sys.argv) != 2:
        print("Usage: verify_headless_runmode.py /path/to/VascularTumorSteppables.py", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        found = check_source(path.read_text(encoding="utf-8"))
    except (OSError, SyntaxError) as exc:
        print(f"FAIL: cannot parse {path}: {exc}", file=sys.stderr)
        return 2
    if found:
        print("OK: headless run mode (equivalent Python expressions accepted)")
        return 0
    print(
        "FAIL: no active assignment equivalent to "
        "runMode = 'out ' + self.simulationID",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
