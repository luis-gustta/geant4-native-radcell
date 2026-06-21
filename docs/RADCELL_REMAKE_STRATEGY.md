# RADCELL Licensing and Remake Strategy

## Finding

The public RADCELL repository describes a Geant4/CompuCell3D radiation-cell workflow but does not provide enough installation detail for a clean Linux setup. It also appears to have no `LICENSE` file.

That means this repository should not copy, modify, or redistribute RADCELL code. Public visibility on GitHub is not equivalent to permission to reuse or create derivatives.

## Conservative legal interpretation

- Do not vendor RADCELL code.
- Do not fork RADCELL and modify it unless the authors add a license or grant permission.
- Do not copy class structure, file organization, or implementation details into a replacement project.
- It is acceptable to implement a clean-room alternative from public scientific descriptions, Geant4 documentation, and independently designed APIs.

This is not legal advice; it is a conservative engineering route.

## Recommended route: clean-room Geant4-first remake

The safest technical route is a new project with a new API and no RADCELL source dependency:

1. **Core engine:** Geant4 / Geant4-DNA.
2. **Geometry model:** explicit cell, nucleus, cytoplasm, and optional organelle volumes.
3. **Input:** YAML or JSON scene description.
4. **Scoring:** per-volume energy deposition, dose, event-level deposition points, and optional DNA-damage proxy models.
5. **Output:** HDF5/CSV/Parquet tables for analysis in Python.
6. **Coupling layer:** optional CompuCell3D adapter that exchanges cell positions/radii and receives dose or damage observables.
7. **Validation:** reproduce simple Geant4-DNA examples first, then add cell-dose benchmarks.

## TOPAS route

TOPAS may be a useful higher-level route because it reduces the amount of raw Geant4 C++ needed. However, before building a TOPAS-dependent project, verify TOPAS access and licensing. If TOPAS is not fully open for the intended redistribution model, the clean-room raw-Geant4 route is safer.

## Possible project name

Candidate names:

- `CellRadG4`
- `OpenCellDose`
- `G4CellDose`
- `RadCellLite`

Avoid `RADCELL` in the project name to reduce confusion with the upstream project.

## Minimal architecture

```text
cellradg4/
  core/
    GeometryBuilder.cc
    PhysicsListFactory.cc
    PrimaryGenerator.cc
    DoseScorer.cc
    EventRecorder.cc
  io/
    SceneConfig.yaml
    Hdf5Writer.cc
  python/
    cellradg4/
      run.py
      analysis.py
  examples/
    single_cell.yaml
    monolayer.yaml
    tumor_spheroid.yaml
```

## First milestone

A defensible first release should do only this:

- Build one spherical cell with spherical nucleus.
- Run Geant4-DNA physics in water.
- Score dose in cytoplasm and nucleus separately.
- Export energy-deposition points.
- Provide one reproducible example and one validation notebook.

Only after that should CompuCell3D coupling be added.
