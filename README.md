# Geant4 Native Installer and RADCELL Compatibility Toolkit

This repository provides a native Linux installer and Debian package builder for Geant4, plus a compatibility toolkit for building the original RADCELL project against a modern Geant4 and CompuCell3D stack.

The immediate motivation is practical: RADCELL depends on Geant4, but its upstream repository gives only high-level installation guidance. This project supplies the missing installation and compatibility layer needed to reproduce RADCELL workflows on a controlled native Linux environment without Spack.

## Main goals

- Install Geant4 natively under `/opt/geant4/<version>`.
- Optionally build a `.deb` package for reuse on similar Linux systems.
- Provide a compatibility patch for building RADCELL with:
  - Geant4 11.4.2;
  - Python 3.12;
  - the Python environment used by CompuCell3D;
  - Geant4/RADCELL running without its own Qt/OpenGL visualization window.
- Provide helper scripts for:
  - automated RADCELL stack setup;
  - applying the RADCELL compatibility patch;
  - building and installing RADCELL;
  - creating a launcher for RADCELL + CompuCell3D workflows.

The intended runtime model is:

```text
CompuCell3D Player
    -> VascularTumor.cc3d
    -> RADCellSimulation.py
    -> compiled RADCELL / Geant4 backend
```

The Geant4/RADCELL backend is built without its own Geant4 Qt/OpenGL visualization window. This does **not** prevent using the CompuCell3D graphical interface.

## Recommended setup

For most users, the recommended entry point is the interactive setup orchestrator:

```bash
./scripts/setup_radcell_stack.sh
```

The script will:

- search for an existing local `RADCELL` source tree;
- offer to clone RADCELL if it is not found;
- detect the CompuCell3D Python interpreter when possible;
- check for Geant4;
- apply the compatibility patch;
- build and install RADCELL;
- create the runtime launcher;
- test `import radcell`;
- save logs under `/tmp/radcell-stack-setup/<timestamp>/`.

For non-interactive setup:

```bash
./scripts/setup_radcell_stack.sh \
  --workdir ~/radcell \
  --cc3d-python ~/CompuCell3D/miniforge3/envs/cc3d_env/bin/python \
  --yes
```

`--workdir` is the parent directory where the original RADCELL repository will be cloned or found. With `--workdir ~/radcell`, the script expects or creates:

```text
~/radcell/RADCELL
```

## Manual/debug setup

The individual scripts are still available for debugging or controlled step-by-step installation:

```bash
./scripts/apply_radcell_patch.sh /path/to/RADCELL
./scripts/build_radcell.sh /path/to/RADCELL
./scripts/create_radcell_launcher.sh
```

Use this path when you need to isolate a specific failure such as patch application, CMake configuration, linking, or runtime import.

## What this repository contains

- `install_geant4_native.sh`
  - native Geant4 installer and `.deb` packager.

- `scripts/setup_radcell_stack.sh`
  - interactive high-level orchestrator for the full Geant4 + RADCELL + CompuCell3D setup.

- `patches/radcell_compat_geant4_11_python312_cc3d.patch`
  - compatibility patch for the original RADCELL source tree.

- `scripts/apply_radcell_patch.sh`
  - applies or verifies the RADCELL compatibility patch on a local RADCELL checkout.

- `scripts/build_radcell.sh`
  - configures, builds, and installs RADCELL against native Geant4 and CompuCell3D Python.

- `scripts/create_radcell_launcher.sh`
  - creates `~/run_radcell_cc3d_python.sh`, a launcher that loads Geant4, RADCELL, and the required runtime library paths.

- `scripts/upload-release.sh`
  - helper script to create a GitHub release and upload the `.deb` as a release asset.

- `docs/radcell_installation_v0.md`
  - end-to-end RADCELL installation workflow.

- `docs/radcell_first_run.md`
  - first-run validation guide after installation, including `import radcell`, direct `RADCellSimulation.py`, CompuCell3D GUI launch, and expected terminal output.

- `docs/`
  - motivation, validation, release, and RADCELL-remake strategy notes.

## What this repository does not contain

This repository intentionally does **not** include RADCELL source code. The public RADCELL repository appears to have no license file, so copying, modifying, or redistributing its code is not a safe open-source route.

Instead, this repository distributes a compatibility patch and helper scripts. The user must clone the original RADCELL repository separately and apply the patch locally.

The `.deb` package should be distributed as a GitHub **Release asset**, not committed directly to the Git tree. Geant4 packages can exceed GitHub's normal per-file size limits.

