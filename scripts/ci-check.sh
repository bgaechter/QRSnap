#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

stage="${1:-all}"
case "$stage" in
    all|environment|project|fixtures|app|xcode) ;;
    *) echo "Usage: bash scripts/ci-check.sh [all|environment|project|fixtures|app|xcode]" >&2; exit 2 ;;
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

check_app() {
    SIGNING_IDENTITY=- bash scripts/build-app.sh
    codesign --verify --strict --verbose=2 build/QRSnap.app
    codesign --display --verbose=4 build/QRSnap.app 2>&1 | tee .build/ci/signature-details.log
    codesign --display --entitlements - --xml build/QRSnap.app > .build/ci/entitlements.plist
    python3 - <<'PY'
from pathlib import Path
import plistlib
import re

entitlements = plistlib.loads(Path(".build/ci/entitlements.plist").read_bytes())
if entitlements != {"com.apple.security.app-sandbox": True}:
    raise SystemExit("Unexpected signed entitlements; expected only App Sandbox.")
signature = Path(".build/ci/signature-details.log").read_text()
if not re.search(r"flags=.*\bruntime\b", signature) or "Signature=adhoc" not in signature:
    raise SystemExit("Expected an ad-hoc signature with Hardened Runtime.")
info = plistlib.loads(Path("build/QRSnap.app/Contents/Info.plist").read_bytes())
if info.get("LSMinimumSystemVersion") != "14.0":
    raise SystemExit("Expected the macOS 14.0 deployment floor.")
print("Verified ad-hoc signature, App Sandbox, Hardened Runtime and declared deployment floor.")
PY
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

run_stage() {
    echo "::group::QRSnap CI: $1"
    "check_$1" 2>&1 | tee ".build/ci/$1.log"
    echo "::endgroup::"
}

if [[ "$stage" == all ]]; then
    for stage in environment project fixtures app xcode; do run_stage "$stage"; done
else
    run_stage "$stage"
fi
