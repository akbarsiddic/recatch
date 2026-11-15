#!/usr/bin/env bash
# Build a real ReCatch.app. A bare SwiftPM binary has no bundle id, no Info.plist and no
# stable TCC identity — which is exactly why permissions never stuck.
#
#   ./Scripts/make-app.sh            # release build into build/ReCatch.app
#   ./Scripts/make-app.sh debug      # debug build
#   ./Scripts/make-app.sh release run  # build, then launch it
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ACTION="${2:-}"
APP="build/ReCatch.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ReCatch" "$APP/Contents/MacOS/ReCatch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "    (no icon yet — run: python3 Scripts/make-icon.py)"
fi

# Ad-hoc signature gives the bundle a stable identity so macOS remembers the
# Microphone / Screen Recording grants across launches.
echo "==> signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
  echo "    (codesign skipped — permissions may be asked again after rebuilds)"

echo "==> done: $(pwd)/$APP"
if [[ "$ACTION" == "run" ]]; then
  pkill -f "ReCatch.app/Contents/MacOS/ReCatch" 2>/dev/null || true
  open "$APP"
  echo "    launched. Look for the waveform in the menu bar."
fi
