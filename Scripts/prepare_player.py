"""Fetch the pinned public FFmpegKit iOS artifacts; never execute build plugins."""
from pathlib import Path
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'Vendor/FFmpegKit'
REPO = 'https://github.com/kingslay/FFmpegKit.git'
TAG = '6.1.3'
COMMIT = '85b77c589de0360c111de16752db86b60496d70b'

def git(*args, cwd=None, data=None):
    return subprocess.run(['git', *args], cwd=cwd, input=data, text=True,
                          check=True, stdout=subprocess.PIPE).stdout.strip()

def main():
    if not shutil.which('git'):
        raise SystemExit('Git is not on PATH; expose a working Git executable and retry.')
    print(git('--version'), flush=True)
    if DEST.exists():
        if not (DEST/'.git').is_dir() or git('rev-parse', 'HEAD', cwd=DEST) != COMMIT:
            raise SystemExit('Vendor/FFmpegKit exists with different contents. Move it aside before retrying.')
        if git('status', '--porcelain', cwd=DEST):
            raise SystemExit('Vendor/FFmpegKit has local changes; refusing to overwrite them.')
    else:
        DEST.parent.mkdir(parents=True, exist_ok=True)
        git('clone', '--filter=blob:none', '--no-checkout', '--depth=1',
            '--single-branch', '--branch', TAG, REPO, str(DEST))
        if git('rev-parse', 'HEAD', cwd=DEST) != COMMIT:
            raise SystemExit('Upstream tag no longer matches the pinned commit.')
    # All declared source targets, plus both iPhone and simulator architectures.
    # libbluray is a macOS-only, conditional dependency; keep its small artifact intact.
    patterns = '\n'.join([
        '/Package.swift', '/LICENSE*', '/README*', '/Plugins/',
        '/Sources/FFmpegKit/', '/Sources/fftools/', '/Sources/ffmpeg/',
        '/Sources/ffplay/', '/Sources/ffprobe/', '/Sources/SDL2/',
        '/Sources/*.xcframework/Info.plist',
        '/Sources/*.xcframework/ios-arm64/',
        '/Sources/*.xcframework/ios-arm64_x86_64-simulator/',
        '/Sources/libbluray.xcframework/',
    ]) + '\n'
    git('sparse-checkout', 'set', '--no-cone', '--stdin', cwd=DEST, data=patterns)
    git('checkout', '--detach', COMMIT, cwd=DEST)
    verified = 0
    for info in sorted((DEST/'Sources').glob('*.xcframework/Info.plist')):
        entries = plistlib.loads(info.read_bytes())['AvailableLibraries']
        if info.parent.name == 'libbluray.xcframework':
            continue
        for variant in (None, 'simulator'):
            candidates = [e for e in entries if e['SupportedPlatform'] == 'ios'
                          and e.get('SupportedPlatformVariant') == variant
                          and 'arm64' in e['SupportedArchitectures']]
            if not candidates:
                raise SystemExit(f'Missing iOS arm64 slice: {info.parent.name}, {variant}')
            item = candidates[0]
            artifact = info.parent/item['LibraryIdentifier']/item['LibraryPath']
            if not artifact.exists():
                raise SystemExit(f'Missing artifact: {artifact}')
            binary = artifact/artifact.stem if artifact.suffix == '.framework' else artifact
            if not binary.is_file() or binary.stat().st_size < 100:
                raise SystemExit(f'Missing native binary: {binary}')
            verified += 1
    if verified != 50:
        raise SystemExit(f'Expected 50 device/simulator slices, found {verified}')
    print(f'FFmpegKit {TAG} @ {COMMIT}: {verified} iOS artifact slices verified.', flush=True)

if __name__ == '__main__':
    main()
