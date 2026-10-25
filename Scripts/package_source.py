from pathlib import Path
import argparse
import hashlib
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', default=str(ROOT/'build/Kanke-iOS-source.zip'))
args = parser.parse_args()
output = Path(args.output).resolve()
output.parent.mkdir(parents=True, exist_ok=True)
roots = ['Kanke', 'Kanke.xcodeproj', 'Packages', 'Scripts', 'Verification', '.github']
paths = [ROOT/'README.md', ROOT/'.gitignore', ROOT/'.gitattributes']
for directory in roots:
    paths.extend(p for p in (ROOT/directory).rglob('*') if p.is_file()
                 and not any(x in p.parts for x in ('__pycache__', '.build', '.swiftpm', 'xcuserdata')))
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(set(paths)):
        assert path.suffix.lower() not in ('.p12', '.mobileprovision', '.apk', '.ipa', '.pyc')
        archive.write(path, path.relative_to(ROOT).as_posix())
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
    assert '.github/workflows/build-ios.yml' in archive.namelist()
    assert 'Kanke.xcodeproj/project.pbxproj' in archive.namelist()
    assert all(not n.startswith(('Research/', '.signing/', 'analysis/')) for n in archive.namelist())
    count = len(archive.namelist())
print('Source archive:', output)
print('Files:', count, 'Bytes:', output.stat().st_size)
print('SHA-256:', hashlib.sha256(output.read_bytes()).hexdigest())
