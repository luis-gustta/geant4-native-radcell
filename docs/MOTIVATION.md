# Motivation: Native Geant4 Packaging for RADCELL-Style Workflows

## Problem

RADCELL is a radiation transport module for cell-level dose and DNA-damage simulations. Its upstream documentation states that the user should install Geant4, compile RADCellSimulation, set `PYTHONPATH`/`LD_LIBRARY_PATH`, install CompuCell3D, and then run the example project. That is not enough for a fresh Linux installation because the hardest and most failure-prone step is the Geant4 stack itself.

The goal of this repository is to remove that ambiguity by producing a native Geant4 installation and, on Debian-family systems, a reusable `.deb` package.

## Why not Spack for this use case?

Spack is valuable for HPC centers and multi-variant research stacks. It is not the shortest path for this specific problem.

For a single workstation or lab machine, a native `.deb` has practical advantages:

1. **Uses the system package manager.** Dependencies are installed by `apt`, not hidden inside a separate Spack prefix.
2. **Predictable prefix.** Geant4 lands in `/opt/geant4/<version>`, which is easy to reference from CMake, RADCELL, TOPAS, or CompuCell3D glue code.
3. **Reusable binary artifact.** Once built, the `.deb` can be copied to another compatible Ubuntu/Linux Mint machine.
4. **Simpler debugging.** Runtime errors are checked with `ldd`, `geant4-config`, and normal Debian package metadata.
5. **No Spack concretizer layer.** The user does not need to understand Spack specs, compilers, variants, external packages, environments, mirrors, or views just to compile a Geant4-dependent module.
6. **Better for teaching and lab reproducibility.** A single script plus a `.deb` is easier to document in a thesis, article supplement, or group README.

This does not claim Spack is bad. The point is narrower: for installing Geant4 as a prerequisite for a poorly documented downstream module, native packaging is more transparent.

## Why package datasets manually?

Geant4 datasets are large, and CMake's internal downloader can fail after hundreds of megabytes without robust resume behavior. The script disables CMake dataset installation and downloads datasets manually with `curl -C -`, retry logic, and validation before extraction.

## Intended audience

- Linux users trying to build RADCELL or RADCELL-like simulations.
- Computational radiation biology students.
- Users who need Geant4-DNA but do not want a Spack environment.
- Labs that want one tested package for several compatible machines.
