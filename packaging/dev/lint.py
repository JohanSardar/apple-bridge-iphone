import ast
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
sources = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT).decode().split('\0')
for relative in sources:
    path = ROOT / relative
    if not relative or not path.is_file():
        continue
    if path.suffix == '.swift':
        for match in re.finditer(r'""".*?"""|"(?:\\.|[^"\\])*"|//|/\*', path.read_text(), re.S):
            if match.group().startswith('/'):
                raise RuntimeError(f'{relative}: code comment')
        subprocess.run(['xcrun', 'swiftc', '-frontend', '-parse', str(path)], check=True, timeout=30)
    elif path.suffix == '.py':
        ast.parse(path.read_text(), filename=relative)
    elif path.suffix == '.sh':
        subprocess.run(['bash', '-n', str(path)], check=True)
print('Swift parse, no-comments, Python and shell syntax: passed')
