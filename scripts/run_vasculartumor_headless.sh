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

  --timeout SECONDS      Maximum runtime (default 120 for startup,
                         900 for --integration-test).

  --integration-test     Copy VascularTumor, run 20 MCS, irradiate at MCS 10,
                         and require full CC3D/RADCELL/Geant4 integration.

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALL_DIR="$(pwd)"
RADCELL_DIR="$HOME/radcell/RADCELL"
CC3D_PYTHON="$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python"
LAUNCHER="$HOME/run_radcell_cc3d_python.sh"
OUTPUT_BASE="$CALL_DIR/radcell_runs"
TIMEOUT_SECONDS="120"
MODEL="VascularTumor"
INTEGRATION_TEST=0
TIMEOUT_EXPLICIT=0
TEST_MODEL_DIR=""

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
      TIMEOUT_EXPLICIT=1
      shift 2
      ;;
    --integration-test)
      INTEGRATION_TEST=1
      shift
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

if [[ "$INTEGRATION_TEST" -eq 1 && "$TIMEOUT_EXPLICIT" -eq 0 ]]; then
  TIMEOUT_SECONDS=900
fi
if ! [[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "[ERROR] --timeout must be a positive integer." >&2
  exit 2
fi

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

if [[ "$INTEGRATION_TEST" -eq 1 ]]; then
  TEST_MODEL_DIR="$RUN_DIR/model/$MODEL"
  if ! python3 "$SCRIPT_DIR/prepare_vasculartumor_integration.py" \
    --source "$RADCELL_DIR/$MODEL" \
    --destination "$TEST_MODEL_DIR" \
    --steps 20 --radiation-mcs 10; then
    echo "[ERROR] Could not prepare isolated integration model." >&2
    exit 2
  fi
  CC3D_FILE="$TEST_MODEL_DIR/$MODEL.cc3d"
fi

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
  "timeout_seconds": $TIMEOUT_SECONDS,
  "integration_test": $INTEGRATION_TEST
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
  local cc3d_ok=0 geant4_ok=0 radcell_ok=0 completed_ok=0
  local events_ok=0 dose_ok=0 damage_ok=0 records_ok=0

  # CC3D can print a Python traceback and still return status zero.
  # Ordinary Geant4 warnings (e.g. ProcCuts110) are not fatal.
  if grep -Eq 'Traceback \(most recent call last\)|(^|[[:space:]])(PermissionError|ModuleNotFoundError|ImportError|FileNotFoundError|SyntaxError|RuntimeError|NameError):|Segmentation fault|terminate called after throwing|COMMAND NOT FOUND </vis/open|Can not open a macro file <vis\.mac>' "$log_file"; then
    echo "[FAIL] Fatal Python/Geant4 marker in $log_file" >&2
    return 1
  fi

  if grep -q 'XML is valid!' "$log_file"; then cc3d_ok=1; fi
  if grep -q 'RADCellSimulation subprocess finished' "$log_file"; then radcell_ok=1; fi
  if grep -q 'Geant4 version Name:' "$log_file"; then geant4_ok=1; fi
  if grep -q 'Now the processing event ID is:' "$log_file"; then events_ok=1; fi
  if grep -q 'Cell Dose Information:' "$log_file"; then dose_ok=1; fi
  if grep -q 'DNA Damage Information:' "$log_file"; then damage_ok=1; fi
  if grep -q 'PERFORMANCE REPORT:' "$log_file"; then completed_ok=1; fi

  if [[ "$INTEGRATION_TEST" -eq 1 ]]; then
    local file
    for file in "$TEST_MODEL_DIR/Simulation/"*cellNumber.csv; do
      [[ -f "$file" ]] || continue
      if [[ "$(wc -l < "$file")" -eq 20 ]]; then
        records_ok=1
        break
      fi
    done
  fi

  echo
  echo "[RADCELL] Validation markers:"
  echo "  CC3D initialized:      $cc3d_ok"
  echo "  CC3D run completed:    $completed_ok"
  echo "  RADCELL returned:      $radcell_ok"
  echo "  Geant4 initialized:    $geant4_ok"
  echo "  Particle events:       $events_ok"
  echo "  Cell dose:             $dose_ok"
  echo "  DNA damage:            $damage_ok"
  if [[ "$INTEGRATION_TEST" -eq 1 ]]; then
    echo "  20 CC3D records:       $records_ok"
    if [[ "$cc3d_ok" -eq 1 && "$completed_ok" -eq 1 && "$radcell_ok" -eq 1 &&
          "$geant4_ok" -eq 1 && "$events_ok" -eq 1 && "$dose_ok" -eq 1 &&
          "$damage_ok" -eq 1 && "$records_ok" -eq 1 ]]; then
      echo "[PASS] Complete CC3D -> RADCELL -> Geant4 -> CC3D integration run."
      return 0
    fi
    echo "[FAIL] Full integration test did not reach all markers." >&2
    return 1
  fi

  if [[ "$cc3d_ok" -eq 1 && "$completed_ok" -eq 1 ]]; then
    echo "[PASS] CC3D execution completed; radiation not required in startup mode."
    return 0
  fi
  echo "[FAIL] CC3D did not reach a completed run." >&2
  return 1
}

set +e
timeout "$TIMEOUT_SECONDS" "$LAUNCHER" -m cc3d.run_script \
  -i "$CC3D_FILE" \
  --output-dir "$RUN_DIR" \
  2>&1 | tee "$LOG_FILE"
status=$?
set -e

if [[ "$status" -eq 124 ]]; then
  echo "[TIMEOUT] Reached $TIMEOUT_SECONDS seconds; no successful completion." >&2
  echo "[RADCELL] Log: $LOG_FILE"
  exit 124
fi

if [[ "$status" -ne 0 ]]; then
  echo "[FAIL] Headless command exited with status $status." >&2
  echo "[RADCELL] Log: $LOG_FILE"
  exit "$status"
fi

if ! validate_smoke_log "$LOG_FILE"; then
  echo "[RADCELL] Log: $LOG_FILE" >&2
  exit 1
fi

echo "[RADCELL] output dir: $RUN_DIR"
