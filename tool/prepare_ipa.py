"""Restore executable modes lost in downloaded native framework archives."""
import json
from pathlib import Path
import plistlib
import stat
import sys


def prepare_application(application):
    root = Path(application).resolve(strict=True)
    assert root.is_dir() and root.suffix == '.app', 'Expected an application directory'
    executables = set(root.rglob('*.dylib'))
    for path in root.rglob('Info.plist'):
        info = plistlib.loads(path.read_bytes())
        name = info.get('CFBundleExecutable')
        if name:
            assert Path(name).name == name, f'Invalid executable name: {path}'
            executables.add(path.parent / name)
    changed = []
    for path in sorted(executables):
        target = path.resolve(strict=True)
        assert target.is_relative_to(root) and target.is_file(), f'Invalid executable path: {path}'
        with target.open('rb') as binary:
            magic = binary.read(4)
        assert magic in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'), f'Expected Mach-O: {path}'
        mode = stat.S_IMODE(target.stat().st_mode)
        if mode & 0o111 != 0o111:
            target.chmod(mode | 0o111)
            changed.append(path.relative_to(root).as_posix())
    return {'executable_files': len(executables), 'restored_modes': changed}


if __name__ == '__main__':
    print(json.dumps(prepare_application(sys.argv[1])))
