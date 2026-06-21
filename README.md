# Geant4 Native Installer for RADCELL Workflows

This repository provides a native Linux installer and Debian package builder for Geant4, written for users who need a reproducible Geant4 installation without Spack.

The immediate motivation was practical: RADCELL requires Geant4, but its upstream repository gives only high-level installation directions. This project supplies the missing Geant4 installation layer so that RADCELL-like or RADCELL-adjacent radiation-cell simulations can be built on a controlled native stack.

## What this repository contains

- `install_geant4_native.sh` — native Geant4 installer and `.deb` packager.
- `docs/` — motivation, validation, release, and RADCELL-remake strategy notes.
- `scripts/upload-release.sh` — helper script to create a GitHub release and upload the `.deb` as a release asset.

## What this repository does not contain

This repository intentionally does **not** include RADCELL source code. The public RADCELL repository appears to have no license file, so copying, modifying, or redistributing its code is not a safe open-source route.

The `.deb` package should be distributed as a GitHub **Release asset**, not committed directly to the Git tree. Geant4 packages can exceed GitHub's normal per-file size limits.

## Quick build

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

## Install the generated package

```bash
sudo apt install ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
source /opt/geant4/11.4.2/bin/geant4.sh
[ -r /etc/profile.d/geant4-11.4.2-datasets.sh ] && source /etc/profile.d/geant4-11.4.2-datasets.sh
geant4-config --version
```

## Test Geant4 with B1

```bash
rm -rf ~/geant4-test
mkdir -p ~/geant4-test
cp -r /opt/geant4/11.4.2/share/Geant4/examples/basic/B1 ~/geant4-test/

cmake -S ~/geant4-test/B1       -B ~/geant4-test/B1/build       -DGeant4_DIR=/opt/geant4/11.4.2/lib/cmake/Geant4

cmake --build ~/geant4-test/B1/build --parallel 4
cd ~/geant4-test/B1/build
./exampleB1 ../run1.mac
```

## Release the `.deb`

Use GitHub Releases rather than committing the binary package:

```bash
./scripts/upload-release.sh v11.4.2-1 ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
```

## License

The installer and documentation in this repository are released under the MIT License. Geant4 itself is not authored by this project and remains subject to the Geant4 Software License and any dataset-specific terms. See `THIRD_PARTY_NOTICES.md`.
