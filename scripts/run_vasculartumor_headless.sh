#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/run_vasculartumor_headless.sh [options]

Options:
  --radcell-dir PATH     Path to patched RADCELL checkout.
                         Default: $HOME/radcell/RADCELL

  --cc3d-python PATH     Path to CompuCell3D Python.
                         Default: $HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python

  --launcher PATH        Path to RADCELL/CC3D launcher.
                         Default: $HOME/run_radcell_cc3d_python.sh

  --output-dir PATH      Directory where run entries are created.
                         Default: $PWD/radcell_runs

  --timeout SECONDS      Maximum runtime for this smoke test.
                         Default: 120

  --help                 Show this help.

Default output layout:
  $PWD/radcell_runs/VascularTumor_cc3d_YYYY_MM_DD_HH_MM_SS_<id>/

Example:
  cd ~/Desktop/simulacoes

  /path/to/geant4-native-radcell/scripts/run_vasculartumor_headless.sh \
    --radcell-dir ~/radcell/RADCELL \
    --launcher ~/run_radcell_cc3d_python.sh
USAGE
}

CALL_DIR="$(pwd)"
RADCELL_DIR="$HOME/radcell/RADCELL"
CC3D_PYTHON="$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python"
LAUNCHER="$HOME/run_radcell_cc3d_python.sh"
OUTPUT_BASE="$CALL_DIR/radcell_runs"
TIMEOUT_SECONDS="120"
MODEL="VascularTumor"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --radcell-dir)
      RADCELL_DIR="$2"
      shift 2
      ;;
    --cc3d-python)
      CC3D_PYTHON="$2"
      shift 2
      ;;
    --launcher)
      LAUNCHER="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_BASE="$2"
      shift 2
      ;;
    --timeout)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

RADCELL_DIR="$(realpath -m "$RADCELL_DIR")"
CC3D_PYTHON="$(realpath -m "$CC3D_PYTHON")"
LAUNCHER="$(realpath -m "$LAUNCHER")"
OUTPUT_BASE="$(realpath -m "$OUTPUT_BASE")"

CC3D_FILE="$RADCELL_DIR/$MODEL/$MODEL.cc3d"

if [[ ! -d "$RADCELL_DIR" ]]; then
  echo "[ERROR] RADCELL directory not found: $RADCELL_DIR" >&2
  exit 1
fi

if [[ ! -f "$CC3D_FILE" ]]; then
  echo "[ERROR] CompuCell3D simulation file not found: $CC3D_FILE" >&2
  exit 1
fi

if [[ ! -x "$CC3D_PYTHON" ]]; then
  echo "[ERROR] CompuCell3D Python not found or not executable: $CC3D_PYTHON" >&2
  exit 1
fi

if [[ ! -x "$LAUNCHER" ]]; then
  echo "[ERROR] launcher not found or not executable: $LAUNCHER" >&2
  exit 1
fi

if ! command -v timeout >/dev/null 2>&1; then
  echo "[ERROR] timeout command not found. Install coreutils." >&2
  exit 1
fi

timestamp="$(date +%Y_%m_%d_%H_%M_%S)"
short_id="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(3))
PY
)"

RUN_NAME="${MODEL}_cc3d_${timestamp}_${short_id}"
RUN_DIR="$OUTPUT_BASE/$RUN_NAME"
LOG_FILE="$RUN_DIR/cc3d_headless.log"
MANIFEST="$RUN_DIR/run_manifest.json"

mkdir -p "$RUN_DIR"

cat > "$MANIFEST" <<JSON
{
  "model": "$MODEL",
  "created_at_local": "$timestamp",
  "run_id": "$short_id",
  "call_dir": "$CALL_DIR",
  "radcell_dir": "$RADCELL_DIR",
  "cc3d_python": "$CC3D_PYTHON",
  "launcher": "$LAUNCHER",
  "cc3d_file": "$CC3D_FILE",
  "output_base": "$OUTPUT_BASE",
  "run_dir": "$RUN_DIR",
  "timeout_seconds": $TIMEOUT_SECONDS
}
JSON

