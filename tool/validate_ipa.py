"""Validate actual archive structure after the macOS build; no signing claims."""
import json
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, 'Invalid ZIP CRC'
    names = archive.namelist()
    info_paths = [n for n in names if n.count('/') == 2 and n.startswith('Payload/') and n.endswith('.app/Info.plist')]
    assert len(info_paths) == 1, 'Expected one iPhone application'
    info = plistlib.loads(archive.read(info_paths[0]))
    root = info_paths[0].rsplit('/', 1)[0] + '/'
    executable = root + info['CFBundleExecutable']
    assert len(archive.read(executable)) > 4096, 'Missing executable'
    assert 'iPhoneOS' in info.get('CFBundleSupportedPlatforms', []), 'Not an iPhoneOS app'
    assert root+'Frameworks/App.framework/App' in names, 'Missing compiled Dart application'
    assert root+'Frameworks/Flutter.framework/Flutter' in names, 'Missing Flutter runtime'
    print(json.dumps({'bundle_id': info['CFBundleIdentifier'], 'version': info['CFBundleShortVersionString'],
                      'files':len(names), 'zip_crc':'passed', 'signed':False}, ensure_ascii=False))
