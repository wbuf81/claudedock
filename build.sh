#!/bin/bash
# Builds build/Claude Dock.app: a release binary in a minimal bundle, ad-hoc signed.
# Universal (Apple Silicon + Intel) when the toolchain can cross-compile, else native only.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Claude Dock.app"
# A copy running from this folder would lose its files mid-run: quit it, and reopen it after.
running="$PWD/$APP/Contents/MacOS/ClaudeDock"
reopen=0
if pgrep -f "$running" >/dev/null; then
  pkill -f "$running" || true
  reopen=1
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

binaries=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx14.0"
  if swift build -c release --triple "$triple" --product ClaudeDock; then
    # Every triple shares one output folder, so copy each binary out before the next build.
    cp "$(swift build -c release --triple "$triple" --show-bin-path)/ClaudeDock" "build/ClaudeDock-$arch"
    binaries+=("build/ClaudeDock-$arch")
  elif [ "$arch" = "$(uname -m)" ]; then
    echo "Build failed for $arch" >&2; exit 1
  else
    echo "Skipping $arch (cross-compiling isn't available here)"
  fi
done
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/ClaudeDock"
rm -f "${binaries[@]}"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeDock</string>
  <key>CFBundleDisplayName</key><string>Claude Dock</string>
  <key>CFBundleIdentifier</key><string>com.wbuf81.claudedock</string>
  <key>CFBundleExecutable</key><string>ClaudeDock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# The crab's animation frames.
mkdir -p "$APP/Contents/Resources"
cp -R Resources/crab "$APP/Contents/Resources/crab"

# Ad-hoc signed, but with a designated requirement of just the bundle id, so macOS keeps
# privacy permissions (like notifications) across rebuilds instead of tying them to each
# build's hash.
codesign --force --sign - --requirements '=designated => identifier "com.wbuf81.claudedock"' "$APP"
echo "Built $APP"
if [ "$reopen" = 1 ]; then
  open "$APP"
  echo "Reopened the running copy"
fi
