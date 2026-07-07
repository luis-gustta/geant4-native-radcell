#!/usr/bin/env bash
set -euo pipefail

# setup_radcell_stack.sh
#
# RADCELL stack setup orchestrator.
#
# Maintainer: Luis Gustavo Lang Gaiato
# Repository: https://github.com/luis-gustta/geant4-native-radcell
#
# This script prepares a local RADCELL workflow using:
#   - native Geant4 from this repository;
#   - the original upstream RADCELL source tree;
#   - the RADCELL compatibility patch provided here;
#   - the Python environment used by CompuCell3D.
#
# It is intentionally an orchestrator. Low-level steps are delegated to:
#   scripts/apply_radcell_patch.sh
#   scripts/verify_radcell_compat.sh
#   scripts/build_radcell.sh
#   scripts/create_radcell_launcher.sh

VERSION="0.4.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# User-facing default. This means:
#   --workdir ~/radcell
# creates or uses:
#   ~/radcell/RADCELL
DEFAULT_WORKDIR="$HOME/radcell"

DEFAULT_GEANT4_PREFIX="/opt/geant4/11.4.2"
DEFAULT_RADCELL_PREFIX="$HOME/.local/radcell"
DEFAULT_LAUNCHER="$HOME/run_radcell_cc3d_python.sh"
DEFAULT_RADCELL_URL="https://github.com/forgetsummer/RADCELL.git"

WORKDIR=""
CC3D_PYTHON=""
GEANT4_PREFIX="$DEFAULT_GEANT4_PREFIX"
RADCELL_PREFIX="$DEFAULT_RADCELL_PREFIX"
LAUNCHER="$DEFAULT_LAUNCHER"
RADCELL_URL="$DEFAULT_RADCELL_URL"
JOBS="$(nproc)"
NON_INTERACTIVE=0
ASSUME_YES=0
SKIP_GEANT4_INSTALL=0
SKIP_CLONE=0
SKIP_PATCH=0
SKIP_VERIFY=0
SKIP_BUILD=0
SKIP_LAUNCHER=0
SKIP_IMPORT_TEST=0
NO_COLOR=0
DRY_RUN=0

LOG_ROOT="${TMPDIR:-/tmp}/radcell-stack-setup"
mkdir -p "$LOG_ROOT"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="$LOG_ROOT/$RUN_ID"
mkdir -p "$LOG_DIR"

if [ -t 1 ] && [ "${TERM:-}" != "dumb" ]; then
  USE_COLOR=1
else
  USE_COLOR=0
fi

color() {
  local code="$1"
  shift
  if [ "$USE_COLOR" -eq 1 ] && [ "$NO_COLOR" -eq 0 ]; then
    printf '\033[%sm%s\033[0m' "$code" "$*"
  else
    printf '%s' "$*"
  fi
}

bold() { color "1" "$*"; }
green() { color "32" "$*"; }
yellow() { color "33" "$*"; }
red() { color "31" "$*"; }
blue() { color "34" "$*"; }
dim() { color "2" "$*"; }

print_header() {
  echo
  bold "RADCELL Stack Setup v$VERSION"
  echo
  echo "Repository: $REPO_DIR"
  echo "Logs:       $LOG_DIR"
  echo
}

