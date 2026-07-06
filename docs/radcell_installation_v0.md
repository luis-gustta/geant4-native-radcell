# RADCELL Installation Manual v0

This document describes an initial installation workflow for running RADCELL with a native Geant4 installation, CompuCell3D, and a compatibility patch maintained in this repository.

The goal is to support the following workflow:

```text
CompuCell3D Player
    -> VascularTumor.cc3d
    -> RADCellSimulation.py
    -> compiled RADCELL / Geant4 backend
```

In this setup, the Geant4/RADCELL backend runs without its own Geant4 Qt/OpenGL visualization window. This does not prevent using the CompuCell3D graphical interface.

## Scope

This guide covers:

1. Installing system dependencies.
2. Installing CompuCell3D.
3. Installing native Geant4 using this repository.
4. Cloning the original RADCELL source code.
5. Applying the RADCELL compatibility patch.
6. Building and installing RADCELL.
7. Creating the RADCELL launcher.
8. Testing the RADCELL Python module.
9. Running `RADCellSimulation.py` directly.
10. Opening `VascularTumor.cc3d` in the CompuCell3D Player.

## Expected layout

The default paths used by this guide are:

- Geant4: `/opt/geant4/11.4.2`
- RADCELL source: `~/working_on/radcell/RADCELL`
- RADCELL install prefix: `~/.local/radcell`
- CompuCell3D: `~/CompuCell3D`
- CompuCell3D Python: `~/CompuCell3D/miniforge3/envs/cc3d_env/bin/python`
- RADCELL launcher: `~/run_radcell_cc3d_python.sh`

Other paths can be used, but the commands must be adjusted accordingly.

---

## 1. Install system dependencies

Install basic build tools:

```bash
sudo apt update
sudo apt install -y \
  git \
  build-essential \
  cmake \
  ninja-build \
  make \
  gcc \
  g++ \
  swig \
  python3 \
  python3-venv \
  python3-pip \
  wget \
  curl \
  ca-certificates \
  pkg-config
```

Install libraries commonly required by the native Geant4 build:

```bash
sudo apt install -y \
  libxerces-c-dev \
  libcurl4-openssl-dev \
  libssl-dev \
  libglu1-mesa \
  qt6-base-dev \
  libqt6opengl6-dev \
  libexpat1-dev \
  zlib1g-dev \
  libfreetype-dev \
  libx11-dev \
  libxext-dev \
  libxmu-dev \
  libxi-dev
```

Check that the main tools are available:

```bash
gcc --version
g++ --version
cmake --version
swig -version
```

RADCELL requires SWIG to build the Python wrapper. If SWIG is missing, the RADCELL build will fail during CMake configuration.

---

## 2. Install CompuCell3D

Install CompuCell3D before building RADCELL, because RADCELL must be compiled against the Python interpreter used by CompuCell3D.

After installing CompuCell3D, verify that the expected Python interpreter exists:

```bash
ls ~/CompuCell3D/miniforge3/envs/cc3d_env/bin/python
```

Check its version:

```bash
~/CompuCell3D/miniforge3/envs/cc3d_env/bin/python --version
```

If CompuCell3D is installed elsewhere, note the full path to its Python interpreter. It will be passed explicitly to the build and launcher scripts.

---

## 3. Install native Geant4

Clone this repository:

```bash
git clone https://github.com/luis-gustta/geant4-native-radcell.git
cd geant4-native-radcell
```

Run the native Geant4 installer:

```bash
chmod +x ./install_geant4_native.sh
./install_geant4_native.sh
```

After installation, verify:

```bash
source /opt/geant4/11.4.2/bin/geant4.sh
geant4-config --version
```

Expected version:

```text
11.4.2
```

Check that core Geant4 libraries exist:

```bash
ls /opt/geant4/11.4.2/lib/libG4run.so
ls /opt/geant4/11.4.2/lib/libG4geometry.so
ls /opt/geant4/11.4.2/lib/libG4global.so
```

---

## 4. Clone RADCELL

Choose a working directory:

```bash
mkdir -p ~/working_on/radcell
cd ~/working_on/radcell
```

Clone the original RADCELL repository:

```bash
git clone https://github.com/forgetsummer/RADCELL.git
```

Check the expected layout:

```bash
ls RADCELL
ls RADCELL/RADCellSimulation
ls RADCELL/VascularTumor
```

The expected directories are:

```text
RADCELL/RADCellSimulation
RADCELL/VascularTumor
```

---

## 5. Apply the compatibility patch

From inside the `geant4-native-radcell` repository:

```bash
cd ~/working_on/radcell/geant4-native-radcell
```

If this repository is elsewhere, use the correct path.

Apply the patch:

```bash
./scripts/apply_radcell_patch.sh ~/working_on/radcell/RADCELL
```

Expected successful output:

```text
[RADCELL] Patch applied successfully.
```

If the patch was already applied, the script may report:

```text
[RADCELL] Patch is already applied.
[RADCELL] Nothing to do.
```

That is also acceptable.

---

## 6. Build and install RADCELL

From inside the `geant4-native-radcell` repository:

```bash
./scripts/build_radcell.sh ~/working_on/radcell/RADCELL
```

If CompuCell3D Python is not at the default location, pass it explicitly:

```bash
./scripts/build_radcell.sh \
  ~/working_on/radcell/RADCELL \
  /path/to/CompuCell3D/miniforge3/envs/cc3d_env/bin/python
```

By default, RADCELL is installed into:

```text
~/.local/radcell
```

Check the installed files:

```bash
ls ~/.local/radcell/bin
```

Expected files:

```text
libradcelllib.so
_radcell.so
radcell.py
test
```

---

## 7. Create the RADCELL launcher

