"""Host-independent project/source consistency checks. No iOS compilation claim."""
from pathlib import Path
import json
import plistlib
import re
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
checks = []
def check(name, passed):
    checks.append((name, bool(passed)))
    if not passed: raise AssertionError(name)

def openstep(text):
    pattern = r'\s+|//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+'
    tokens = [m.group() for m in re.finditer(pattern, text) if not m.group().isspace() and not m.group().startswith(('//','/*'))]
    index = 0
    def consume(expected=None):
        nonlocal index
        value = tokens[index]; index += 1
        if expected: assert value == expected, (expected, value)
        return value
    def value():
        if tokens[index] == '{':
            consume('{'); out = {}
            while tokens[index] != '}':
                key = consume(); consume('='); item = value(); consume(';')
                assert key not in out, key
                out[key] = item
            consume('}'); return out
        if tokens[index] == '(':
            consume('('); out = []
            while tokens[index] != ')':
                out.append(value())
                if tokens[index] != ')': consume(',')
            consume(')'); return out
        token = consume()
        return json.loads(token) if token.startswith('"') else token
    result = value()
    assert index == len(tokens)
    return result

project = openstep((ROOT/'Kanke.xcodeproj/project.pbxproj').read_text(encoding='utf-8'))
objects = project['objects']
check('Project root references a PBXProject', objects[project['rootObject']]['isa'] == 'PBXProject')
def refs(obj):
    if isinstance(obj, dict):
        for v in obj.values(): yield from refs(v)
    elif isinstance(obj, list):
        for v in obj: yield from refs(v)
    elif re.fullmatch('[A-F0-9]{24}', str(obj)): yield obj
check('All Xcode object references exist', all(ref in objects for ref in refs(project)))
phase = next(v for v in objects.values() if v.get('isa') == 'PBXSourcesBuildPhase')
source_files = {objects[objects[ref]['fileRef']]['path'] for ref in phase['files']}
check('All native Swift files are included in build', source_files == {p.name for p in (ROOT/'Kanke').glob('*.swift')})
check('Build sources exist', all((ROOT/'Kanke'/p).is_file() for p in source_files))
check('Local Swift package exists', (ROOT/'Packages/KankeCore/Package.swift').is_file())
package_ref = next(v for v in objects.values() if v.get('isa') == 'XCLocalSwiftPackageReference')
check('Swift package path matches project', (ROOT/package_ref['relativePath']/'Package.swift').is_file())
scheme = ET.parse(ROOT/'Kanke.xcodeproj/xcshareddata/xcschemes/Kanke.xcscheme')
check('Shared build scheme references native target', all(e.get('BlueprintIdentifier') in objects for e in scheme.iter('BuildableReference')))
with (ROOT/'Kanke/Info.plist').open('rb') as f: info = plistlib.load(f)
check('Main plist valid, with dynamic HTTP compatibility', info['NSAppTransportSecurity']['NSAllowsArbitraryLoads'] is True)
check('Audio background mode declared', info['UIBackgroundModes'] == ['audio'])
with (ROOT/'Kanke/PrivacyInfo.xcprivacy').open('rb') as f: privacy = plistlib.load(f)
check('Privacy manifest parses', privacy['NSPrivacyTracking'] is False)
data = (ROOT/'Kanke/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes()
check('AppIcon opaque 1024px RGB PNG', data[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', data[16:24]) == (1024,1024) and data[25] == 2)
for path in (ROOT/'Kanke/Assets.xcassets').rglob('Contents.json'): json.loads(path.read_text(encoding='utf-8'))
check('Asset catalogs parse', True)
check('No remote package dependencies', '.package(' not in (ROOT/'Packages/KankeCore/Package.swift').read_text(encoding='utf-8'))
workflow = (ROOT/'.github/workflows/build-ios.yml').read_text(encoding='utf-8')
check('CI runs Swift tests before device archive', workflow.index('swift test') < workflow.index('Archive iPhone'))
check('CI defaults to unsigned, with explicit optional signing', 'default: false' in workflow and 'inputs.signed == true' in workflow)
check('CI validates IPA after packaging', 'validate_ipa.py' in (ROOT/'Scripts/package_ipa.sh').read_text(encoding='utf-8'))
for name in ('sign_app.sh', 'package_ipa.sh'):
    check(name+' has LF line endings', b'\r\n' not in (ROOT/'Scripts'/name).read_bytes())
check('Protocol fixtures present', bool(list((ROOT/'Packages/KankeCore/Tests/KankeCoreTests/Fixtures').glob('*.json'))))
print(json.dumps({'source_consistency_checks_passed': len(checks), 'xcode_compilation_performed_here': False}, indent=2))
