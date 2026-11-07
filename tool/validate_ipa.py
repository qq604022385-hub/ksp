"""Check an unsigned iPhone IPA before publishing; signing is a separate step."""
import collections
import json
from pathlib import PurePosixPath
import plistlib
import struct
import sys
import zipfile


def macho_slices(data):
    """Read architecture/platform metadata, including universal Flutter binaries."""
    assert len(data) >= 8, 'Truncated Mach-O binary'
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        count = struct.unpack_from('>I', data, 4)[0]
        assert 0 < count <= 16, 'Invalid universal binary architecture count'
        stride = 32 if magic[-1] == 0xbf else 20
        result = []
        for index in range(count):
            offset = 8 + index * stride
            if stride == 32:
                start, length = struct.unpack_from('>QQ', data, offset + 8)
            else:
                start, length = struct.unpack_from('>II', data, offset + 8)
            assert start + length <= len(data), 'Truncated universal binary'
            result.extend(macho_slices(data[start:start + length]))
        return result
    assert magic == b'\xcf\xfa\xed\xfe', f'Unsupported Mach-O format: {magic.hex()}'
    assert len(data) >= 32, 'Truncated Mach-O header'
    _, cpu, subtype, filetype, commands, command_bytes, _, _ = struct.unpack_from('<8I', data)
    assert 32 + command_bytes <= len(data), 'Invalid Mach-O command area'
    result = {'cpu': cpu, 'subtype': subtype, 'filetype': filetype}
    offset = 32
    for _ in range(commands):
        command, size = struct.unpack_from('<II', data, offset)
        assert size >= 8 and offset + size <= 32 + command_bytes, 'Invalid Mach-O load command'
        if command == 0x32:
            result['platform'] = struct.unpack_from('<I', data, offset + 8)[0]
        elif command == 0x25:
            result['platform'] = 2  # LC_VERSION_MIN_IPHONEOS on older Flutter engines.
        elif command in (0x21, 0x2c):
            assert struct.unpack_from('<I', data, offset + 16)[0] == 0, 'Encrypted App Store binary'
        offset += size
    return [result]


def validate_ipa(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'Invalid ZIP CRC'
        names = archive.namelist()
        assert len(names) == len(set(names)), 'Duplicate ZIP paths'
        for name in names:
            parts = PurePosixPath(name).parts
            assert not name.startswith('/') and '..' not in parts, 'Unsafe ZIP path'
            assert name.startswith('Payload/'), f'Unexpected IPA root item: {name}'
        info_paths = [name for name in names if name.count('/') == 2
                      and name.endswith('.app/Info.plist')]
        assert len(info_paths) == 1, 'Expected one iPhone application'
        info = plistlib.loads(archive.read(info_paths[0]))
        root = info_paths[0].rsplit('/', 1)[0] + '/'
        assert info.get('CFBundlePackageType') == 'APPL', 'Invalid main application type'
        assert 'iPhoneOS' in info.get('CFBundleSupportedPlatforms', []), 'Not an iPhoneOS app'
        assert info.get('CFBundleShortVersionString') and info.get('CFBundleVersion'), 'Missing app version'
        assert info.get('UIDeviceFamily') and 1 in info['UIDeviceFamily'], 'iPhone support missing'
        identifiers = collections.defaultdict(list)
        executable_count = 0
        for name in names:
            if not name.endswith('/Info.plist'):
                continue
            bundle = plistlib.loads(archive.read(name))
            if bundle.get('CFBundlePackageType') not in ('APPL', 'FMWK', 'BNDL', 'XPC!'):
                continue
            identifier = bundle.get('CFBundleIdentifier')
            assert identifier, f'Bundle identifier missing: {name}'
            identifiers[identifier].append(name)
            executable_name = bundle.get('CFBundleExecutable')
            if not executable_name:
                assert bundle.get('CFBundlePackageType') == 'BNDL', f'Executable missing: {name}'
                continue
            executable = name.rsplit('/', 1)[0] + '/' + executable_name
            assert executable in names, f'Executable file missing: {executable}'
            assert archive.getinfo(executable).external_attr >> 16 & 0o111, f'Executable permission missing: {executable}'
            architectures = macho_slices(archive.read(executable))
            assert any(a['cpu'] == 0x100000c for a in architectures), f'ARM64 missing: {executable}'
            assert all(a.get('platform') == 2 for a in architectures), f'Non-iPhone binary: {executable}'
            executable_count += 1
        duplicates = {key: paths for key, paths in identifiers.items() if len(paths) > 1}
        assert not duplicates, 'Duplicate bundle identifiers: ' + json.dumps(duplicates)
        for framework in ('App', 'Flutter'):
            assert root + f'Frameworks/{framework}.framework/{framework}' in names, f'Missing {framework} runtime'
        return {'bundle_id': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
                'files': len(names), 'bundles': len(identifiers), 'executables': executable_count,
                'zip_crc': 'passed', 'unique_bundle_identifiers': 'passed',
                'arm64_iphone_binaries': 'passed', 'signed': False}


if __name__ == '__main__':
    print(json.dumps(validate_ipa(sys.argv[1]), ensure_ascii=False))
