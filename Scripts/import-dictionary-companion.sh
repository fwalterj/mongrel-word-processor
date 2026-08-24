#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_PACKAGE="${1:-$PROJECT_ROOT/../mongrel-dictionary/MongrelDictionary/App/Data/CompanionExports/MongrelDictionaryCompanionPackage}"
TARGET_ROOT="$PROJECT_ROOT/MongrelWordProcessor/App/Resources"
TARGET_PACKAGE="$TARGET_ROOT/MongrelDictionaryCompanionPackage"

if [[ ! -d "$SOURCE_PACKAGE" ]]; then
  echo "Dictionary companion package not found: $SOURCE_PACKAGE" >&2
  exit 1
fi

mkdir -p "$TARGET_ROOT"
rm -rf "$TARGET_PACKAGE"
mkdir -p "$TARGET_PACKAGE"

for filename in manifest.json README.txt spellcheck_dictionary.txt; do
  if [[ ! -f "$SOURCE_PACKAGE/$filename" ]]; then
    echo "Missing expected companion file: $SOURCE_PACKAGE/$filename" >&2
    exit 1
  fi
  cp "$SOURCE_PACKAGE/$filename" "$TARGET_PACKAGE/$filename"
done

echo "Imported Mongrel dictionary companion package into:"
echo "  $TARGET_PACKAGE"
