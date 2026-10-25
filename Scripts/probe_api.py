"""Read-only verification of the APK's public content protocol."""
from pathlib import Path
import json
import urllib.request
import urllib.parse
import time
import argparse

ROOT = Path(__file__).resolve().parents[1]


def crypt(data, key):
    key = key.encode('utf-8')
    if not key:
        raise ValueError('empty protocol key')
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 255
        s[i], s[j] = s[j], s[i]
    i = j = 0
    result = bytearray()
    for value in data:
        i = (i + 1) & 255
        j = (j + s[i]) & 255
        s[i], s[j] = s[j], s[i]
        t = s[i] + s[j]
        result.append(value ^ s[t & 255])
    return bytes(result)


def fetch(url):
    with urllib.request.urlopen(url, timeout=20) as response:
        return response.read(3_000_000)


def decode(data, key):
    text = data.decode('utf-8-sig').strip()
    if text.startswith(('{', '[')):
        return json.loads(text)
    return json.loads(crypt(bytes.fromhex(text), key).decode('utf-8'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', default='612536', help='Video ID for bounded read-only playback probes')
    args = parser.parse_args()
    research = ROOT/'Research'
    research.mkdir(exist_ok=True)
    bootstrap = fetch('https://app-1361125462.cos.ap-guangzhou.myqcloud.com/azapp2.json').decode().strip()
    resolver = bootstrap.rstrip('/') if bootstrap.startswith(('https://', 'http://')) else 'http://'+bootstrap
    settings = json.loads(fetch(resolver+'/extend/api/set.php?type=set'))['data']
    base = settings['pgdz'].rstrip('/')
    paths = {'category': '/api.php/localhost/Category',
             'movie': '/api.php/localhost/vod/?ac=list&class=movie&page=1',
             'search': '/api.php/localhost/So/?ac=list&zm='+urllib.parse.quote('测试')+'&page=1'}
    catalog_checks = {}
    for name, path in paths.items():
        raw = fetch(base+path)
        obj = decode(raw, settings['miyao'])
        (research/(name+'-decoded.json')).write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')
        catalog_checks[name] = {'decoded': True, 'items': len(obj) if isinstance(obj, list) else len(obj.get('data', []))}
    details = decode(fetch(base+'/api.php/localhost/vod/?ac=detail&ids='+urllib.parse.quote(args.id)), settings['miyao'])
    metadata = decode(details['player'].encode(), settings['miyao'])
    account, password = settings['rgdz'].split('#', 1)
    attempts = []
    for source in list(details['videolist'])[:3]:
        episode = details['videolist'][source][0]
        series = urllib.parse.quote_plus(details['title']+'-'+episode['title'])
        payload = '&account='+account+'&password='+password+'&series='+series+'&edition=2.9'
        form = urllib.parse.urlencode({'app': '10000', 'key': crypt(payload.encode(), settings['rck']).hex()}).encode()
        url = resolver+'/Client/?url='+urllib.parse.quote(episode['url'], safe='')
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, data=form), timeout=25).read(2_000_000)
            obj = decode(data, settings['miyao'])
            result = {'source': source, 'code': obj.get('code'), 'has_url': bool(obj.get('url')), 'response_keys': list(obj)}
            if obj.get('url'):
                headers = {k: v for k, v in {
                       'User-Agent': obj.get('UserAgent'), 'Referer': obj.get('Referer'),
                       'Origin': obj.get('Origin'), 'Cookie': obj.get('Cookie')}.items() if v}
                headers['Range'] = 'bytes=0-8191'
                req = urllib.request.Request(obj['url'], headers=headers)
                try:
                    with urllib.request.urlopen(req, timeout=15) as response:
                        sample = response.read(8192)
                        result.update({'media_http_status': response.status, 'hls_header': sample.startswith(b'#EXTM3U'),
                                       'media_content_type': response.headers.get('Content-Type')})
                except Exception as e:
                    result['media_error'] = type(e).__name__
            attempts.append(result)
            print('resolve', result)
        except Exception as e:
            attempts.append({'source': source, 'error': type(e).__name__})
    report = {'checked_at_unix': time.time(), 'bootstrap_http': 200, 'settings_http': 200,
              'catalog_checks': catalog_checks, 'detail_decoded': True, 'source_metadata_entries': len(metadata),
              'playback_probes': attempts, 'iphone_tested': False}
    (research/'live-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