usage() {
  cat <<EOF
Usage:
  scripts/setup_radcell_stack.sh [options]

Typical interactive use:
  ./scripts/setup_radcell_stack.sh

Typical non-interactive use:
  ./scripts/setup_radcell_stack.sh \\
    --workdir ~/radcell \\
    --cc3d-python ~/CompuCell3D/miniforge3/envs/cc3d_env/bin/python \\
    --yes

Options:
  --workdir PATH              Parent directory where RADCELL will be cloned or found.
                              With --workdir ~/radcell, this script uses:
                              ~/radcell/RADCELL

  --cc3d-python PATH          Python interpreter from the CompuCell3D environment.

  --geant4-prefix PATH        Geant4 install prefix.
                              Default: $DEFAULT_GEANT4_PREFIX

  --radcell-prefix PATH       RADCELL install prefix.
                              Default: $DEFAULT_RADCELL_PREFIX

  --launcher PATH             Output launcher path.
                              Default: $DEFAULT_LAUNCHER

  --radcell-url URL           RADCELL git URL.
                              Default: $DEFAULT_RADCELL_URL

  --jobs N                    Build jobs.
                              Default: nproc

  --yes, -y                   Accept default choices.
  --non-interactive           Do not ask questions. Fail if required values are missing.

  --skip-geant4-install       Do not attempt to install Geant4 if missing.
  --skip-clone                Do not clone RADCELL if missing.
  --skip-patch                Skip applying the RADCELL compatibility patch.
  --skip-verify               Skip verifying the patched RADCELL source tree.
  --skip-build                Skip building RADCELL.
  --skip-launcher             Skip launcher creation.
  --skip-import-test          Skip final Python import test.

  --dry-run                   Print the resolved plan but do not modify anything.
  --no-color                  Disable colored output.
  --help, -h                  Show this help.
EOF
}

fail() {
  echo
  red "ERROR:"
  echo " $*" >&2
  echo
  echo "Logs directory:"
  echo "  $LOG_DIR"
  exit 1
}

warn() {
  yellow "WARNING:"
  echo " $*"
}

info() {
  blue "INFO:"
  echo " $*"
}

ok() {
  green "OK:"
  echo " $*"
}

section() {
  echo
  bold "==> $*"
  echo
}

