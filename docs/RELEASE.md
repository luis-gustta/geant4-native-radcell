# GitHub Repository and Release Procedure

## v0.4.1 — Clean headless RADCELL execution

This maintenance release cleans up the headless RADCELL/Geant4 execution path used by the modern CompuCell3D workflow.

Main changes:

- prevents `RADCellSimulationInitialize()` from executing `vis.mac` automatically;
- removes the unwanted `/vis/open OGL` attempt in headless `out` runs;
- extends `scripts/verify_radcell_compat.sh` to check the C++ headless compatibility changes;
- updates `scripts/setup_radcell_stack.sh` version to `0.4.1`.

Validation performed locally:

- patched clean RADCELL checkout builds successfully;
- isolated launcher imports `radcell` successfully;
- headless `RADCellSimulation.py "out test_cc3d" testInputSource` starts Geant4 event processing without the previous `/vis/open OGL` command error.

## v0.4.0 — Modernized CompuCell3D VascularTumor workflow

This release adds the modern CompuCell3D-compatible RADCELL VascularTumor workflow.

Main changes:

- modernizes the original RADCELL `VascularTumor` Python workflow for current CompuCell3D APIs;
- removes the need for legacy `PYTHON_MODULE_PATH` and shim modules;
- uses modern `cc3d` imports and steppable registration;
- updates the VascularTumor neighbor API from `getCellNeighbors` to `getCellNeighborDataList`;
- forces RADCELL/Geant4 execution to use headless `out` mode while keeping the CompuCell3D GUI usable;
- adds `scripts/verify_radcell_compat.sh` to check whether a RADCELL checkout was patched correctly;
- integrates compatibility verification into `scripts/setup_radcell_stack.sh`;
- ignores CompuCell3D-generated `VascularTumor_cc3d_*` output directories.

Validation performed locally:

- patched RADCELL VascularTumor opens in CompuCell3D without compatibility shims;
- cells remain stable during early GUI simulation steps;
- RADCELL Python modules compile under the CompuCell3D Python environment;
- compatibility verifier passes on the patched RADCELL checkout.

## Create repository

The connector used to prepare this bundle cannot create a new GitHub repository. Use GitHub CLI locally:

```bash
gh auth login
gh repo create luis-gustta/geant4-native-radcell --public   --description "Native Geant4 installer and Debian package workflow for RADCELL-style simulations"   --source .   --remote origin   --push
```

Or manually create an empty repo on GitHub, then:

```bash
git remote add origin git@github.com:luis-gustta/geant4-native-radcell.git
git branch -M main
git push -u origin main
```

## Do not commit the `.deb`

Use GitHub Releases for `.deb` packages:

```bash
./scripts/upload-release.sh v11.4.2-1 ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb
```

The release asset is the right place for the binary package. The Git repo should contain source, docs, checksums, and packaging scripts.

## Compute checksum

```bash
sha256sum ~/.cache/geant4-native-build/packages/geant4-native_11.4.2-1_amd64.deb > checksums/SHA256SUMS
```

Commit the checksum file:

```bash
git add checksums/SHA256SUMS
git commit -m "Add release checksum for Geant4 11.4.2 package"
git push
```
