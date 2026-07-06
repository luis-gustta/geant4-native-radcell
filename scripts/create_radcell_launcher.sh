#!/usr/bin/env bash
set -euo pipefail

GEANT4_PREFIX="${GEANT4_PREFIX:-/opt/geant4/11.4.2}"
RADCELL_PREFIX="${RADCELL_PREFIX:-$HOME/.local/radcell}"

if [ $# -ge 1 ]; then
  PYTHON_BIN="$1"
else
  PYTHON_BIN="${CC3D_PYTHON:-$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/python}"
fi

if [ $# -ge 2 ]; then
  OUT="$2"
else
  OUT="$HOME/run_radcell_cc3d_python.sh"
fi

GEANT4_SH="$GEANT4_PREFIX/bin/geant4.sh"
G4LIB="$GEANT4_PREFIX/lib"

if [ ! -f "$GEANT4_SH" ]; then
  echo "ERROR: Geant4 setup script not found:"
  echo "  $GEANT4_SH"
  echo
  echo "Set GEANT4_PREFIX if Geant4 is installed elsewhere."
  exit 1
fi

if [ ! -x "$PYTHON_BIN" ]; then
  echo "ERROR: CompuCell3D Python not found or not executable:"
  echo "  $PYTHON_BIN"
  echo
  echo "Pass it explicitly:"
  echo "  $0 /path/to/cc3d_env/bin/python"
  exit 1
fi

if [ ! -d "$RADCELL_PREFIX/bin" ]; then
  echo "ERROR: RADCELL installation not found:"
  echo "  $RADCELL_PREFIX/bin"
  echo
  echo "Build RADCELL first, or set RADCELL_PREFIX."
  exit 1
fi

if [ ! -f "$RADCELL_PREFIX/bin/radcell.py" ]; then
  echo "ERROR: radcell.py not found:"
  echo "  $RADCELL_PREFIX/bin/radcell.py"
  exit 1
fi

if [ ! -f "$RADCELL_PREFIX/bin/_radcell.so" ]; then
  echo "ERROR: _radcell.so not found:"
  echo "  $RADCELL_PREFIX/bin/_radcell.so"
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export RADCELL_PREFIX="$RADCELL_PREFIX"
export GEANT4_PREFIX="$GEANT4_PREFIX"
export G4LIB="$G4LIB"

source "$GEANT4_SH"

export PYTHONPATH="\$RADCELL_PREFIX/bin:\${PYTHONPATH:-}"
export LD_LIBRARY_PATH="\$RADCELL_PREFIX/bin:\$G4LIB:\${LD_LIBRARY_PATH:-}"

export RADCELL_LAUNCHER="\${RADCELL_LAUNCHER:-$OUT}"

export G4_PRELOAD=\$(find "\$G4LIB" -maxdepth 1 -name "libG4*.so" | sort | tr '\n' ':' | sed 's/:$//')

LD_PRELOAD="\$G4_PRELOAD\${LD_PRELOAD:+:\$LD_PRELOAD}" \\
exec "$PYTHON_BIN" "\$@"
EOF

chmod +x "$OUT"

echo "[RADCELL] Launcher created:"
echo "  $OUT"
echo
echo "Using:"
echo "  Geant4:       $GEANT4_PREFIX"
echo "  RADCELL:      $RADCELL_PREFIX"
echo "  CC3D Python:  $PYTHON_BIN"
echo
echo "Test with:"
echo "  $OUT -c \"import radcell; print(radcell)\""
