"""Validate the actual CI artifact's structure, plist and executable."""
from pathlib import Path
import hashlib
import plistlib
import sys
import zipfile

apk = Path(sys.argv[1])
signed = len(sys.argv) > 2 and sys.argv[2] == 'true'
with zipfile.ZipFile(apk) as archive:
    assert archive.testzip() is None, 'ZIP CRC failed'
    names = archive.namelist()
    assert len(names) == len(set(names)), 'Duplicate ZIP members'
    assert all(n.startswith('Payload/') for n in names), 'Wrong IPA root'
    prefix = 'Payload/Kanke.app/'
    info = plistlib.loads(archive.read(prefix+'Info.plist'))
    assert info['CFBundlePackageType'] == 'APPL'
    assert info['CFBundleIdentifier'] and '$(' not in info['CFBundleIdentifier']
    assert float(info['MinimumOSVersion']) >= 16
    executable = archive.read(prefix+info['CFBundleExecutable'])
    assert executable[:4] in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'), 'Not a Mach-O executable'
    assert len(executable) > 10000, 'Executable is unexpectedly small'
    assert prefix+'Assets.car' in names, 'Missing compiled icons/assets'
    assert prefix+'PrivacyInfo.xcprivacy' in names, 'Missing privacy manifest'
    if signed:
        assert prefix+'embedded.mobileprovision' in names
        assert prefix+'_CodeSignature/CodeResources' in names
print('IPA structure passed:', apk.name, apk.stat().st_size, 'bytes')
print('SHA-256:', hashlib.sha256(apk.read_bytes()).hexdigest())
print('Physical-device acceptance: not performed by this packaging script')
