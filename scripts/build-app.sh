#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch_name="${ARCH:-$(uname -m)}"
case "$arch_name" in arm64|x86_64) ;; *) echo "Unsupported ARCH: $arch_name" >&2; exit 1 ;; esac
app_dir="$PWD/build/QRSnap.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources" "$PWD/.build/clang-module-cache"
source_files=()
while IFS= read -r -d '' path; do source_files+=("$path"); done < <(find QRSnap -name '*.swift' -print0)
xcrun swiftc -parse-as-library -swift-version 6 -target "$arch_name-apple-macosx14.0" \
    -module-name QRSnap -module-cache-path "$PWD/.build/clang-module-cache" \
    -O -g "${source_files[@]}" -o "$app_dir/Contents/MacOS/QRSnap"
cp QRSnap/App/Info.plist "$app_dir/Contents/Info.plist"
# Local ad-hoc signature by default. A supplied identity is used only on request.
codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime \
    --entitlements QRSnap/App/QRSnap.entitlements "$app_dir"
codesign --verify --strict --verbose=2 "$app_dir"
echo "Built $app_dir ($arch_name). Build does not launch the app."
