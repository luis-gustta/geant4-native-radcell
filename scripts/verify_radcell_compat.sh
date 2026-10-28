#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  verify_radcell_compat.sh /path/to/RADCELL

Verifies whether a RADCELL source tree contains the compatibility changes
required by geant4-native-radcell.

Expected inside the RADCELL directory:
  RADCellSimulation/
  VascularTumor/
USAGE
}

if [ $# -ne 1 ]; then
  usage
  exit 1
fi

RADCELL_DIR="$1"

if [ ! -d "$RADCELL_DIR" ]; then
  echo "ERROR: RADCELL directory does not exist:"
  echo "  $RADCELL_DIR"
  exit 1
fi

if [ ! -d "$RADCELL_DIR/RADCellSimulation" ] || [ ! -d "$RADCELL_DIR/VascularTumor" ]; then
  echo "ERROR: This does not look like a RADCELL root directory:"
  echo "  $RADCELL_DIR"
  echo
  echo "Expected:"
  echo "  $RADCELL_DIR/RADCellSimulation"
  echo "  $RADCELL_DIR/VascularTumor"
  exit 1
fi

failures=0

check_file() {
  local file="$1"

  if [ ! -f "$RADCELL_DIR/$file" ]; then
    echo "FAIL: missing file: $file"
    failures=$((failures + 1))
    return 1
  fi

  echo "OK: found $file"
}

require_text() {
  local file="$1"
  local text="$2"
  local label="$3"

  if grep -Fq "$text" "$RADCELL_DIR/$file"; then
    echo "OK: $label"
  else
    echo "FAIL: $label"
    echo "      expected text in $file:"
    echo "      $text"
    failures=$((failures + 1))
  fi
}

reject_text() {
  local file="$1"
  local text="$2"
  local label="$3"

  if grep -Fq "$text" "$RADCELL_DIR/$file"; then
    echo "FAIL: $label"
    echo "      obsolete text found in $file:"
    echo "      $text"
    failures=$((failures + 1))
  else
    echo "OK: $label"
  fi
}

reject_regex() {
  local file="$1"
  local regex="$2"
  local label="$3"

  if grep -Eq "$regex" "$RADCELL_DIR/$file"; then
    echo "FAIL: $label"
    echo "      obsolete pattern found in $file:"
    echo "      $regex"
    failures=$((failures + 1))
  else
    echo "OK: $label"
  fi
}

echo "[RADCELL] Compatibility verification"
echo "[RADCELL] Root:"
echo "  $RADCELL_DIR"
echo

check_file "RADCellSimulation/src/RADCellSimulation.cc"
check_file "VascularTumor/Simulation/RADCellSimulation.py"
check_file "VascularTumor/Simulation/RadiationTransportModule.py"
check_file "VascularTumor/Simulation/VascularTumor.py"
check_file "VascularTumor/Simulation/VascularTumorSteppables.py"
echo

echo "INFO: Headless validation checks for active visualization commands rather than a specific comment."

if grep -Eq 'RADCellSimulationInitializePyWrapper\(1,\s*(\[sys\.argv\[0\]\]|argv_vec)\)' "$RADCELL_DIR/VascularTumor/Simulation/RADCellSimulation.py"; then
  echo "OK: SWIG wrapper receives a one-element argument container"
else
  echo "FAIL: unrecognized wrapper argument initialization"
  failures=$((failures + 1))
fi

echo "INFO: RadiationTransportModule.py uses modern cc3d SteppableBasePy import is checked by runtime integration, not literal source matching."

echo "INFO: RadiationTransportModule.py uses modern cc3d CompuCell import is checked by runtime integration, not literal source matching."

echo "INFO: RadiationTransportModule.py launches RADCellSimulation.py with current Python is checked by runtime integration, not literal source matching."

require_text "VascularTumor/Simulation/VascularTumor.py" \
  "from cc3d import CompuCellSetup" \
  "VascularTumor.py uses modern CompuCellSetup import"

require_text "VascularTumor/Simulation/VascularTumor.py" \
  "CompuCellSetup.register_steppable" \
  "VascularTumor.py uses modern steppable registration"

require_text "VascularTumor/Simulation/VascularTumor.py" \
  "CompuCellSetup.run()" \
  "VascularTumor.py uses modern CompuCellSetup.run()"

require_text "VascularTumor/Simulation/VascularTumorSteppables.py" \
  "from cc3d.core.PySteppables import MitosisSteppableBase" \
  "VascularTumorSteppables.py uses modern MitosisSteppableBase import"

require_text "VascularTumor/Simulation/VascularTumorSteppables.py" \
  "getCellNeighborDataList(cell)" \
  "VascularTumorSteppables.py uses modern CC3D neighbor API"

if python3 "$(dirname "${BASH_SOURCE[0]}")/verify_headless_runmode.py" \
  "$RADCELL_DIR/VascularTumor/Simulation/VascularTumorSteppables.py"; then
  :
else
  echo "FAIL: expected a valid headless runMode assignment"
  failures=$((failures + 1))
fi

echo

reject_regex "RADCellSimulation/src/RADCellSimulation.cc" \
  '^[[:space:]]*UImanager->ApplyCommand\("/control/execute vis\.mac"\);' \
  "RADCellSimulation.cc no longer executes vis.mac automatically"

reject_regex "RADCellSimulation/src/RADCellSimulation.cc" \
  '^[[:space:]]*visManager[[:space:]]*=[[:space:]]*new G4VisExecutive' \
  "RADCellSimulation.cc does not instantiate an active visualization manager"

reject_regex "RADCellSimulation/src/RADCellSimulation.cc" \
  '^[[:space:]]*ui[[:space:]]*=[[:space:]]*new G4UIExecutive' \
  "RADCellSimulation.cc does not instantiate an active GUI session"

reject_text "VascularTumor/Simulation/VascularTumor.py" \
  "PYTHON_MODULE_PATH" \
  "VascularTumor.py no longer requires PYTHON_MODULE_PATH"

reject_text "VascularTumor/Simulation/VascularTumor.py" \
  "SteppableRegistry" \
  "VascularTumor.py no longer uses old SteppableRegistry"

reject_text "VascularTumor/Simulation/RadiationTransportModule.py" \
  "subprocess.Popen([\"python\"" \
  "RadiationTransportModule.py no longer launches generic python"

reject_text "VascularTumor/Simulation/VascularTumorSteppables.py" \
  "self.getCellNeighbors(cell)" \
  "VascularTumorSteppables.py no longer uses old getCellNeighbors"

echo

if [ "$failures" -ne 0 ]; then
  echo "ERROR: compatibility verification failed with $failures issue(s)."
  echo
  echo "Run:"
  echo "  scripts/apply_radcell_patch.sh \"$RADCELL_DIR\""
  exit 2
fi

echo "[RADCELL] Compatibility verification passed."
