# RADCELL First Run Guide

This guide explains how to verify that a RADCELL installation is actually usable after completing the installation workflow.

It assumes that the setup was completed with either:

```bash
./scripts/setup_radcell_stack.sh
```

or the manual/debug path:

```bash
./scripts/apply_radcell_patch.sh /path/to/RADCELL
./scripts/build_radcell.sh /path/to/RADCELL
./scripts/create_radcell_launcher.sh
```

The purpose is not to validate the full biological or radiation model. The purpose is to confirm that:

- the compiled RADCELL Python module can be imported;
- the Geant4 runtime environment is available;
- `RADCellSimulation.py` can run directly;
- the CompuCell3D Player can be launched with the RADCELL environment;
- the `VascularTumor.cc3d` example can call RADCELL at a radiation step.

---

## 1. Expected paths

The default setup uses:

```text
Geant4:       /opt/geant4/11.4.2
RADCELL:      ~/radcell/RADCELL
RADCELL lib:  ~/.local/radcell/bin
Launcher:     ~/run_radcell_cc3d_python.sh
CompuCell3D:  ~/CompuCell3D
```

If your RADCELL source tree is somewhere else, adjust the commands below.

For convenience, define:

```bash
export RADCELL_ROOT="$HOME/radcell/RADCELL"
export RADCELL_LAUNCHER="$HOME/run_radcell_cc3d_python.sh"
export CC3D_PLAYER="$HOME/CompuCell3D/miniforge3/envs/cc3d_env/bin/cc3d-player5"
```

For example, if your RADCELL source is in `/home/luis/Desktop/Test/RADCELL`, use:

```bash
export RADCELL_ROOT="/home/luis/Desktop/Test/RADCELL"
```

---

## 2. Test the launcher and Python import

Run:

```bash
"$RADCELL_LAUNCHER" -c "import radcell; print(radcell)"
```

Expected output:

```text
<module 'radcell' from '/home/USER/.local/radcell/bin/radcell.py'>
```

This confirms that:

- the CompuCell3D Python interpreter can see `radcell.py`;
- `_radcell.so` can be loaded;
- the Geant4 runtime libraries are available through the launcher.

If this fails, first check that the installed files exist:

```bash
ls -lh ~/.local/radcell/bin
```

Expected files:

```text
libradcelllib.so
_radcell.so
radcell.py
test
```

Common failures:

| Symptom | Likely cause |
|---|---|
| `ModuleNotFoundError: No module named 'radcell'` | `PYTHONPATH` is not being set by the launcher, or RADCELL was not installed. |
| `_radcell.so: cannot open shared object file` | `LD_LIBRARY_PATH` is missing the RADCELL install directory. |
| Geant4 library import errors | The launcher is not loading the Geant4 runtime correctly. |
| TLS / preload-related errors | RADCELL should be run through the launcher, not by globally setting `LD_PRELOAD`. |

---

## 3. Check that the launcher does not rely on global `LD_PRELOAD`

The launcher may set `LD_PRELOAD` internally for the process it starts. This should not be global.

Check the current shell:

```bash
echo "${LD_PRELOAD:-}"
env | grep LD_PRELOAD
```

The ideal result is no global `LD_PRELOAD`.

Do not add Geant4 or RADCELL preload settings to:

```text
~/.bashrc
~/.profile
/etc/environment
/etc/ld.so.preload
```

Use the launcher instead:

```bash
~/run_radcell_cc3d_python.sh <command>
```

---

## 4. Test `RADCellSimulation.py` directly

Go to the VascularTumor simulation directory:

```bash
cd "$RADCELL_ROOT/VascularTumor/Simulation"
```

Check that the expected files exist:

```bash
ls RADCellSimulation.py
ls testInputSource.in
ls cellInformation.csv
```

Then run:

```bash
"$RADCELL_LAUNCHER" RADCellSimulation.py \
  "out test_cc3d" \
  testInputSource
```

Expected signs of success include lines similar to:

```text
Start calling subprocess RADCellSimulation here
cellInformation exists: True
Loaded cells: ...
Tissue dimensions [mm]: ...
Geant4 version Name: geant4-11-04...
runMode: out test_cc3d
radiationSource: testInputSource.in
```

The exact number of loaded cells depends on the current `cellInformation.csv`.

---

## 5. Warnings and errors

Some Geant4 warnings may appear during the direct test.

For example:

```text
G4Exception : ProcCuts110
Setting cuts for particles other than photon, e-, e+ or proton has no effect.
This is just a warning message.
```

This warning is usually not fatal.

However, with the modern `v0.4.1+` compatibility workflow, visualization-related messages such as:

```text
COMMAND NOT FOUND </vis/open OGL 600x400-0+0>
```

or:

```text
Can not open a macro file <vis.mac>
```

should be treated as signs of an old or incomplete compatibility patch.

The Geant4/RADCELL backend is expected to run headlessly. CompuCell3D may still use its own GUI, but RADCELL should not try to open a separate Geant4 Qt/OpenGL window during the headless backend call.

Fatal errors usually include:

- Python traceback;
- segmentation fault;
- missing `_radcell.so`;
- missing Geant4 libraries;
- missing input source file;
- failure to read `cellInformation.csv`;
- process exits before printing `runMode`;
- old Geant4 visualization/OpenGL errors in a `v0.4.1+` workflow.


---

## 6. Launch the CompuCell3D Player through the RADCELL environment

Start the Player through the launcher:

```bash
cd "$RADCELL_ROOT"

"$RADCELL_LAUNCHER" "$CC3D_PLAYER"
```

Inside the CompuCell3D Player, open:

```text
VascularTumor/VascularTumor.cc3d
```

Then press **Run**.

The terminal should show CompuCell3D starting the simulation.

