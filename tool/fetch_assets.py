"""Restore exact upstream binary resources before pub get/build; no credentials."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import time
import urllib.request

root = Path(__file__).resolve().parents[1]
manifest = json.loads((Path(__file__).with_name('upstream-assets.json')).read_text(encoding='utf-8'))

def restore(item):
    target = (root / item['path']).resolve()
    if not target.is_relative_to(root) or item['size'] > 12_000_000:
        raise ValueError('Invalid asset manifest entry')
    if target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == item['sha256']:
        return item['path']
    last = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(item['url'], headers={'User-Agent': 'Kazumi-iOS-build'})
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read(item['size'] + 1)
            if len(data) != item['size'] or hashlib.sha256(data).hexdigest() != item['sha256']:
                raise ValueError('Upstream asset hash mismatch: '+item['path'])
            target.parent.mkdir(parents=True, exist_ok=True)
            temp = target.with_name(target.name+'.download')
            temp.write_bytes(data)
            temp.replace(target)
            return item['path']
        except Exception as error:
            last = error
            if attempt < 2:
                time.sleep(attempt + 1)
    raise last

if __name__ == '__main__':
    with ThreadPoolExecutor(max_workers=6) as pool:
        for path in pool.map(restore, manifest):
            print('Verified '+path)
