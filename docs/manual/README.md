# Technical Manual

This directory is reserved for the technical reference manual of the `geant4-native-radcell` codebase.

The manual documents:

- the repository structure;
- the native Geant4 installation workflow;
- the RADCELL compatibility patching layer;
- the build scripts;
- the launcher model;
- validation procedures;
- headless and GUI execution paths;
- safe local modification of RADCELL/VascularTumor experiments.

## Recommended source file

Use the English `refrep/refman` LaTeX source as the maintained manual source:

```text
manual_geant4_native_radcell_refman_en.tex
```

The auxiliary class/style files required by Overleaf should live next to the `.tex` source:

```text
refrep.cls
refart.cls
pagepc.sty
```

## PDF policy

Prefer attaching compiled PDFs to GitHub Releases instead of committing frequently regenerated PDF files to the Git tree.
