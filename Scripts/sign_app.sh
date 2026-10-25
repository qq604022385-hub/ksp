#!/bin/bash
set -euo pipefail
app="${1:?Pass the archived .app directory}"
test -d "$app"
test -n "${RUNNER_TEMP:-}" || { echo 'This helper is intended for an ephemeral GitHub macOS runner.'; exit 1; }
test -n "${IOS_CERTIFICATE_P12_BASE64:-}" || { echo 'Missing IOS_CERTIFICATE_P12_BASE64 secret'; exit 1; }
test -n "${IOS_PROVISION_PROFILE_BASE64:-}" || { echo 'Missing IOS_PROVISION_PROFILE_BASE64 secret'; exit 1; }
keydir="$(mktemp -d "$RUNNER_TEMP/kanke-sign.XXXXXX")"
keychain="$keydir/signing.keychain-db"
cleanup() {
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  case "$keydir" in "$RUNNER_TEMP"/kanke-sign.*) rm -rf "$keydir" ;; esac
}
trap cleanup EXIT
printf '%s' "$IOS_CERTIFICATE_P12_BASE64" | base64 --decode > "$keydir/certificate.p12"
printf '%s' "$IOS_PROVISION_PROFILE_BASE64" | base64 --decode > "$keydir/profile.mobileprovision"
keypass="$(openssl rand -hex 24)"
security create-keychain -p "$keypass" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keypass" "$keychain"
security import "$keydir/certificate.p12" -k "$keychain" -P "${IOS_CERTIFICATE_PASSWORD:-}" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keypass" "$keychain" >/dev/null
security cms -D -i "$keydir/profile.mobileprovision" -o "$keydir/profile.plist"
python3 - "$app/Info.plist" "$keydir/profile.plist" "$keydir/entitlements.plist" <<'PY'
import datetime, fnmatch, plistlib, sys
with open(sys.argv[1], 'rb') as f: bundle = plistlib.load(f)['CFBundleIdentifier']
with open(sys.argv[2], 'rb') as f: profile = plistlib.load(f)
expiry = profile['ExpirationDate'].replace(tzinfo=datetime.timezone.utc)
if expiry <= datetime.datetime.now(datetime.timezone.utc): raise SystemExit('Provisioning profile has expired')
entitlements = profile['Entitlements']
appid = entitlements['application-identifier']
prefix = appid.split('.', 1)[0]
actual = prefix + '.' + bundle
if not fnmatch.fnmatchcase(actual, appid): raise SystemExit('Profile App ID does not match the chosen bundle identifier')
entitlements['application-identifier'] = actual
if 'keychain-access-groups' in entitlements:
    entitlements['keychain-access-groups'] = [s.replace('*', bundle) for s in entitlements['keychain-access-groups']]
with open(sys.argv[3], 'wb') as f: plistlib.dump(entitlements, f)
PY
identity="$(security find-identity -v -p codesigning "$keychain" | awk '/[0-9A-F]{40}/ {print $2; exit}')"
# Some macOS awk versions need a character-count-independent pattern.
if test -z "$identity"; then identity="$(security find-identity -v -p codesigning "$keychain" | awk '/\) [A-F0-9]+ / {print $2; exit}')"; fi
test -n "$identity" || { echo 'No valid Apple code signing identity found in the imported certificate'; exit 1; }
cp "$keydir/profile.mobileprovision" "$app/embedded.mobileprovision"
codesign --force --sign "$identity" --keychain "$keychain" --entitlements "$keydir/entitlements.plist" --timestamp=none "$app"
codesign --verify --deep --strict "$app"
echo 'Signed with the provided Apple identity and matching provisioning profile.'