expand_path() {
  local p="$1"
  if [ -z "$p" ]; then
    echo ""
    return
  fi

  case "$p" in
    \~) echo "$HOME" ;;
    \~/*) echo "$HOME/${p#~/}" ;;
    *) echo "$p" ;;
  esac
}

parent_dir() {
  local p="$1"
  dirname "$p"
}

is_radcell_root() {
  local p="$1"
  [ -d "$p" ] && [ -d "$p/RADCellSimulation" ] && [ -d "$p/VascularTumor" ]
}

require_command() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [ -n "$hint" ]; then
      fail "Required command '$cmd' was not found. $hint"
    else
      fail "Required command '$cmd' was not found."
    fi
  fi
}

prompt_input() {
  local prompt="$1"
  local default="$2"
  local answer=""

  if [ "$NON_INTERACTIVE" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ]; then
    echo "$default"
    return
  fi

  read -r -p "$prompt [$default]: " answer
  if [ -z "$answer" ]; then
    echo "$default"
  else
    echo "$answer"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="${2:-yes}"
  local answer=""

  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi

  if [ "$NON_INTERACTIVE" -eq 1 ]; then
    case "$default" in
      yes|y|Y|YES) return 0 ;;
      *) return 1 ;;
    esac
  fi

  while true; do
    if [ "$default" = "yes" ]; then
      read -r -p "$prompt [Y/n]: " answer
      answer="${answer:-y}"
    else
      read -r -p "$prompt [y/N]: " answer
      answer="${answer:-n}"
    fi

    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

spinner_run() {
  local label="$1"
  local logfile="$2"
  shift 2

  echo -n "$label "

  if [ "$DRY_RUN" -eq 1 ]; then
    dim "[dry-run]"
    echo
    printf 'Command:' > "$logfile"
    printf ' %q' "$@" >> "$logfile"
    printf '\n' >> "$logfile"
    return 0
  fi

  set +e
  "$@" >"$logfile" 2>&1 &
  local pid=$!
  local frames="|/-\\"
  local i=0

  while kill -0 "$pid" >/dev/null 2>&1; do
    printf "\r%s %s" "$label" "${frames:i++%${#frames}:1}"
    sleep 0.15
  done

  wait "$pid"
  local status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    printf "\r%s " "$label"
    green "done"
    echo
    return 0
  fi

  printf "\r%s " "$label"
  red "failed"
  echo
  echo
  echo "Command failed:"
  printf '  %q' "$@"
  echo
  echo
  echo "Log file:"
  echo "  $logfile"
  echo
  echo "Last 80 log lines:"
  sed -n '1,999999p' "$logfile" | tail -80
  echo
  exit "$status"
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --workdir)
        [ $# -ge 2 ] || fail "--workdir requires a path."
        WORKDIR="$(expand_path "$2")"
        shift 2
        ;;
      --cc3d-python)
        [ $# -ge 2 ] || fail "--cc3d-python requires a path."
        CC3D_PYTHON="$(expand_path "$2")"
        shift 2
        ;;
      --geant4-prefix)
        [ $# -ge 2 ] || fail "--geant4-prefix requires a path."
        GEANT4_PREFIX="$(expand_path "$2")"
        shift 2
        ;;
      --radcell-prefix)
        [ $# -ge 2 ] || fail "--radcell-prefix requires a path."
        RADCELL_PREFIX="$(expand_path "$2")"
        shift 2
        ;;
      --launcher)
        [ $# -ge 2 ] || fail "--launcher requires a path."
        LAUNCHER="$(expand_path "$2")"
        shift 2
        ;;
      --radcell-url)
        [ $# -ge 2 ] || fail "--radcell-url requires a URL."
        RADCELL_URL="$2"
        shift 2
        ;;
      --jobs)
        [ $# -ge 2 ] || fail "--jobs requires a number."
        JOBS="$2"
        shift 2
        ;;
      --yes|-y)
        ASSUME_YES=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --skip-geant4-install)
        SKIP_GEANT4_INSTALL=1
        shift
        ;;
      --skip-clone)
        SKIP_CLONE=1
        shift
        ;;
      --skip-patch)
        SKIP_PATCH=1
        shift
        ;;
      --skip-verify)
        SKIP_VERIFY=1
        shift
        ;;
      --skip-build)
        SKIP_BUILD=1
        shift
        ;;
      --skip-launcher)
        SKIP_LAUNCHER=1
        shift
        ;;
      --skip-import-test)
        SKIP_IMPORT_TEST=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --no-color)
        NO_COLOR=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fail "Unknown option: $1"
        ;;
    esac
  done
}

find_cc3d_python() {
  local candidates=(
    "$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python"
    "$HOME/CompuCell3D/miniconda3/envs/cc3d_env/bin/python"
    "$HOME/CompuCell3D/bin/python"
  )

  local c
  for c in "${candidates[@]}"; do
    if [ -x "$c" ]; then
      echo "$c"
      return 0
    fi
  done

  local found=""
  found="$(find "$HOME" -maxdepth 5 -type f -path "*/cc3d_env/bin/python" -executable 2>/dev/null | head -n 1 || true)"
  if [ -n "$found" ]; then
    echo "$found"
    return 0
  fi

  return 1
}

find_radcell_sources() {
  # Print RADCELL root directories, one per line. Deduplicate with awk.
  {
    # High-confidence fixed candidates first.
    printf '%s\n' \
      "$HOME/RADCELL" \
      "$HOME/radcell/RADCELL" \
      "$HOME/Desktop/RADCELL" \
      "$HOME/Desktop/Test/RADCELL" \
      "$HOME/Downloads/RADCELL" \
      "$HOME/working_on/radcell/RADCELL"

    # Conservative search. Depth 5 catches common user layouts without doing a
    # broad expensive scan of the entire home directory.
    find "$HOME" -maxdepth 5 -type d -name "RADCELL" 2>/dev/null || true
  } | awk '!seen[$0]++' | while IFS= read -r candidate; do
    if is_radcell_root "$candidate"; then
      printf '%s\n' "$candidate"
    fi
  done
}

