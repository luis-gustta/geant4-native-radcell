#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOUSAGE'
RADCELL minimal validation

Usage:
  examples/radcell_minimal/run_validation.sh [options]

Options:
  --radcell-root PATH     Path to the RADCELL source tree.
                          Default: $RADCELL_ROOT or ~/radcell/RADCELL

  --launcher PATH         Path to the RADCELL/CompuCell3D Python launcher.
                          Default: $RADCELL_LAUNCHER or ~/run_radcell_cc3d_python.sh

  --log-dir PATH          Directory where validation logs will be written.
                          Default: temporary directory under /tmp

  --timeout SECONDS       Timeout for the direct RADCellSimulation.py test.
                          Default: $TIMEOUT_SECONDS or 120

  -h, --help              Show this help message.

Environment variables:
  RADCELL_ROOT            Default RADCELL source tree.
  RADCELL_LAUNCHER        Default launcher.
  TIMEOUT_SECONDS         Default timeout for direct simulation test.
  LOG_DIR                 Default log directory.

Examples:
  examples/radcell_minimal/run_validation.sh

  examples/radcell_minimal/run_validation.sh \
    --radcell-root /home/luis/Desktop/Test/RADCELL \
    --launcher /home/luis/run_radcell_cc3d_python.sh
EOUSAGE
}

info() {
  printf '[INFO] %s\n' "$*"
}

ok() {
  printf '[PASS] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

expand_path() {
  local p
  p=$1

  case "$p" in
    \~)
      printf '%s\n' "$HOME"
      ;;
    \~/*)
      printf '%s/%s\n' "$HOME" "${p:2}"
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

require_file() {
  local path
  path=$1

  [[ -f "$path" ]] || fail "Missing required file: $path"
  ok "Found file: $path"
}

require_dir() {
  local path
  path=$1

  [[ -d "$path" ]] || fail "Missing required directory: $path"
  ok "Found directory: $path"
}

check_log_pattern() {
  local pattern
  local file
  local description

  pattern=$1
  file=$2
  description=$3

  if grep -Eq "$pattern" "$file"; then
    ok "$description"
  else
    warn "Could not confirm from log: $description"
  fi
}

RADCELL_ROOT="${RADCELL_ROOT:-$HOME/radcell/RADCELL}"
RADCELL_LAUNCHER="${RADCELL_LAUNCHER:-$HOME/run_radcell_cc3d_python.sh}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"
LOG_DIR="${LOG_DIR:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --radcell-root)
      shift
      [[ $# -gt 0 ]] || fail "--radcell-root requires a path"
      RADCELL_ROOT=$1
      ;;
    --launcher)
      shift
      [[ $# -gt 0 ]] || fail "--launcher requires a path"
      RADCELL_LAUNCHER=$1
      ;;
    --log-dir)
      shift
      [[ $# -gt 0 ]] || fail "--log-dir requires a path"
      LOG_DIR=$1
      ;;
    --timeout)
      shift
      [[ $# -gt 0 ]] || fail "--timeout requires a number of seconds"
      TIMEOUT_SECONDS=$1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
  shift
done

[[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || fail "--timeout must be an integer number of seconds"

RADCELL_ROOT=$(expand_path "$RADCELL_ROOT")
RADCELL_LAUNCHER=$(expand_path "$RADCELL_LAUNCHER")

if [[ -z "$LOG_DIR" ]]; then
  LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/radcell-minimal-validation.XXXXXX")
else
  LOG_DIR=$(expand_path "$LOG_DIR")
  mkdir -p "$LOG_DIR"
fi

IMPORT_LOG="$LOG_DIR/import_radcell.log"
DIRECT_LOG="$LOG_DIR/direct_radcellsimulation.log"

SIM_DIR="$RADCELL_ROOT/VascularTumor/Simulation"
SIM_SCRIPT="$SIM_DIR/RADCellSimulation.py"
SOURCE_FILE="$SIM_DIR/testInputSource.in"
CELL_FILE="$SIM_DIR/cellInformation.csv"

info "RADCELL root:     $RADCELL_ROOT"
info "Launcher:         $RADCELL_LAUNCHER"
info "Simulation dir:   $SIM_DIR"
info "Log dir:          $LOG_DIR"
info "Timeout:          ${TIMEOUT_SECONDS}s"

require_dir "$RADCELL_ROOT"
require_dir "$SIM_DIR"
require_file "$RADCELL_LAUNCHER"
require_file "$SIM_SCRIPT"
require_file "$SOURCE_FILE"
require_file "$CELL_FILE"

[[ -x "$RADCELL_LAUNCHER" ]] || fail "Launcher is not executable: $RADCELL_LAUNCHER"
ok "Launcher is executable"

info "Testing Python import: import radcell"
if "$RADCELL_LAUNCHER" -c 'import radcell; print(radcell.__file__)' >"$IMPORT_LOG" 2>&1; then
  ok "Python can import radcell through the launcher"
else
  cat "$IMPORT_LOG" >&2
  fail "Python import test failed"
fi

check_log_pattern 'radcell\.py|_radcell' "$IMPORT_LOG" "Import log points to the RADCELL Python module"

info "Running RADCellSimulation.py directly"
info "Direct run log: $DIRECT_LOG"

direct_status=0
set +e
(
  cd "$SIM_DIR" || exit 1

  if command -v timeout >/dev/null 2>&1; then
    PYTHONUNBUFFERED=1 timeout "$TIMEOUT_SECONDS" "$RADCELL_LAUNCHER" -u RADCellSimulation.py out testInputSource
  else
    PYTHONUNBUFFERED=1 "$RADCELL_LAUNCHER" -u RADCellSimulation.py out testInputSource
  fi
) >"$DIRECT_LOG" 2>&1
direct_status=$?
set -e

if [[ "$direct_status" -eq 0 ]]; then
  ok "RADCellSimulation.py completed"
elif [[ "$direct_status" -eq 124 ]]; then
  warn "RADCellSimulation.py reached the timeout limit"
  warn "This may still be enough to validate initialization; checking log patterns"
else
  tail -80 "$DIRECT_LOG" >&2 || true
  fail "RADCellSimulation.py failed with exit code $direct_status"
fi

if grep -Eq 'Geant4|runMode|radiationSource|Loaded cells|cellInformation' "$DIRECT_LOG"; then
  ok "Direct run reached RADCELL/Geant4 startup"
else
  tail -80 "$DIRECT_LOG" >&2 || true
  fail "Direct run did not show expected RADCELL/Geant4 startup lines"
fi

check_log_pattern 'cellInformation' "$DIRECT_LOG" "RADCELL checked or read cellInformation.csv"
check_log_pattern 'Loaded cells|Tissue dimensions' "$DIRECT_LOG" "RADCELL read cell geometry information"
check_log_pattern 'Geant4|geant4' "$DIRECT_LOG" "Geant4 initialization appeared in the log"
check_log_pattern 'runMode|test_cc3d' "$DIRECT_LOG" "Run mode appeared in the log"
check_log_pattern 'radiationSource|testInputSource' "$DIRECT_LOG" "Radiation source appeared in the log"

ok "Minimal RADCELL validation finished"
info "Logs were written to: $LOG_DIR"
info "This validates the installation path, not the full biological or radiation model."
