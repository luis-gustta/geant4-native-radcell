# RADCELL Minimal Validation Example

This example provides a small validation wrapper for a patched and installed RADCELL workflow.

It does not define a new radiation biology model and it does not replace the original RADCELL examples. Its purpose is narrower:

- verify that the RADCELL launcher exists;
- verify that Python can import `radcell`;
- verify that the original `VascularTumor/Simulation` files are present;
- run `RADCellSimulation.py` directly through the launcher;
- save logs in one place;
- report simple `PASS` / `FAIL` messages.

## Default assumptions

The script assumes the default paths used by this repository:

```text
RADCELL source:  ~/radcell/RADCELL
Launcher:        ~/run_radcell_cc3d_python.sh
```

These are the defaults created by:

```bash
./scripts/setup_radcell_stack.sh
```

If your RADCELL source tree is elsewhere, pass the path explicitly.

Example for a local test tree:

```bash
examples/radcell_minimal/run_validation.sh \
  --radcell-root /home/luis/Desktop/Test/RADCELL \
  --launcher /home/luis/run_radcell_cc3d_python.sh
```

## Run

From the repository root:

```bash
examples/radcell_minimal/run_validation.sh
```

With explicit paths:

```bash
examples/radcell_minimal/run_validation.sh \
  --radcell-root /path/to/RADCELL \
  --launcher /path/to/run_radcell_cc3d_python.sh
```

With a fixed log directory:

```bash
examples/radcell_minimal/run_validation.sh \
  --radcell-root /path/to/RADCELL \
  --launcher /path/to/run_radcell_cc3d_python.sh \
  --log-dir ./radcell_validation_logs
```

## What it checks

The script checks for:

```text
RADCELL_ROOT/VascularTumor/Simulation/RADCellSimulation.py
RADCELL_ROOT/VascularTumor/Simulation/testInputSource.in
RADCELL_ROOT/VascularTumor/Simulation/cellInformation.csv
```

Then it runs:

```bash
"$RADCELL_LAUNCHER" -c "import radcell; print(radcell.__file__)"
```

and:

```bash
cd "$RADCELL_ROOT/VascularTumor/Simulation"

"$RADCELL_LAUNCHER" RADCellSimulation.py \
  "out test_cc3d" \
  testInputSource
```

## Logs

By default, logs are written under a temporary directory:

```text
/tmp/radcell-minimal-validation.XXXXXX/
```

The main logs are:

```text
import_radcell.log
direct_radcellsimulation.log
```

Use `--log-dir` to choose a persistent location.

## Timeout behavior

The direct `RADCellSimulation.py` test uses a timeout.

Default:

```text
120 seconds
```

Override:

```bash
examples/radcell_minimal/run_validation.sh --timeout 300
```

If the timeout is reached after RADCELL/Geant4 initialization, the script may still report that the startup path was reached. This is intentional: the example validates the runtime wiring, not a full production simulation.

## What counts as success

A successful run should show:

```text
[PASS] Python can import radcell through the launcher
[PASS] Direct run reached RADCELL/Geant4 startup
[PASS] Minimal RADCELL validation finished
```

The direct run log should contain lines related to:

```text
cellInformation
Loaded cells
Tissue dimensions
Geant4
runMode
radiationSource
```

Exact output depends on the upstream RADCELL version and the current `cellInformation.csv`.

## What this does not validate

This example does not validate:

- physical accuracy of the Geant4 model;
- biological correctness of survival or damage models;
- full CompuCell3D/RADCELL coupling over a complete MCS schedule;
- the original high-MCS VascularTumor radiation schedule.

For CompuCell3D GUI validation, see:

```text
docs/radcell_first_run.md
```

## ShellCheck

Validate the script with:

```bash
shellcheck examples/radcell_minimal/run_validation.sh
```