Create the launcher:

```bash
./scripts/create_radcell_launcher.sh
```

If CompuCell3D Python is not at the default location:

```bash
./scripts/create_radcell_launcher.sh \
  /path/to/CompuCell3D/miniforge3/envs/cc3d_env/bin/python
```

Expected output:

```text
[RADCELL] Launcher created:
  /home/USER/run_radcell_cc3d_python.sh
```

The launcher sets the RADCELL and Geant4 environment only for the process it launches. It should not modify global shell or system configuration such as:

```text
~/.bashrc
~/.profile
/etc/environment
/etc/ld.so.preload
```

---

## 8. Test the RADCELL Python module

Run:

```bash
~/run_radcell_cc3d_python.sh -c "import radcell; print(radcell)"
```

Expected output:

```text
<module 'radcell' from '/home/USER/.local/radcell/bin/radcell.py'>
```

If this fails, check:

```bash
ls ~/.local/radcell/bin
echo "${PYTHONPATH:-}"
echo "${LD_LIBRARY_PATH:-}"
echo "${LD_PRELOAD:-}"
```

`LD_PRELOAD` does not need to be globally set in the shell. It is set only inside the launcher command.

---

## 9. Test `RADCellSimulation.py` directly

Go to the VascularTumor simulation directory:

```bash
cd ~/working_on/radcell/RADCELL/VascularTumor/Simulation
```

Run:

```bash
~/run_radcell_cc3d_python.sh RADCellSimulation.py \
  "out test_cc3d" \
  testInputSource
```

Expected signs of success:

```text
Start calling subprocess RADCellSimulation here
cellInformation exists: True
Loaded cells: ...
Geant4 version Name: geant4-11-04...
runMode: out test_cc3d
radiationSource: testInputSource.in
```

Warnings about Geant4 production cuts may appear and are not necessarily fatal.

---

## 10. Run with the CompuCell3D GUI

Start the CompuCell3D Player through the launcher:

```bash
cd ~/working_on/radcell/RADCELL

~/run_radcell_cc3d_python.sh \
  ~/CompuCell3D/miniforge3/envs/cc3d_env/bin/cc3d-player5
```

Inside the CompuCell3D Player, open:

```text
~/working_on/radcell/RADCELL/VascularTumor/VascularTumor.cc3d
```

Press **Run**.

When the simulation reaches a radiation step, the terminal should show RADCELL being called.

The original VascularTumor schedule may call RADCELL at high MCS values such as:

```text
12000, 13000, 14000, 15000, 16000
```

For a short test, the simulation may need to be adjusted to call RADCELL earlier, for example at MCS 10.

---

## 11. Run with CompuCell3D headless

For server or SSH use:

```bash
~/run_radcell_cc3d_python.sh -m cc3d.run_script \
  -i ~/working_on/radcell/RADCELL/VascularTumor/VascularTumor.cc3d \
  --output-dir ~/radcell_cc3d_outputs/VascularTumor_test
```

Use an output directory outside the simulation directory.

---

## 12. Troubleshooting

### `Could NOT find SWIG`

Install SWIG:

```bash
sudo apt install -y swig
```

### `PyString_FromString was not declared`

The RADCELL compatibility patch was not applied.

Run:

```bash
./scripts/apply_radcell_patch.sh /path/to/RADCELL
```

### `G4MTRunManager does not name a type`

The RADCELL compatibility patch was not applied, or the source is partially patched.

Check:

```bash
grep -RIn "G4MTRunManager" /path/to/RADCELL/RADCellSimulation
```

### `g4root.hh: No such file or directory`

The RADCELL compatibility patch was not applied.

Check:

```bash
grep -RIn "g4root.hh" /path/to/RADCELL/RADCellSimulation
```

### `theParticleIterator was not declared`

The RADCELL compatibility patch was not applied.

Check:

```bash
grep -RIn "theParticleIterator" /path/to/RADCELL/RADCellSimulation/src/PhysicsList.cc
```

### `cannot find -lG4run` or another `-lG4...`

The linker is not finding the Geant4 library path.

Check:

```bash
ls /opt/geant4/11.4.2/lib/libG4run.so
```

If the file exists, build with:

```bash
export LIBRARY_PATH=/opt/geant4/11.4.2/lib:$LIBRARY_PATH
./scripts/build_radcell.sh /path/to/RADCELL
```

### `qdialog.h: No such file or directory`

RADCELL is trying to build with Geant4 Qt UI support.

The build should use:

```bash
-DWITH_GEANT4_UIVIS=OFF
```

The provided build script already does this.

### Global `LD_PRELOAD` problems

Do not globally export Geant4 libraries with `LD_PRELOAD`.

Check:

```bash
echo "${LD_PRELOAD:-}"
env | grep LD_PRELOAD
cat /etc/ld.so.preload 2>/dev/null
```

The launcher sets `LD_PRELOAD` only for the process it launches.

---

## 13. Clean rebuild

To rebuild RADCELL from scratch:

```bash
cd /path/to/RADCELL/RADCellSimulation
rm -rf build
```

Then run from this repository:

```bash
./scripts/build_radcell.sh /path/to/RADCELL
```

---

## 14. Minimal command summary

```bash
# Install Geant4 from this repository
./install_geant4_native.sh

# Clone RADCELL
git clone https://github.com/forgetsummer/RADCELL.git

# Patch RADCELL
./scripts/apply_radcell_patch.sh /path/to/RADCELL

# Build RADCELL
./scripts/build_radcell.sh /path/to/RADCELL

# Create launcher
./scripts/create_radcell_launcher.sh

# Test
~/run_radcell_cc3d_python.sh -c "import radcell; print(radcell)"
```