choose_radcell_source_or_workdir() {
  # If --workdir was passed explicitly, respect it.
  if [ -n "$WORKDIR" ]; then
    WORKDIR="$(expand_path "$WORKDIR")"
    RADCELL_DIR="$WORKDIR/RADCELL"
    return
  fi

  local candidates=()
  local c=""
  while IFS= read -r c; do
    candidates+=("$c")
  done < <(find_radcell_sources)

  if [ "${#candidates[@]}" -gt 0 ]; then
    echo "Existing RADCELL source tree(s) found:"
    echo

    local i
    for i in "${!candidates[@]}"; do
      printf '  [%d] %s\n' "$((i+1))" "${candidates[$i]}"
    done

    echo "  [n] Clone/use a new RADCELL source tree"
    echo

    if [ "$ASSUME_YES" -eq 1 ]; then
      RADCELL_DIR="${candidates[0]}"
      WORKDIR="$(parent_dir "$RADCELL_DIR")"
      echo "Using first detected RADCELL source: $RADCELL_DIR"
      return
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
      RADCELL_DIR="${candidates[0]}"
      WORKDIR="$(parent_dir "$RADCELL_DIR")"
      return
    fi

    local answer=""
    while true; do
      read -r -p "Select a RADCELL source tree or choose [n] for a new one [1]: " answer
      answer="${answer:-1}"

      if [ "$answer" = "n" ] || [ "$answer" = "N" ]; then
        break
      fi

      if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#candidates[@]}" ]; then
        RADCELL_DIR="${candidates[$((answer-1))]}"
        WORKDIR="$(parent_dir "$RADCELL_DIR")"
        return
      fi

      echo "Invalid selection."
    done
  fi

  # No existing source selected. Ask for parent directory.
  WORKDIR="$(prompt_input "Where should RADCELL be cloned or found? This is the parent directory; the source will be WORKDIR/RADCELL" "$DEFAULT_WORKDIR")"
  WORKDIR="$(expand_path "$WORKDIR")"
  RADCELL_DIR="$WORKDIR/RADCELL"
}

validate_positive_int() {
  local value="$1"
  local name="$2"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 1 ]; then
    fail "$name must be a positive integer. Got: $value"
  fi
}

resolve_plan() {
  section "Resolving setup plan"

  choose_radcell_source_or_workdir

  if [ -z "$CC3D_PYTHON" ]; then
    local detected=""
    if detected="$(find_cc3d_python)"; then
      echo
      echo "Detected CompuCell3D Python:"
      echo "  $detected"
      if prompt_yes_no "Use this Python interpreter?" "yes"; then
        CC3D_PYTHON="$detected"
      fi
    fi
  fi

  if [ -z "$CC3D_PYTHON" ]; then
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
      fail "CompuCell3D Python was not provided and could not be detected. Use --cc3d-python."
    fi
    CC3D_PYTHON="$(prompt_input "Path to CompuCell3D Python" "$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python")"
    CC3D_PYTHON="$(expand_path "$CC3D_PYTHON")"
  fi

  GEANT4_PREFIX="$(expand_path "$GEANT4_PREFIX")"
  RADCELL_PREFIX="$(expand_path "$RADCELL_PREFIX")"
  LAUNCHER="$(expand_path "$LAUNCHER")"

  validate_positive_int "$JOBS" "--jobs"

  GEANT4_SH="$GEANT4_PREFIX/bin/geant4.sh"

  echo
  bold "Resolved paths"
  echo
  echo "  Work directory:     $WORKDIR"
  echo "  RADCELL source:     $RADCELL_DIR"
  echo "  RADCELL URL:        $RADCELL_URL"
  echo "  Geant4 prefix:      $GEANT4_PREFIX"
  echo "  RADCELL prefix:     $RADCELL_PREFIX"
  echo "  CompuCell3D Python: $CC3D_PYTHON"
  echo "  Launcher:           $LAUNCHER"
  echo "  Jobs:               $JOBS"
  echo "  Logs:               $LOG_DIR"
  echo

  if [ "$DRY_RUN" -eq 1 ]; then
    warn "Dry-run mode enabled. No changes will be made."
  fi

  if ! prompt_yes_no "Continue with this setup plan?" "yes"; then
    fail "Setup cancelled by user."
  fi
}

