import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT / 'ios/BogoKit'
VECTORS = KIT / 'BogoRelay/StandInVectors'
SWIFTC = ['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library']
counts = json.loads((VECTORS / 'manifest.json').read_text())['counts']
PROOFS = [
    ('vectors', 'BogoModel', 'BogoVectorsProof.swift', [str(VECTORS)], f"PASS {counts['requests']} requests, {counts['decode_reject']} rejects, 3 reviews"),
    ('review-exact-key', 'BogoModel', 'BogoReviewExactKeyProof.swift', [], ''),
    ('reason-picture', 'BogoModel', 'BogoReasonPictureProof.swift', [], 'PASS S1'),
    ('closed-room', 'BogoRelay', 'BogoClosedRoomProof.swift', [], 'PASS'),
    ('early-sync', 'BogoRelay', 'BogoEarlySyncProof.swift', [], 'PASS'),
    ('retry-sync', 'BogoRelay', 'BogoRetrySyncProof.swift', [], 'PASS'),
    ('reconciliation', 'BogoRelay', 'BogoReconciliationProof.swift', [], ''),
]


def sources(module):
    return sorted(str(path) for path in (KIT / module).glob('*.swift'))


with tempfile.TemporaryDirectory(prefix='bogo-proofs-') as temporary:
    out = Path(temporary)
    linked = ['-I', temporary, '-L', temporary, '-Xlinker', '-rpath', '-Xlinker', temporary]
    for module, needs in [('BogoModel', []), ('BogoCrypto', ['BogoModel'])]:
        library = out / f'lib{module}.dylib'
        subprocess.run([*SWIFTC, '-emit-library', '-emit-module', '-module-name', module, *linked, *[f'-l{need}' for need in needs], *sources(module), '-o', str(library), '-Xlinker', '-install_name', '-Xlinker', f'@rpath/{library.name}'], cwd=ROOT, check=True, timeout=300)
    for name, home, proof, arguments, expected in PROOFS:
        binary = out / name
        modules = [] if home == 'BogoModel' else [*linked, '-lBogoModel', '-lBogoCrypto']
        subprocess.run([*SWIFTC, *modules, *sources(home), str(ROOT / 'lab/ios' / proof), '-o', str(binary)], cwd=ROOT, check=True, timeout=300)
        result = subprocess.run([str(binary), *arguments], cwd=temporary, capture_output=True, text=True, timeout=60)
        if result.returncode != 0 or result.stdout.strip() != expected:
            raise SystemExit(f'{name}: failed\n{result.stdout}{result.stderr}')
        print(f'bogo {name}: passed', flush=True)
result = subprocess.run(['python3', str(ROOT / 'packaging/dev/prove-approval-key-failure.py')], capture_output=True, text=True, timeout=900)
if result.returncode != 0 or result.stdout.strip() != 'PASS S1':
    raise SystemExit(f'approval-key-failure: failed\n{result.stdout}{result.stderr}')
print('bogo approval-key-failure: passed', flush=True)
print(f'{len(PROOFS) + 1} BOGO proofs passed')
