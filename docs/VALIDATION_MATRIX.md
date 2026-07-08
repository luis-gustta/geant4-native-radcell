# Validation Matrix

This document defines the validation levels used by `geant4-native-radcell`.

The repository is an installation and compatibility toolkit. These checks validate that the Geant4/RADCELL/CompuCell3D stack is installed, patched, linked, and runnable. They do not constitute a scientific validation of the original RADCELL model, the underlying radiobiology, or any specific radiation-transport experiment.

## Validation levels

| Level | Name | Purpose | Requires RADCELL? | Requires CompuCell3D? |
|---:|---|---|---:|---:|
| 0 | Repository checks | Verify scripts, patches, documentation, and CI-level shell checks. | No | No |
| 1 | Geant4 native install | Verify that Geant4 is installed, discoverable, and linkable. | No | No |
| 2 | RADCELL patch/build | Verify that a local RADCELL checkout can be patched and built. | Yes | Yes, for Python |
| 3 | Python import/runtime | Verify that the compiled RADCELL Python module loads through the launcher. | Yes | Yes |
| 4 | Direct RADCELL run | Verify that `RADCellSimulation.py` can initialize the compiled backend. | Yes | Yes |
| 5 | CompuCell3D headless smoke test | Verify that the patched `VascularTumor` workflow can start through `cc3d.run_script`. | Yes | Yes |
| 6 | CompuCell3D GUI launch | Verify that the GUI can be opened through the RADCELL launcher. | Yes | Yes |

## Matrix

| Check | Level | Command | Expected result | Output / evidence |
|---|---:|---|---|---|
| Repository shell checks | 0 | CI or local `shellcheck scripts/*.sh install_geant4_native.sh` | No shellcheck failure in maintained scripts. | CI log or local terminal output. |
| Geant4 environment script | 1 | `source /opt/geant4/11.4.2/bin/geant4.sh` | Shell environment loads without error. | Terminal output. |
| Geant4 version | 1 | `geant4-config --version` | `11.4.2` | Terminal output. |
| Geant4 prefix | 1 | `geant4-config --prefix` | `/opt/geant4/11.4.2` | Terminal output. |
| Geant4 datasets | 1 | `env | grep '^G4.*DATA'` | Dataset variables are defined after sourcing the dataset profile script. | Terminal output. |
| Geant4 shared libraries | 1 | `find /opt/geant4/11.4.2/lib -name "*.so" -exec ldd {} \; | grep "not found"` | No output. | Terminal output. |
| Geant4 B1 example | 1 | Build and run `/opt/geant4/11.4.2/share/Geant4/examples/basic/B1` | Example builds and runs a macro without missing-library errors. | Build/run log. |
| Patch application | 2 | `./scripts/apply_radcell_patch.sh /path/to/RADCELL` | Patch applies cleanly or is detected as already applied. | Script output. |
| Patch verification | 2 | `./scripts/verify_radcell_compat.sh /path/to/RADCELL` | Required compatibility markers are present; obsolete patterns are absent. | Script output. |
| RADCELL build | 2 | `./scripts/build_radcell.sh /path/to/RADCELL /path/to/cc3d_env/bin/python` | Build and install complete. | CMake/make log. |
| Launcher creation | 3 | `./scripts/create_radcell_launcher.sh /path/to/cc3d_env/bin/python` | `~/run_radcell_cc3d_python.sh` is created and executable. | File exists and is executable. |
| RADCELL Python import | 3 | `~/run_radcell_cc3d_python.sh -c "import radcell; print(radcell)"` | Python prints the loaded `radcell` module path. | Terminal output. |
| Direct `RADCellSimulation.py` run | 4 | `cd /path/to/RADCELL/VascularTumor/Simulation && ~/run_radcell_cc3d_python.sh RADCellSimulation.py "out test_cc3d" testInputSource` | The script starts, reads cell information, and initializes the Geant4/RADCELL backend. | Terminal output and generated RADCELL files. |
| Headless `VascularTumor` smoke test | 5 | `scripts/run_vasculartumor_headless.sh --radcell-dir /path/to/RADCELL --launcher ~/run_radcell_cc3d_python.sh` | A timestamped run directory is created under `$PWD/radcell_runs/`; `cc3d_headless.log` and `run_manifest.json` are written. | Run directory. |
| GUI launch through launcher | 6 | `~/run_radcell_cc3d_python.sh /path/to/cc3d-player5` | CompuCell3D Player starts with the same runtime environment used for RADCELL. | GUI session and terminal output. |

## Smoke-test interpretation

A short headless `VascularTumor` smoke test may initialize CompuCell3D without reaching a RADCELL radiation step before the timeout. This is acceptable for a short runtime check if the objective is only to verify that CompuCell3D starts correctly through the launcher.

To test the RADCELL/Geant4 call path, either increase the timeout or use a controlled local modification that triggers radiation earlier in the simulation schedule.

## Failure classification

| Symptom | Likely class | First diagnostic command |
|---|---|---|
| `geant4-config: command not found` | Geant4 environment not loaded or Geant4 not installed. | `ls /opt/geant4/11.4.2/bin/geant4.sh` |
| `ModuleNotFoundError: No module named 'radcell'` | RADCELL Python module not installed or launcher not used. | `~/run_radcell_cc3d_python.sh -c "import sys; print(sys.path)"` |
| `_radcell.so: cannot open shared object file` | Runtime library path problem. | `~/run_radcell_cc3d_python.sh -c "import radcell"` |
| `cannot allocate memory in static TLS block` | Geant4/RADCELL preload problem. | Inspect `LD_PRELOAD` inside the launcher. |
| `/vis/open OGL` or `vis.mac` errors | Old or incompletely patched RADCELL checkout. | `./scripts/verify_radcell_compat.sh /path/to/RADCELL` |
| CompuCell3D starts but RADCELL is not reached | Radiation is scheduled at a later MCS or timeout is too short. | Increase `--timeout` or inspect the radiation schedule. |

## Reporting a validation result

When reporting a validation result, include:

- operating system and version;
- Geant4 version and prefix;
- CompuCell3D version and Python path;
- RADCELL checkout path and commit if known;
- `geant4-native-radcell` commit/tag;
- exact command executed;
- relevant log file;
- whether the failure occurred during install, patch, build, import, direct run, headless run, or GUI launch.
