#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage:"
  echo "  $0 /path/to/RADCELL [/path/to/cc3d_python]"
  echo
  echo "Environment variables:"
  echo "  GEANT4_PREFIX    Default: /opt/geant4/11.4.2"
  echo "  RADCELL_PREFIX   Default: \$HOME/.local/radcell"
  echo "  JOBS             Default: nproc"
  exit 1
fi

RADCELL_DIR="$1"
GEANT4_PREFIX="${GEANT4_PREFIX:-/opt/geant4/11.4.2}"
RADCELL_PREFIX="${RADCELL_PREFIX:-$HOME/.local/radcell}"
JOBS="${JOBS:-$(nproc)}"

if [ $# -eq 2 ]; then
  PYTHON_BIN="$2"
else
  PYTHON_BIN="${CC3D_PYTHON:-$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python}"
fi

RADSIM_DIR="$RADCELL_DIR/RADCellSimulation"
GEANT4_SH="$GEANT4_PREFIX/bin/geant4.sh"
G4LIB="$GEANT4_PREFIX/lib"

if [ ! -d "$RADCELL_DIR" ]; then
  echo "ERROR: RADCELL directory does not exist:"
  echo "  $RADCELL_DIR"
  exit 1
fi

if [ ! -d "$RADSIM_DIR" ]; then
  echo "ERROR: This does not look like a RADCELL root directory:"
  echo "  $RADCELL_DIR"
  echo
  echo "Expected:"
  echo "  $RADSIM_DIR"
  exit 1
fi

if [ ! -f "$GEANT4_SH" ]; then
  echo "ERROR: Geant4 setup script not found:"
  echo "  $GEANT4_SH"
  echo
  echo "Set GEANT4_PREFIX if Geant4 is installed elsewhere."
  exit 1
fi

if [ ! -x "$PYTHON_BIN" ]; then
  echo "ERROR: Python interpreter not found or not executable:"
  echo "  $PYTHON_BIN"
  echo
  echo "Pass the CompuCell3D Python explicitly:"
  echo "  $0 /path/to/RADCELL /path/to/cc3d_env/bin/python"
  exit 1
fi

echo "[RADCELL] Source:"
echo "  $RADCELL_DIR"
echo "[RADCELL] Build dir:"
echo "  $RADSIM_DIR/build"
echo "[RADCELL] Install prefix:"
echo "  $RADCELL_PREFIX"
echo "[Geant4] Prefix:"
echo "  $GEANT4_PREFIX"
echo "[Python] Interpreter:"
echo "  $PYTHON_BIN"
echo "[Build] Jobs:"
echo "  $JOBS"
echo

source "$GEANT4_SH"

PY_INC="$("$PYTHON_BIN" -c 'import sysconfig; print(sysconfig.get_paths()["include"])')"

if [ -f "$(dirname "$PYTHON_BIN")/../lib/libpython3.12.so" ]; then
  PY_LIB="$(cd "$(dirname "$PYTHON_BIN")/../lib" && pwd)/libpython3.12.so"
else
  PY_LIB="$("$PYTHON_BIN" -c 'import sysconfig, pathlib; print(pathlib.Path(sysconfig.get_config_var("LIBDIR")) / sysconfig.get_config_var("LDLIBRARY"))')"
fi

if [ ! -d "$PY_INC" ]; then
  echo "ERROR: Python include directory not found:"
  echo "  $PY_INC"
  exit 1
fi

if [ ! -f "$PY_LIB" ]; then
  echo "ERROR: Python library not found:"
  echo "  $PY_LIB"
  exit 1
fi

echo "[Python] Include:"
echo "  $PY_INC"
echo "[Python] Library:"
echo "  $PY_LIB"
echo

export LIBRARY_PATH="$G4LIB:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="$RADCELL_PREFIX/bin:$G4LIB:${LD_LIBRARY_PATH:-}"

cd "$RADSIM_DIR"

rm -rf build
mkdir build
cd build

cmake .. \
  -DCMAKE_INSTALL_PREFIX="$RADCELL_PREFIX" \
  -DWITH_GEANT4_UIVIS=OFF \
  -DPYTHON_EXECUTABLE="$PYTHON_BIN" \
  -DPYTHON_INCLUDE_DIR="$PY_INC" \
  -DPYTHON_LIBRARY="$PY_LIB"

make -j"$JOBS"
make install

echo
echo "[RADCELL] Build and installation completed."
echo
echo "Installed files:"
echo "  $RADCELL_PREFIX/bin/libradcelllib.so"
echo "  $RADCELL_PREFIX/bin/_radcell.so"
echo "  $RADCELL_PREFIX/bin/radcell.py"
echo
echo "Next test:"
echo "  export RADCELL_PREFIX=\"$RADCELL_PREFIX\""
echo "  export G4LIB=\"$G4LIB\""
echo "  source \"$GEANT4_SH\""
echo "  export PYTHONPATH=\"\$RADCELL_PREFIX/bin:\$PYTHONPATH\""
echo "  export LD_LIBRARY_PATH=\"\$RADCELL_PREFIX/bin:\$G4LIB:\$LD_LIBRARY_PATH\""
echo "  $PYTHON_BIN -c \"import radcell; print(radcell)\""
