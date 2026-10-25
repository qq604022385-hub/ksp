#!/bin/bash
set -euo pipefail
app="${1:?Pass archived .app path}"
signed="${2:-false}"
test -f "$app/Info.plist"
test -f "$app/Kanke"
mkdir -p build/packaging/Payload build/output
ditto "$app" build/packaging/Payload/Kanke.app
name=Kanke-unsigned.ipa
if test "$signed" = true; then
  codesign --verify --deep --strict "$app"
  name=Kanke-signed.ipa
fi
ditto -c -k --keepParent build/packaging/Payload "build/output/$name"
python3 Scripts/validate_ipa.py "build/output/$name" "$signed"
shasum -a 256 "build/output/$name" > build/output/SHA256SUMS.txt
{
  echo "Artifact: $name"
  echo "Signed with supplied Apple identity: $signed"
  echo "Minimum iOS: 16.0"
  echo "Commit: ${GITHUB_SHA:-local}"
  echo "Built UTC: $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo 'An unsigned IPA requires signing before installation on an iPhone.'
  echo 'Packaging validation is not physical-device playback acceptance.'
} > build/output/BUILD-INFO.txt
