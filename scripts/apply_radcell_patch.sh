#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage:"
  echo "  $0 /path/to/RADCELL"
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

cd "$RADCELL_DIR"

echo "[RADCELL] Root directory:"
echo "  $RADCELL_DIR"
echo
echo "[RADCELL] Patch file:"
echo "  $PATCH_FILE"
echo

echo "[RADCELL] Testing whether patch can be applied..."

if patch --dry-run --batch --forward -p1 < "$PATCH_FILE"; then
  echo
  echo "[RADCELL] Applying patch..."
  patch --batch --forward -p1 < "$PATCH_FILE"
  echo
  echo "[RADCELL] Patch applied successfully."
  exit 0
fi

echo
echo "[RADCELL] Patch cannot be applied directly."
echo "[RADCELL] Checking whether it is already applied..."

if patch --dry-run --batch --reverse -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
  echo
  echo "[RADCELL] Patch is already applied."
  echo "[RADCELL] Nothing to do."
  exit 0
fi

echo
echo "ERROR: Patch failed and does not look already applied."
echo
echo "Possible causes:"
echo "  1. The RADCELL source version differs from the expected one."
echo "  2. The source was manually edited and now conflicts with the patch."
echo "  3. The patch was copied incorrectly."
echo
echo "Useful diagnostic command:"
echo
echo "  grep -RIn \"PyString_FromString\\|PyInt_AsLong\\|G4MTRunManager\\|g4root.hh\\|theParticleIterator\" \"$RADCELL_DIR/RADCellSimulation\""
echo
exit 2
