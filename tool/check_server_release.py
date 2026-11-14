"""Fail release preparation if a known legacy source/secret returns to client code."""
from pathlib import Path
import re

root=Path(__file__).resolve().parents[1]
forbidden=[b'cos.ap-guangzhou.myqcloud.com/azapp2', b'cos.ap-shanghai.myqcloud.com/A7F92C41',
           b'class KankeService',b'class StormService',b'licensed_credentials',b'ADMIN_PASSWORD_HASH']
files=[p for folder in ('lib','assets','ios/Runner','android/app/src') for p in (root/folder).rglob('*') if p.is_file()]
failures=[]
for path in files:
    data=path.read_bytes()
    if any(value in data for value in forbidden):failures.append(str(path.relative_to(root)))
assert not failures, 'Legacy configuration/credential in client: '+', '.join(failures)
assert not (root/'pubspec_overrides.yaml').exists(), 'Remove Windows QA-only dependency overrides before release.'
print('Release source check passed: no known source implementations or server credentials.')
