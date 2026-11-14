"""Publish validated unsigned IPA from Actions; credentials are environment-only."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request


def request(method, url, token, data=None, content_type='application/json'):
    payload = json.dumps(data).encode() if data is not None and content_type == 'application/json' and not isinstance(data, (bytes, bytearray)) else data
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer '+token,
               'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': content_type,
               'User-Agent': 'Kanke-iOS-release'}
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, data=payload, headers=headers, method=method), timeout=180) as response:
                body=response.read()
                return json.loads(body) if body else None
        except urllib.error.HTTPError as error:
            if error.code < 500 or attempt == 2:
                raise
        time.sleep(2*(attempt+1))


def publish(version, files):
    repository=os.environ['GITHUB_REPOSITORY']
    commit=os.environ['GITHUB_SHA']
    token=os.environ['GH_TOKEN']
    assert re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository)
    assert re.fullmatch(r'\d+\.\d+\.\d+',version)
    tag='ios-v'+version
    api='https://api.github.com/repos/'+repository
    try:
        release=request('GET',api+'/releases/tags/'+tag,token)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        release=request('POST',api+'/releases',token,{
            'tag_name':tag,'target_commitish':commit,'name':'看客 iOS '+version,
            'draft':True,'prerelease':False,
            'body':f'看客 iOS {version}，未签名 IPA，安装前需要自行签名。\n\n'
                   '保留分类分区首页、竖屏全屏及实际分辨率显示，增加设备审批授权和动态来源管理。'
                   '看客可在授权后由手机解析，风暴继续服务端解析；视频直接连接第三方来源。\n\n'
                   '首次使用需在管理后台批准设备申请。看客上游仍可能返回空地址或403，未完成iPhone实机验收。\n\n'
                   f'源码提交：{commit}\n包含SHA-256校验文件与IPA结构检查结果。'})
    existing={asset['name']:asset for asset in release.get('assets',[])}
    upload=release['upload_url'].split('{',1)[0]
    for path in files:
        data=path.read_bytes()
        digest='sha256:'+hashlib.sha256(data).hexdigest()
        prior=existing.get(path.name)
        if prior:
            if prior.get('digest') == digest:
                print('Already uploaded:',path.name)
                continue
            if not release['draft']:
                raise RuntimeError('A published asset differs; refusing to overwrite '+path.name)
            request('DELETE',prior['url'],token)
        mime='application/octet-stream' if path.suffix == '.ipa' else 'application/json' if path.suffix == '.json' else 'text/plain'
        asset=request('POST',upload+'?'+urllib.parse.urlencode({'name':path.name}),token,data,mime)
        assert asset['state']=='uploaded' and asset['size']==len(data)
        if asset.get('digest'):
            assert asset['digest']==digest, 'Upload digest mismatch'
        print('Uploaded:',path.name,len(data),'bytes')
    if release['draft']:
        release=request('PATCH',api+'/releases/'+str(release['id']),token,{'draft':False,'make_latest':'true'})
    print('Published:',release['html_url'])
    summary=os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary,'a',encoding='utf-8') as stream:
            stream.write(f"[下载看客 iOS {version}（未签名）]({release['html_url']})\n")


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--version',required=True)
    parser.add_argument('files',nargs='+',type=Path)
    args=parser.parse_args()
    assert all(path.is_file() for path in args.files)
    publish(args.version,args.files)