preflight_checks() {
  section "Preflight checks"

  require_command git "Install it with: sudo apt install git"
  require_command cmake "Install it with: sudo apt install cmake"
  require_command make "Install it with: sudo apt install make"
  require_command patch "Install it with: sudo apt install patch"
  require_command swig "Install it with: sudo apt install swig"

  if [ ! -x "$CC3D_PYTHON" ]; then
    fail "CompuCell3D Python not found or not executable: $CC3D_PYTHON"
  fi

  local pyver
  pyver="$("$CC3D_PYTHON" --version 2>&1 || true)"
  echo "CompuCell3D Python: $pyver"

  if [ ! -x "$REPO_DIR/scripts/apply_radcell_patch.sh" ]; then
    fail "Missing helper script: $REPO_DIR/scripts/apply_radcell_patch.sh"
  fi

  if [ ! -x "$REPO_DIR/scripts/verify_radcell_compat.sh" ]; then
    fail "Missing helper script: $REPO_DIR/scripts/verify_radcell_compat.sh"
  fi

  if [ ! -x "$REPO_DIR/scripts/build_radcell.sh" ]; then
    fail "Missing helper script: $REPO_DIR/scripts/build_radcell.sh"
  fi

  if [ ! -x "$REPO_DIR/scripts/create_radcell_launcher.sh" ]; then
    fail "Missing helper script: $REPO_DIR/scripts/create_radcell_launcher.sh"
  fi

  ok "Basic requirements look available."
}

ensure_geant4() {
  section "Checking Geant4"

  if [ -f "$GEANT4_SH" ]; then
    ok "Geant4 setup script found: $GEANT4_SH"
    return
  fi

  warn "Geant4 setup script not found: $GEANT4_SH"

  if [ "$SKIP_GEANT4_INSTALL" -eq 1 ]; then
    fail "Geant4 is missing and --skip-geant4-install was provided."
  fi

  if [ ! -x "$REPO_DIR/install_geant4_native.sh" ]; then
    fail "Geant4 is missing and installer was not found or is not executable: $REPO_DIR/install_geant4_native.sh"
  fi

  if ! prompt_yes_no "Install Geant4 now using this repository? This may take a long time." "yes"; then
    fail "Geant4 is required. Install it or pass --geant4-prefix."
  fi

  local log="$LOG_DIR/install_geant4_native.log"

  spinner_run \
    "Installing native Geant4" \
    "$log" \
    "$REPO_DIR/install_geant4_native.sh" --deb --version "11.4.2" --jobs "$JOBS"

  if [ ! -f "$GEANT4_SH" ]; then
    fail "Geant4 installation finished, but setup script still not found: $GEANT4_SH"
  fi

  ok "Geant4 installed."
}

ensure_radcell_source() {
  section "Checking RADCELL source"

  if [ -d "$RADCELL_DIR/RADCellSimulation" ]; then
    ok "RADCELL source found: $RADCELL_DIR"
    return
  fi

  if [ "$SKIP_CLONE" -eq 1 ]; then
    fail "RADCELL source was not found and --skip-clone was provided: $RADCELL_DIR"
  fi

  if ! prompt_yes_no "RADCELL source was not found. Clone it into $RADCELL_DIR?" "yes"; then
    fail "RADCELL source is required."
  fi

  if [ "$DRY_RUN" -eq 0 ]; then
    mkdir -p "$WORKDIR"
  fi

  local log="$LOG_DIR/git_clone_radcell.log"

  spinner_run \
    "Cloning RADCELL" \
    "$log" \
    git clone "$RADCELL_URL" "$RADCELL_DIR"

  if [ ! -d "$RADCELL_DIR/RADCellSimulation" ]; then
    fail "RADCELL clone completed, but expected directory was not found: $RADCELL_DIR/RADCellSimulation"
  fi

  ok "RADCELL source is ready."
}

apply_patch() {
  section "Applying RADCELL compatibility patch"

  if [ "$SKIP_PATCH" -eq 1 ]; then
    warn "Skipping patch step."
    return
  fi

  local log="$LOG_DIR/apply_radcell_patch.log"

  spinner_run \
    "Applying/checking patch" \
    "$log" \
    "$REPO_DIR/scripts/apply_radcell_patch.sh" "$RADCELL_DIR"

  ok "Patch step completed."
}

