#!/bin/bash
set -euo pipefail
# Sign, notarize, and package an existing build. Credentials stay in Keychain.
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool Keychain profile.}"
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_output="$(cd "${1:?Pass the completed build directory.}" && pwd)"
task_app="$task_output/Mongrel Word Processor.app"
task_notary="${NOTARYTOOL_PATH:-/Applications/Xcode.app/Contents/Developer/usr/bin/notarytool}"
task_stapler="${STAPLER_PATH:-/Applications/Xcode.app/Contents/Developer/usr/bin/stapler}"
task_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$task_app/Contents/Info.plist")"
task_build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$task_app/Contents/Info.plist")"
task_stem="Mongrel-Word-Processor-$task_version-$task_build-macOS-universal"
task_work="$(mktemp -d "$task_output/.packaging.XXXXXX")"
trap 'rm -rf "$task_work"' EXIT
export DEVELOPER_DIR=/Library/Developer/CommandLineTools

notarize() {
    local archive="$1" record="$2"
    "$task_notary" submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json > "$record"
    python3 - "$record" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted: ' + str(result))
print('Notarization accepted:', result['id'])
PY
}

/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp --options runtime \
    --entitlements "$task_root/MongrelWordProcessor/App/MongrelWordProcessor.entitlements" "$task_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$task_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_work/Notarization.zip"
notarize "$task_work/Notarization.zip" "$task_output/AppNotarization.json"
"$task_stapler" staple "$task_app"
"$task_stapler" validate "$task_app"
/usr/sbin/spctl --assess --type execute --verbose=2 "$task_app"

mkdir -p "$task_work/image"
/usr/bin/ditto "$task_app" "$task_work/image/Mongrel Word Processor.app"
ln -s /Applications "$task_work/image/Applications"
cat > "$task_work/image/Install.txt" <<'TXT'
MONGREL WORD PROCESSOR

Requires macOS 14 Sonoma or later. Supports Apple Silicon and Intel Macs.

1. Drag Mongrel Word Processor into Applications.
2. Eject this disk image.
3. Open Mongrel Word Processor from Applications.

When replacing an older version, quit that version before copying the new one.
Your documents and recovered workspace are stored separately from the app.

The app is Developer ID signed and notarized by Apple. No account or subscription
is required. Prose, screenplay, source editing, and the bundled dictionary work
offline. LanguageTool integration is optional and uses a locally installed server.

The native document formats preserve Mongrel-specific formatting and metadata.
Use Export when sending PDF, Word, or other interchange copies.

Project and release notes: https://github.com/fwalterj/mongrel-word-processor
TXT
cp "$task_work/image/Install.txt" "$task_output/Install.txt"
/usr/bin/hdiutil create -volname "Mongrel Word Processor $task_version" -srcfolder "$task_work/image" \
    -format UDZO "$task_output/$task_stem.dmg"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$task_output/$task_stem.dmg"
notarize "$task_output/$task_stem.dmg" "$task_output/InstallerNotarization.json"
"$task_stapler" staple "$task_output/$task_stem.dmg"
"$task_stapler" validate "$task_output/$task_stem.dmg"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$task_output/$task_stem.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_output/$task_stem.zip"
# Replace the local-build archive with the same notarized app, never leave two signatures to confuse users.
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_output/Mongrel Word Processor.zip"
python3 - "$task_output" <<'PY'
import json, pathlib, sys
output = pathlib.Path(sys.argv[1])
record = json.loads((output / 'BuildRecord.json').read_text())
record.update(signing='Developer ID Application, hardened runtime, app sandbox', notarized=True)
record['notarizationSubmissionID'] = json.loads((output / 'AppNotarization.json').read_text())['id']
(output / 'BuildRecord.json').write_text(json.dumps(record, indent=2) + '\n')
PY
(cd "$task_output" && /usr/bin/shasum -a 256 "$task_stem.dmg" "$task_stem.zip" > SHA256SUMS)
echo "Shareable installer: $task_output/$task_stem.dmg"
