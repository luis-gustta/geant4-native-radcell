"""Run with python3 tests/test_cell_count_recording.py /path/to/upstream/RADCELL.

Uses temporary source trees; does not import CC3D or run Geant4.
"""
import ast
import io
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile

repo = Path(__file__).resolve().parents[1]
upstream = Path(sys.argv[1]).resolve()
archive = subprocess.check_output(['git', 'archive', 'HEAD'], cwd=upstream)
old_patch = subprocess.check_output(
    ['git', 'show', '2a45e3cfc1205197b78e2812f02a1a723291af46:patches/radcell_compat_geant4_11_python312_cc3d.patch'], cwd=repo)


def apply(tree):
    subprocess.run(['bash', str(repo / 'scripts/apply_radcell_patch.sh'), str(tree)],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


with tempfile.TemporaryDirectory() as tmp:
    for mode in ('fresh', 'upgrade'):
        tree = Path(tmp) / mode
        tree.mkdir()
        with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
            tar.extractall(tree, filter='data')
        if mode == 'upgrade':
            subprocess.run(['patch', '--batch', '-p1'], input=old_patch, cwd=tree,
                           check=True, stdout=subprocess.PIPE)
        apply(tree)
        source = tree / 'VascularTumor/Simulation/VascularTumorSteppables.py'
        before = source.read_bytes()
        apply(tree)
        assert source.read_bytes() == before, 'Repeated application changes source'
        parsed = ast.parse(source.read_text())
        cls = next(n for n in parsed.body if isinstance(n, ast.ClassDef)
                   and n.name == 'VolumeParamSteppable')
        names = {'_record_cell_counts', '_close_cell_counts', 'finish', 'on_stop'}
        methods = [n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name in names]
        namespace = {}
        exec(compile(ast.Module(body=methods, type_ignores=[]), str(source), 'exec'), namespace)
        Recorder = type('Recorder', (), {n: namespace[n] for n in names})
        step = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == 'step')
        assert any(isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)
                   and n.func.attr == '_record_cell_counts' for n in ast.walk(step))
        for ending in ('finish', 'on_stop'):
            output = tree / (ending + '.csv')
            recorder = Recorder()
            recorder.cellNumberFileOut = output.open('w')
            recorder._record_cell_counts(0, 100, 12, 0, 0)
            assert output.read_text() == '0,100,12,0,0\n'
            recorder._record_cell_counts(50, 95, 12, 0, 5)
            expected = '0,100,12,0,0\n50,95,12,0,5\n'
            assert output.read_text() == expected, 'Counts not flushed during run'
            getattr(recorder, ending)()
            recorder.on_stop()
            recorder.finish()
            assert recorder.cellNumberFileOut.closed
            assert output.read_text() == expected, 'Closing duplicates rows'
        print('PASS:', mode, 'application, repeat application, live writes, finish and Stop')