echo "[RADCELL] model: $MODEL"
echo "[RADCELL] call dir: $CALL_DIR"
echo "[RADCELL] RADCELL dir: $RADCELL_DIR"
echo "[RADCELL] CC3D file: $CC3D_FILE"
echo "[RADCELL] output dir: $RUN_DIR"
echo "[RADCELL] log: $LOG_FILE"
echo "[RADCELL] manifest: $MANIFEST"
echo "[RADCELL] timeout: ${TIMEOUT_SECONDS}s"
echo

validate_smoke_log() {
  local log_file="$1"

  if grep -Eq "COMMAND NOT FOUND </vis/open|/vis/open OGL|Can not open a macro file <vis\.mac>" "$log_file"; then
    echo "[ERROR] Found the old Geant4 visualization/OpenGL error in the log."
    echo "[ERROR] This RADCELL tree may not have the v0.4.1 headless patch applied."
    return 1
  fi

  local cc3d_ok=0
  local radcell_ok=0
  local geant4_ok=0

  if grep -Eq "CompuCell3D Version|XML is valid|INFO: Random number generator|INFO: Step|totalArea .*cell growth" "$log_file"; then
    cc3d_ok=1
  fi

  if grep -Eq "\[RADCELL\] running|Start calling subprocess RADCellSimulation|the runMode is:|runMode:|Loaded cells:" "$log_file"; then
    radcell_ok=1
  fi

  if grep -Eq "Geant4 version Name|G4DNASamplingTable|PhysicsList::SetCuts" "$log_file"; then
    geant4_ok=1
  fi

  echo
  echo "[RADCELL] smoke-test markers:"
  echo "  CC3D:    $cc3d_ok"
  echo "  RADCELL: $radcell_ok"
  echo "  Geant4:  $geant4_ok"

  if [[ "$cc3d_ok" -eq 1 && "$radcell_ok" -eq 1 && "$geant4_ok" -eq 1 ]]; then
    echo "[RADCELL] full CC3D/RADCELL/Geant4 chain was reached."
    return 0
  fi

  if [[ "$cc3d_ok" -eq 1 ]]; then
    echo
    echo "[RADCELL] CC3D started correctly."
    echo "[RADCELL] RADCELL/Geant4 was not reached before timeout."
    echo "[RADCELL] This is acceptable for a VascularTumor headless smoke test because radiation is triggered later in the CC3D run."
    echo "[RADCELL] Increase --timeout if you specifically want to observe the RADCELL/Geant4 call."
    return 0
  fi

  echo
  echo "[ERROR] Smoke test did not reach CC3D initialization markers."
  echo "[ERROR] See log: $log_file"
  return 1
}

set +e
timeout "$TIMEOUT_SECONDS" "$LAUNCHER" -m cc3d.run_script \
  -i "$CC3D_FILE" \
  --output-dir "$RUN_DIR" \
  2>&1 | tee "$LOG_FILE"

status=${PIPESTATUS[0]}
set -e

if [[ "$status" -eq 124 ]]; then
  echo
  echo "[RADCELL] timeout reached after ${TIMEOUT_SECONDS}s."
  validate_smoke_log "$LOG_FILE"
  echo
  echo "[RADCELL] smoke test passed before timeout."
  echo "[RADCELL] output dir: $RUN_DIR"
  exit 0
fi

if [[ "$status" -ne 0 ]]; then
  echo
  echo "[ERROR] Headless run failed with exit code $status."
  echo "[ERROR] See log: $LOG_FILE"
  exit "$status"
fi

validate_smoke_log "$LOG_FILE"

echo
echo "[RADCELL] headless run finished successfully."
echo "[RADCELL] output dir: $RUN_DIR"
