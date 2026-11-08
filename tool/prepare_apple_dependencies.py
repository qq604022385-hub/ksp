"""Prefetch checksum-pinned Apple SDKs through their official release asset API."""
import argparse
import hashlib
import json
import platform
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import quote, unquote, urljoin, urlparse
from urllib.request import url2pathname


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def curl(url, destination, *, binary=False):
    parsed = urlparse(url)
    if parsed.scheme != 'https' or parsed.hostname != 'api.github.com' or parsed.username:
        raise ValueError('Expected an official GitHub API URL')
    subprocess.run([
        'curl', '--fail', '--location', '--silent', '--show-error',
        '--retry', '4', '--retry-delay', '3', '--retry-all-errors',
        '--connect-timeout', '20', '--max-time', '180',
        '--header', 'Accept: application/octet-stream' if binary else 'Accept: application/vnd.github+json',
        '--output', str(destination), url,
    ], check=True)


def asset_api_url(url, expected):
    parsed = urlparse(url)
    if parsed.scheme == 'https' and parsed.hostname == 'api.github.com':
        return url
    parts = parsed.path.strip('/').split('/')
    if parsed.scheme != 'https' or parsed.hostname != 'github.com' or len(parts) != 6 or parts[2:4] != ['releases', 'download']:
        raise ValueError('Expected a fixed GitHub release download')
    owner, repo, _, _, tag, name = parts
    endpoint = f'https://api.github.com/repos/{owner}/{repo}/releases/tags/{quote(unquote(tag), safe="")}'
    with tempfile.TemporaryDirectory() as directory:
        metadata = Path(directory) / 'release.json'
        curl(endpoint, metadata)
        release = json.loads(metadata.read_text())
    for asset in release['assets']:
        if asset['name'] == unquote(name):
            remote_digest = asset.get('digest')
            if remote_digest and remote_digest != 'sha256:' + expected:
                raise ValueError('Release metadata does not match the pinned SHA-256')
            return asset['url']
    raise ValueError('Pinned release asset not found')


def fetch(url, expected, destination):
    if destination.is_file() and digest(destination) == expected:
        print('Cached and verified:', destination.name, flush=True)
        return
    api_url = asset_api_url(url, expected)
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + '.download')
    try:
        curl(api_url, partial, binary=True)
        if digest(partial) != expected:
            raise ValueError('Dependency SHA-256 mismatch')
        partial.replace(destination)
    finally:
        partial.unlink(missing_ok=True)
    print('Downloaded and verified:', destination.name, flush=True)


def prepare(root, host):
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text())['packages']
    ech = next(item for item in packages if item['name'] == 'ech_http')
    package_uri = urljoin(config.as_uri(), ech['rootUri'])
    if urlparse(package_uri).scheme != 'file':
        raise ValueError('Expected a local resolved ech_http package')
    ech_root = Path(url2pathname(unquote(urlparse(package_uri).path)))
    dependencies = json.loads((ech_root / 'lib/src/build_support/dependencies.json').read_text())
    for target in [host, 'ios-arm64-device']:
        item = dependencies['targets'][target]
        expected = item['sha256']
        # Default cache layout owned by ech_http's unmodified build hook.
        target_file = root / '.dart_tool/hooks_runner/shared/ech_http/build/prebuilt' / f'{target}-{expected}.zip'
        fetch(item['url'], expected, target_file)
    bundles = json.loads((root / 'third_party/media-kit/media_kit/hook/native_bundles.json').read_text())['bundles']
    for target in [host.replace('-', '_'), 'ios_arm64']:
        item = bundles[target]
        target_file = root / '.dart_tool/hooks_runner/shared/media_kit/build/prebuilt' / item['sha256'] / ('archive.' + item['format'])
        fetch(item['url'], item['sha256'], target_file)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host-target', choices=['macos-arm64', 'macos-x64'],
                        default='macos-arm64' if platform.machine() == 'arm64' else 'macos-x64')
    arguments = parser.parse_args()
    prepare(Path(__file__).resolve().parents[1], arguments.host_target)
