#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

stage="${1:-all}"
case "$stage" in
    all|environment|project|fixtures|app|xcode|archive) ;;
    *) echo "Usage: bash scripts/ci-check.sh [all|environment|project|fixtures|app|xcode|archive]" >&2; exit 2 ;;
esac
mkdir -p .build/ci

check_environment() {
    sw_vers
    uname -m
    echo "Developer directory: ${DEVELOPER_DIR:-$(xcode-select -p)}"
    if ! xcodebuild -version; then
        echo "Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory." >&2
        return 1
    fi
    xcrun swiftc --version
    xcrun --sdk macosx --show-sdk-version
    python3 --version
    git rev-parse HEAD
}

check_project() {
    # Generate in a temporary copy so this check never overwrites local project edits.
    python3 - <<'PY'
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

root = Path.cwd()
with tempfile.TemporaryDirectory(prefix="project-", dir=root / ".build/ci") as temp:
    scratch = Path(temp)
    for folder in ("QRSnap", "QRSnapTests"):
        shutil.copytree(root / folder, scratch / folder)
    (scratch / "scripts").mkdir()
    generator = scratch / "scripts/generate-xcode-project.py"
    shutil.copy2(root / "scripts/generate-xcode-project.py", generator)
    subprocess.run([sys.executable, str(generator)], check=True)
    for generated in sorted((scratch / "QRSnap.xcodeproj").rglob("*")):
        if not generated.is_file():
            continue
        relative = generated.relative_to(scratch)
        committed = root / relative
        if not committed.is_file() or generated.read_bytes() != committed.read_bytes():
            sys.exit(f"Generated project is stale: {relative}. Run scripts/generate-xcode-project.py and commit the result.")
ET.parse(root / "QRSnap.xcodeproj/xcshareddata/xcschemes/QRSnap.xcscheme")
print("Generated project and shared scheme match the generator.")
PY
    plutil -lint QRSnap.xcodeproj/project.pbxproj QRSnap/App/Info.plist QRSnap/App/QRSnap.entitlements
}

check_fixtures() {
    # No --core-only fallback: unavailable Vision services must fail visibly.
    bash scripts/test.sh
}

verify_app() {
    local app_path="$1" audit_prefix="$2" require_runtime="${3:-yes}"
    codesign --verify --strict --verbose=2 "$app_path"
    codesign --display --verbose=4 "$app_path" 2>&1 | tee "${audit_prefix}-signature.log"
    codesign --display --entitlements - --xml "$app_path" > "${audit_prefix}-entitlements.plist"
    python3 - "$app_path" "$audit_prefix" "$require_runtime" <<'PY'
from pathlib import Path
import plistlib
import re
import sys

app, prefix, require_runtime = sys.argv[1:]
entitlements = plistlib.loads(Path(f"{prefix}-entitlements.plist").read_bytes())
if entitlements != {"com.apple.security.app-sandbox": True}:
    raise SystemExit("Unexpected signed entitlements; expected only App Sandbox.")
signature = Path(f"{prefix}-signature.log").read_text()
if "Signature=adhoc" not in signature:
    raise SystemExit("Expected an ad-hoc signature.")
if require_runtime == "yes" and not re.search(r"flags=.*\bruntime\b", signature):
    raise SystemExit("Expected Hardened Runtime.")
info = plistlib.loads((Path(app) / "Contents/Info.plist").read_bytes())
if info.get("LSMinimumSystemVersion") != "14.0":
    raise SystemExit("Expected the macOS 14.0 deployment floor.")
print(f"Verified {app}: ad-hoc signature, App Sandbox and macOS 14.0 deployment floor.")
if require_runtime == "yes":
    print("Verified Hardened Runtime.")
PY
}

check_app() {
    SIGNING_IDENTITY=- bash scripts/build-app.sh
    verify_app build/QRSnap.app .build/ci/app
}

check_xcode() {
    # A unique bundle path permits local reruns without deleting previous evidence.
    local result_dir
    result_dir="$(mktemp -d "$PWD/.build/ci/xcode-XXXXXX")"
    xcodebuild test \
        -project QRSnap.xcodeproj -scheme QRSnap -configuration Debug \
        -destination "platform=macOS,arch=$(uname -m)" \
        -derivedDataPath "$PWD/.build/ci/DerivedData" \
        -resultBundlePath "$result_dir/Tests.xcresult" \
        -parallel-testing-enabled NO \
        -test-timeouts-enabled YES \
        -default-test-execution-time-allowance 60 \
        -maximum-test-execution-time-allowance 120 \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-
}

check_archive() {
    local archive_dir archive_path app_path
    archive_dir="$(mktemp -d "$PWD/.build/ci/archive-XXXXXX")"
    archive_path="$archive_dir/QRSnap.xcarchive"
    app_path="$archive_path/Products/Applications/QRSnap.app"
    xcodebuild archive \
        -project QRSnap.xcodeproj -scheme QRSnap -configuration Release \
        -destination 'generic/platform=macOS' \
        -derivedDataPath "$PWD/.build/ci/ReleaseDerivedData" \
        -archivePath "$archive_path" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=-
    test -d "$app_path"
    # Audit Xcode's original entitlements before replacing its signature.
    # Xcode can disable Hardened Runtime with ad-hoc signing, even when configured.
    verify_app "$app_path" .build/ci/archive-original no
    echo "Applying the explicit ad-hoc Hardened Runtime signature to the archived app."
    codesign --force --sign - --options runtime \
        --entitlements QRSnap/App/QRSnap.entitlements "$app_path"
    verify_app "$app_path" .build/ci/archive-final
    # Preserve the executable permissions and bundle layout inside the artifact.
    ditto -c -k --keepParent "$app_path" "$archive_dir/QRSnap-adhoc-pr.zip"
    echo "Packaged verified Release app: $archive_dir/QRSnap-adhoc-pr.zip"
    echo "This is an ad-hoc PR test build, not a Developer ID/notarized release."
}

run_stage() {
    echo "::group::QRSnap CI: $1"
    "check_$1" 2>&1 | tee ".build/ci/$1.log"
    echo "::endgroup::"
}

if [[ "$stage" == all ]]; then
    for stage in environment project fixtures app xcode archive; do run_stage "$stage"; done
else
    run_stage "$stage"
fi