## Quick start: build Geant4 only

If you only want the native Geant4 installer/package builder:

```bash
chmod +x install_geant4_native.sh
./install_geant4_native.sh --deb --version 11.4.2 --jobs 4
```

For a lower-RAM machine:

```bash
./install_geant4_native.sh --deb --version 11.4.2 --jobs 2 --no-deps
```

If GCC crashes with an internal compiler error:

```bash
sudo apt install clang lld
./install_geant4_native.sh --deb --version 11.4.2 --compiler clang --clean-build --jobs 4 --no-deps
```

## Install the generated Geant4 package

```bash
sudo apt install ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
source /opt/geant4/11.4.2/bin/geant4.sh
[ -r /etc/profile.d/geant4-11.4.2-datasets.sh ] && source /etc/profile.d/geant4-11.4.2-datasets.sh
geant4-config --version
```

Expected output:

```text
11.4.2
```

## Test Geant4 with B1

```bash
rm -rf ~/geant4-test
mkdir -p ~/geant4-test
cp -r /opt/geant4/11.4.2/share/Geant4/examples/basic/B1 ~/geant4-test/

cmake -S ~/geant4-test/B1 \
      -B ~/geant4-test/B1/build \
      -DGeant4_DIR=/opt/geant4/11.4.2/lib/cmake/Geant4

cmake --build ~/geant4-test/B1/build --parallel 4

cd ~/geant4-test/B1/build
./exampleB1 ../run1.mac
```

## RADCELL compatibility workflow

After Geant4 and CompuCell3D are installed, the complete RADCELL workflow is:

```bash
# Recommended interactive path
./scripts/setup_radcell_stack.sh
```

Or, step by step:

```bash
# Clone the original RADCELL repository separately.
git clone https://github.com/forgetsummer/RADCELL.git

# Apply the compatibility patch.
./scripts/apply_radcell_patch.sh /path/to/RADCELL

# Build and install RADCELL.
./scripts/build_radcell.sh /path/to/RADCELL

# Create the launcher.
./scripts/create_radcell_launcher.sh

# Test the RADCELL Python module.
~/run_radcell_cc3d_python.sh -c "import radcell; print(radcell)"
```

If CompuCell3D Python is not installed in the default location, pass it explicitly:

```bash
./scripts/build_radcell.sh \
  /path/to/RADCELL \
  /path/to/CompuCell3D/miniforge3/envs/cc3d_env/bin/python

./scripts/create_radcell_launcher.sh \
  /path/to/CompuCell3D/miniforge3/envs/cc3d_env/bin/python
```

For the full installation procedure, see:

```text
docs/radcell_installation_v0.md
```

## Runtime launcher and `LD_PRELOAD`

RADCELL may require Geant4 libraries to be preloaded when imported from Python. The launcher created by `scripts/create_radcell_launcher.sh` handles this locally for the launched process.

The repository should not require users to globally set `LD_PRELOAD`.

Avoid placing Geant4 or RADCELL preload settings in:

```text
~/.bashrc
~/.profile
/etc/environment
/etc/ld.so.preload
```

The intended pattern is:

```bash
~/run_radcell_cc3d_python.sh <python-script-or-cc3d-command>
```

not:

```bash
export LD_PRELOAD=/opt/geant4/11.4.2/lib/...
```

## Release the `.deb`

Use GitHub Releases rather than committing the binary package:

```bash
./scripts/upload-release.sh v11.4.2-1 ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
```

## Documentation

Recommended starting points:

- `docs/radcell_installation_v0.md`
  - end-to-end RADCELL installation workflow.

- `docs/radcell_first_run.md`
  - first-run validation guide after installation.

- `examples/radcell_minimal/README.md`
  - minimal RADCELL runtime validation example using the patched VascularTumor workflow.

- `THIRD_PARTY_NOTICES.md`
  - third-party license and attribution notes.

- Additional files in `docs/`
  - project motivation, validation notes, release workflow, and RADCELL-remake strategy.

## Maintainer

Maintained by Luis Gustavo Lang Gaiato.

GitHub: [@luis-gustta](https://github.com/luis-gustta)

## License

The installer, scripts, patches, and documentation in this repository are released under the MIT License unless otherwise noted.

Geant4 itself is not authored by this project and remains subject to the Geant4 Software License and any dataset-specific terms. See `THIRD_PARTY_NOTICES.md`.

RADCELL is not redistributed by this repository. Users should review the upstream RADCELL repository and its licensing status before redistributing modified RADCELL source code.
