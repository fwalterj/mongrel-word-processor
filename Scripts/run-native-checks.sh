#!/bin/bash
set -euo pipefail
# Fallback when the Xcode test runner is unavailable. Uses the actual test bodies.
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_source="$task_root/MongrelWordProcessor"
task_work="$(mktemp -d "${TMPDIR:-/tmp}/mongrel-native-checks.XXXXXX")"
trap 'rm -rf "$task_work"' EXIT
task_developer="/Library/Developer/CommandLineTools"
task_swift="$task_developer/usr/bin/swiftc"
task_flags=(-O -swift-version 5 -strict-concurrency=complete -sdk "$task_developer/SDKs/MacOSX.sdk")
export DEVELOPER_DIR="$task_developer"
"$task_swift" "${task_flags[@]}" -warnings-as-errors -emit-library -static -emit-module -module-name SharedFoundation \
    "$task_source"/Packages/SharedFoundation/Sources/SharedFoundation/UI/*.swift \
    -emit-module-path "$task_work/SharedFoundation.swiftmodule" -o "$task_work/libSharedFoundation.a"
cd "$task_source"
python3 "$task_root/Scripts/native-checks-harness.py" "$task_work/AllNativeChecks.swift"
"$task_swift" "${task_flags[@]}" -parse-as-library -I "$task_work" -L "$task_work" -lSharedFoundation \
    App/Models/*.swift App/Services/*.swift App/ViewModels/*.swift App/Views/*.swift App/Views/Editor/*.swift \
    "$task_work/AllNativeChecks.swift" -o "$task_work/NativeChecks"
export MONGREL_SAMPLE_DIRECTORY="${MONGREL_SAMPLE_DIRECTORY:-$task_root/screenplay_examples}"
"$task_work/NativeChecks"
