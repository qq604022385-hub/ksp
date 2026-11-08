"""Retry a command only for transient native-dependency download responses."""
import re
import subprocess
import sys
import time

DOWNLOAD_FAILURE = re.compile(
    r'(?:Dependency download: HTTP|Native bundle download returned)\s+'
    r'(?:429|500|502|503|504)\b'
)


def run(command, attempts=4, delay=3):
    for attempt in range(1, attempts + 1):
        process = subprocess.Popen(
            command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding='utf-8', errors='replace',
        )
        transient_download_error = False
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            transient_download_error |= bool(DOWNLOAD_FAILURE.search(line))
        status = process.wait()
        if status == 0 or not transient_download_error or attempt == attempts:
            return status
        print(f'Native dependency download failed temporarily; retry {attempt}/{attempts - 1}.', flush=True)
        time.sleep(delay)
    raise AssertionError('unreachable')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        raise SystemExit('Usage: run_with_download_retry.py COMMAND [ARG ...]')
    raise SystemExit(run(sys.argv[1:]))
