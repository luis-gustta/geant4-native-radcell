#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  apply_radcell_patch.sh /path/to/RADCELL

Applies the RADCELL compatibility patch distributed with this repository.

The argument must be the root of a RADCELL source tree, for example:
  /home/user/working_on/radcell/RADCELL

Expected inside that directory:
  RADCellSimulation/
  VascularTumor/
EOF
}

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

RADCELL_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PATCH_FILE="$REPO_DIR/patches/radcell_compat_geant4_11_python312_cc3d.patch"

if [ ! -d "$RADCELL_DIR" ]; then
  echo "ERROR: RADCELL directory does not exist:"
  echo "  $RADCELL_DIR"
  exit 1
fi

if [ ! -d "$RADCELL_DIR/RADCellSimulation" ]; then
  echo "ERROR: This does not look like a RADCELL root directory:"
  echo "  $RADCELL_DIR"
  echo
  echo "Expected:"
  echo "  $RADCELL_DIR/RADCellSimulation"
  exit 1
fi

if [ ! -f "$PATCH_FILE" ]; then
  echo "ERROR: Patch file not found:"
  echo "  $PATCH_FILE"
  exit 1
fi

if ! command -v patch >/dev/null 2>&1; then
  echo "ERROR: 'patch' command not found."
  echo "Install it with:"
  echo "  sudo apt install patch"
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DRY_LOG="$TMP_DIR/patch-dry-run.log"
APPLY_LOG="$TMP_DIR/patch-apply.log"
REVERSE_LOG="$TMP_DIR/patch-reverse-check.log"

cd "$RADCELL_DIR"

echo "[RADCELL] Root directory:"
echo "  $RADCELL_DIR"
echo
echo "[RADCELL] Patch file:"
echo "  $PATCH_FILE"
echo
echo "[RADCELL] Checking patch status..."

# Case 1: patch can be applied normally.
if patch --dry-run --batch --forward -p1 < "$PATCH_FILE" >"$DRY_LOG" 2>&1; then
  echo "[RADCELL] Patch can be applied."
  echo "[RADCELL] Applying patch..."

  if patch --batch --forward -p1 < "$PATCH_FILE" >"$APPLY_LOG" 2>&1; then
    echo "[RADCELL] Patch applied successfully."
    exit 0
  fi

  echo
  echo "ERROR: Patch dry-run succeeded, but patch application failed."
  echo
  echo "Patch output:"
  sed -n '1,160p' "$APPLY_LOG"
  exit 2
fi

# Case 2: patch is already applied.
# A reversed dry-run succeeds when the current source tree already contains
# the patch changes.
if patch --dry-run --batch --reverse -p1 < "$PATCH_FILE" >"$REVERSE_LOG" 2>&1; then
  echo "[RADCELL] Patch is already applied."
  echo "[RADCELL] Nothing to do."
  exit 0
fi

# Case 3: neither forward nor reverse worked.
echo
echo "ERROR: Patch cannot be applied and does not look already applied."
echo
echo "Possible causes:"
echo "  1. The RADCELL source version differs from the expected upstream version."
echo "  2. The source tree was manually edited and now conflicts with the patch."
echo "  3. The compatibility patch file was copied incorrectly."
echo
echo "Forward dry-run output:"
sed -n '1,160p' "$DRY_LOG"
echo
echo "Reverse dry-run output:"
sed -n '1,160p' "$REVERSE_LOG"
echo
echo "Useful diagnostic command:"
echo "  grep -RIn \"PyString_FromString\\|PyInt_AsLong\\|G4MTRunManager\\|g4root.hh\\|theParticleIterator\" \"$RADCELL_DIR/RADCellSimulation\""
echo

exit 2
