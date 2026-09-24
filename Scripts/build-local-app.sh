#!/bin/bash
set -euo pipefail

# Reproducible universal local build using the installed Command Line Tools.
# This produces a self-contained, ad-hoc signed app; it does not notarize it.
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_source="$task_root/MongrelWordProcessor"
task_output="${1:-$task_root/build/Confident-$(date +%Y%m%d-%H%M%S)}"
task_developer="/Library/Developer/CommandLineTools"
task_swift="$task_developer/usr/bin/swiftc"
task_sdk="$task_developer/SDKs/MacOSX.sdk"
task_app="$task_output/Mongrel Word Processor.app"

if [[ ! -x "$task_swift" || ! -d "$task_sdk" ]]; then
    echo "The macOS Command Line Tools compiler and SDK are required." >&2
    exit 1
fi
if [[ -e "$task_app" ]]; then
    echo "Choose a new output directory; an app already exists at $task_app" >&2
    exit 1
fi
mkdir -p "$task_output"
task_objects="$(mktemp -d "$task_output/.objects.XXXXXX")"
trap 'rm -rf "$task_objects"' EXIT
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
export DEVELOPER_DIR="$task_developer"
task_flags=(-O -swift-version 5 -strict-concurrency=complete -warnings-as-errors -sdk "$task_sdk")
read -r -a task_architectures <<< "${MONGREL_ARCHS:-arm64 x86_64}"
task_binaries=()
for task_arch in "${task_architectures[@]}"; do
    case "$task_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $task_arch" >&2; exit 1 ;; esac
    task_arch_objects="$task_objects/$task_arch"
    mkdir -p "$task_arch_objects"

"$task_swift" "${task_flags[@]}" -target "$task_arch-apple-macosx14.0" -emit-library -static -emit-module -module-name SharedFoundation \
    "$task_source"/Packages/SharedFoundation/Sources/SharedFoundation/UI/*.swift \
    -emit-module-path "$task_arch_objects/SharedFoundation.swiftmodule" \
    -o "$task_arch_objects/libSharedFoundation.a"

"$task_swift" "${task_flags[@]}" -target "$task_arch-apple-macosx14.0" -parse-as-library \
    -I "$task_arch_objects" -L "$task_arch_objects" -lSharedFoundation \
    "$task_source"/App/Models/*.swift "$task_source"/App/Services/*.swift \
    "$task_source"/App/ViewModels/*.swift "$task_source"/App/Views/*.swift \
    "$task_source"/App/Views/Editor/*.swift "$task_source/App/MongrelWordProcessorApp.swift" \
    -o "$task_arch_objects/MongrelWordProcessor"
task_binaries+=("$task_arch_objects/MongrelWordProcessor")
done
"$task_developer/usr/bin/lipo" -create "${task_binaries[@]}" -output "$task_app/Contents/MacOS/MongrelWordProcessor"

/usr/bin/ditto "$task_source/App/Resources" "$task_app/Contents/Resources"
python3 - "$task_source" "$task_app" "$task_output" <<'PY'
import datetime, hashlib, json, pathlib, plistlib, re, subprocess, sys
source, app, output = map(pathlib.Path, sys.argv[1:])
project = (source / 'project.yml').read_text()
version = re.search(r'MARKETING_VERSION: (\S+)', project)[1]
build = re.search(r'CURRENT_PROJECT_VERSION: (\S+)', project)[1]
values = {
    '$(EXECUTABLE_NAME)': 'MongrelWordProcessor',
    '$(PRODUCT_BUNDLE_IDENTIFIER)': 'com.mongrel.wordprocessor',
    '$(PRODUCT_NAME)': 'MongrelWordProcessor',
    '$(MARKETING_VERSION)': version,
    '$(CURRENT_PROJECT_VERSION)': build,
    '$(MACOSX_DEPLOYMENT_TARGET)': '14.0',
}
info = plistlib.loads((source / 'App/Info.plist').read_bytes())
for key, value in info.items():
    if isinstance(value, str):
        info[key] = values.get(value, value)
info['NSHighResolutionCapable'] = True
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app / 'Contents/PkgInfo').write_bytes(b'APPL????')
digest = hashlib.sha256()
paths = list((source / 'App').rglob('*')) + list((source / 'Packages/SharedFoundation/Sources').rglob('*'))
for path in sorted(p for p in paths if p.is_file() and p.name != '.DS_Store'):
    digest.update(str(path.relative_to(source)).encode())
    digest.update(b'\0')
    digest.update(path.read_bytes())
record = {
    'version': version, 'build': build,
    'architectures': subprocess.check_output(['/Library/Developer/CommandLineTools/usr/bin/lipo', '-archs', str(app / 'Contents/MacOS/MongrelWordProcessor')], text=True).split(),
    'minimumMacOS': '14.0',
    'builtAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'sourceSHA256': digest.hexdigest(),
    'gitRevision': subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
    'workingTreeHasChanges': bool(subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip()),
    'compiler': subprocess.check_output(['/Library/Developer/CommandLineTools/usr/bin/swiftc', '--version'], text=True).strip(),
    'signing': 'ad-hoc, hardened runtime, app sandbox', 'notarized': False,
}
(output / 'BuildRecord.json').write_text(json.dumps(record, indent=2) + '\n')
PY

/usr/bin/codesign --force --sign - --options runtime \
    --entitlements "$task_source/App/MongrelWordProcessor.entitlements" "$task_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$task_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_output/Mongrel Word Processor.zip"
(cd "$task_output" && /usr/bin/shasum -a 256 "Mongrel Word Processor.zip" > SHA256SUMS)
echo "Built: $task_app"