verify_radcell_compat() {
  section "Verifying RADCELL compatibility patch"

  if [ "$SKIP_VERIFY" -eq 1 ]; then
    warn "Skipping compatibility verification step."
    return
  fi

  local log="$LOG_DIR/verify_radcell_compat.log"

  spinner_run \
    "Verifying patched RADCELL source" \
    "$log" \
    "$REPO_DIR/scripts/verify_radcell_compat.sh" "$RADCELL_DIR"

  ok "Compatibility verification passed."
}

build_radcell() {
  section "Building RADCELL"

  if [ "$SKIP_BUILD" -eq 1 ]; then
    warn "Skipping build step."
    return
  fi

  local log="$LOG_DIR/build_radcell.log"

  spinner_run \
    "Building and installing RADCELL" \
    "$log" \
    env \
      GEANT4_PREFIX="$GEANT4_PREFIX" \
      RADCELL_PREFIX="$RADCELL_PREFIX" \
      JOBS="$JOBS" \
      "$REPO_DIR/scripts/build_radcell.sh" "$RADCELL_DIR" "$CC3D_PYTHON"

  if [ "$DRY_RUN" -eq 0 ]; then
    [ -f "$RADCELL_PREFIX/bin/radcell.py" ] || fail "radcell.py was not installed in $RADCELL_PREFIX/bin"
    [ -f "$RADCELL_PREFIX/bin/_radcell.so" ] || fail "_radcell.so was not installed in $RADCELL_PREFIX/bin"
  fi

  ok "RADCELL build step completed."
}

create_launcher() {
  section "Creating launcher"

  if [ "$SKIP_LAUNCHER" -eq 1 ]; then
    warn "Skipping launcher creation."
    return
  fi

  local log="$LOG_DIR/create_launcher.log"

  spinner_run \
    "Creating launcher" \
    "$log" \
    env \
      GEANT4_PREFIX="$GEANT4_PREFIX" \
      RADCELL_PREFIX="$RADCELL_PREFIX" \
      "$REPO_DIR/scripts/create_radcell_launcher.sh" "$CC3D_PYTHON" "$LAUNCHER"

  if [ "$DRY_RUN" -eq 0 ]; then
    [ -x "$LAUNCHER" ] || fail "Launcher was not created or is not executable: $LAUNCHER"
  fi

  ok "Launcher step completed."
}

test_import() {
  section "Testing RADCELL Python import"

  if [ "$SKIP_IMPORT_TEST" -eq 1 ]; then
    warn "Skipping import test."
    return
  fi

  local log="$LOG_DIR/import_radcell.log"

  spinner_run \
    "Importing radcell" \
    "$log" \
    "$LAUNCHER" -c "import radcell; print(radcell)"

  ok "RADCELL import test passed."
}

final_summary() {
  section "Setup complete"

  echo "RADCELL stack setup finished."
  echo
  echo "Important paths:"
  echo "  RADCELL source:     $RADCELL_DIR"
  echo "  RADCELL install:    $RADCELL_PREFIX"
  echo "  Geant4 prefix:      $GEANT4_PREFIX"
  echo "  CompuCell3D Python: $CC3D_PYTHON"
  echo "  Launcher:           $LAUNCHER"
  echo "  Logs:               $LOG_DIR"
  echo
  echo "Next tests:"
  echo
  echo "  $LAUNCHER -c \"import radcell; print(radcell)\""
  echo
  echo "  cd $RADCELL_DIR/VascularTumor/Simulation"
  echo "  $LAUNCHER RADCellSimulation.py \"out test_cc3d\" testInputSource"
  echo
  echo "To open the CompuCell3D GUI through the RADCELL environment:"
  echo
  echo "  cd $RADCELL_DIR"
  echo "  $LAUNCHER $HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/cc3d-player5"
  echo
}

main() {
  parse_args "$@"
  print_header
  resolve_plan
  preflight_checks
  ensure_geant4
  ensure_radcell_source
  apply_patch
  verify_radcell_compat
  build_radcell
  create_launcher
  test_import
  final_summary
}

main "$@"