Expected early signs:

```text
CompuCell3D Version: ...
Selected simulation file: .../VascularTumor.cc3d
XML is valid!
INFO: Random number generator: MersenneTwister
INFO: Step 0
INFO: Cells ...
```

---

## 7. Radiation schedule caveat

The original `VascularTumor` example may call RADCELL only at high MCS values, for example:

```text
12000, 13000, 14000, 15000, 16000
```

This means that the CompuCell3D GUI may appear to run normally for a long time before RADCELL is called.

For a short test, temporarily adjust the radiation schedule in the simulation steppables so that RADCELL is called earlier, for example at MCS 10.

Before editing, make a backup:

```bash
cd "$RADCELL_ROOT/VascularTumor/Simulation"
cp VascularTumorSteppables.py VascularTumorSteppables.py.before_short_test
```

Then edit the condition that triggers RADCELL and temporarily replace the high-MCS schedule with a short-test trigger such as:

```python
if mcs == 10:
```

After the test, restore the original file:

```bash
mv VascularTumorSteppables.py.before_short_test VascularTumorSteppables.py
```

Do not commit this short-test change to a clean RADCELL source unless it is explicitly documented as a test variant.

---

## 8. Expected terminal output when CompuCell3D calls RADCELL

When the CompuCell3D simulation reaches a radiation step, the terminal should show RADCELL being called from the simulation directory.

Expected signs:

```text
the runMode is: out single_MRT_8Gy_5_hyperfraction
[RADCELL] running: /home/USER/run_radcell_cc3d_python.sh RADCellSimulation.py out single_MRT_8Gy_5_hyperfraction testInputSource
Start calling subprocess RADCellSimulation here
cellInformation exists: True
Loaded cells: ...
Tissue dimensions [mm]: ...
Before starting radiation energy deposition calculation
Geant4 version Name: geant4-11-04...
runMode: out single_MRT_8Gy_5_hyperfraction
radiationSource: testInputSource.in
```

This confirms that:

- CompuCell3D is running;
- the steppable reached a radiation step;
- `RADCellSimulation.py` was launched;
- RADCELL read `cellInformation.csv`;
- Geant4 initialized.

---

## 9. Recommended headless CompuCell3D smoke test

For SSH, tmux, or non-GUI runs, prefer the repository helper script:

```bash
mkdir -p ~/Desktop/simulacoes
cd ~/Desktop/simulacoes

/path/to/geant4-native-radcell/scripts/run_vasculartumor_headless.sh \
  --radcell-dir "$RADCELL_ROOT" \
  --launcher "$RADCELL_LAUNCHER"
```

By default, the script writes outputs under the directory where it was called:

```text
$PWD/radcell_runs/VascularTumor_cc3d_YYYY_MM_DD_HH_MM_SS_<id>/
```

Each run directory contains at least:

```text
VascularTumor.cc3d
cc3d_headless.log
run_manifest.json
```

This keeps simulation outputs out of the `geant4-native-radcell` repository and out of the RADCELL source tree.

The script validates that CompuCell3D starts correctly. If the timeout is reached before the radiation step, the smoke test can still pass as long as CompuCell3D initialized successfully and no old Geant4 visualization/OpenGL error was found.

If you specifically want to observe the RADCELL/Geant4 call from the full `VascularTumor` workflow, increase the timeout:

```bash
/path/to/geant4-native-radcell/scripts/run_vasculartumor_headless.sh \
  --radcell-dir "$RADCELL_ROOT" \
  --launcher "$RADCELL_LAUNCHER" \
  --timeout 300
```

Manual equivalent:

```bash
"$RADCELL_LAUNCHER" -m cc3d.run_script \
  -i "$RADCELL_ROOT/VascularTumor/VascularTumor.cc3d" \
  --output-dir "$PWD/radcell_runs/VascularTumor_manual_test"
```

If this command starts but never reaches RADCELL, check the radiation schedule. The simulation may not have reached the required MCS yet.


---

## 10. Where to look for outputs

RADCELL and the VascularTumor example may write outputs inside:

```text
RADCELL/VascularTumor/Simulation/
```

or inside directories named by the run mode, depending on the specific script behavior.

Useful inspection commands:

```bash
cd "$RADCELL_ROOT/VascularTumor/Simulation"

find . -maxdepth 3 -type f -name "*.csv" -printf "%TY-%Tm-%Td %TH:%TM  %p\n" | sort
find . -maxdepth 3 -type f -printf "%TY-%Tm-%Td %TH:%TM  %p\n" | sort | tail -50
```

At minimum, the direct run should show that RADCELL can read:

```text
cellInformation.csv
testInputSource.in
```

The exact output files depend on the run mode and the RADCELL scripts being used.

---

## 11. Minimal success checklist

A first successful setup should satisfy:

```text
[ ] ~/run_radcell_cc3d_python.sh exists and is executable.
[ ] ~/.local/radcell/bin/radcell.py exists.
[ ] ~/.local/radcell/bin/_radcell.so exists.
[ ] The launcher can import radcell.
[ ] RADCellSimulation.py starts directly from VascularTumor/Simulation.
[ ] Geant4 prints its version during the direct test.
[ ] CompuCell3D Player opens through the launcher.
[ ] VascularTumor.cc3d starts in CompuCell3D.
[ ] At a radiation step, CompuCell3D calls RADCellSimulation.py.
```

---

## 12. Common next actions

After confirming the first run:

1. Restore any temporary short-test schedule changes.
2. Run the original VascularTumor schedule.
3. Save terminal logs from a successful run.
4. Record the exact Geant4, CompuCell3D, Python, and RADCELL paths.
5. If preparing documentation, include both:
   - a direct `RADCellSimulation.py` test;
   - a CompuCell3D GUI test.
