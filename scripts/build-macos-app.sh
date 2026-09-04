#!/usr/bin/env bash
set -euo pipefail

# Build a native WKWebView macOS app around the published DeepSeek Harness.
# This script must run on macOS with Xcode Command Line Tools installed.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="0.1.0-rc.6"
NODE_VERSION="22.19.0"
ARCH="${DEEPSEEK_MACOS_ARCH:-$(uname -m)}"
OUTPUT_DIR="${1:-${ROOT_DIR}/distribution/macos/dist}"
BUILD_ROOT="${ROOT_DIR}/distribution/macos/build"
APP_NAME="DeepSeek Desktop.app"
APP_PATH="${OUTPUT_DIR}/${APP_NAME}"
DMG_PATH="${OUTPUT_DIR}/DeepSeek-Desktop-${VERSION}-macOS-${ARCH}.dmg"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This builder must run on macOS (Darwin)." >&2
  exit 2
fi

for command in curl shasum tar swiftc sips iconutil hdiutil codesign; do
  command -v "$command" >/dev/null || {
    echo "Required macOS tool is missing: $command" >&2
    exit 2
  }
done

case "$ARCH" in
  arm64)
    NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-arm64.tar.gz"
    NODE_SHA256="c59006db713c770d6ec63ae16cb3edc11f49ee093b5c415d667bb4f436c6526d"
    ;;
  x86_64|x64)
    ARCH="x64"
    NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-x64.tar.gz"
    NODE_SHA256="3cfed4795cd97277559763c5f56e711852d2cc2420bda1cea30c8aa9ac77ce0c"
    ;;
  *)
    echo "Unsupported macOS architecture: $ARCH (use arm64 or x64)." >&2
    exit 2
    ;;
esac

if [[ -e "$APP_PATH" || -e "$DMG_PATH" ]]; then
  echo "Refusing to overwrite an existing macOS artifact in $OUTPUT_DIR" >&2
  exit 2
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-desktop-macos.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT
mkdir -p "$OUTPUT_DIR" "$BUILD_ROOT"

ARCHIVE_PATH="$WORK_ROOT/$NODE_ARCHIVE"
curl --fail --location --retry 3 --output "$ARCHIVE_PATH" \
  "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$NODE_SHA256" ]]; then
  echo "Node.js checksum mismatch: expected $NODE_SHA256, got $ACTUAL_SHA256" >&2
  exit 1
fi

tar -xzf "$ARCHIVE_PATH" -C "$WORK_ROOT"
NODE_ROOT="$WORK_ROOT/node-v${NODE_VERSION}-darwin-${ARCH}"

APP_CONTENTS="$WORK_ROOT/$APP_NAME/Contents"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_MACOS="$APP_CONTENTS/MacOS"
mkdir -p "$APP_RESOURCES/app" "$APP_RESOURCES/defaults" "$APP_RESOURCES/plugins" "$APP_MACOS"
ditto "$NODE_ROOT" "$APP_RESOURCES/runtime"

cp "$ROOT_DIR/distribution/macos/templates/DeepSeekDesktop.swift" "$WORK_ROOT/DeepSeekDesktop.swift"
cp "$ROOT_DIR/distribution/macos/templates/Info.plist" "$APP_CONTENTS/Info.plist"
sed -i '' "s/__VERSION__/${VERSION}/g" "$APP_CONTENTS/Info.plist"
cp "$ROOT_DIR/distribution/windows/templates/DeepSeek-Black-Logo.png" "$APP_RESOURCES/DeepSeek-Black-Logo.png"

ICONSET="$WORK_ROOT/DeepSeek.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  sips -z "$size" "$size" "$APP_RESOURCES/DeepSeek-Black-Logo.png" \
    --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double_size" "$double_size" "$APP_RESOURCES/DeepSeek-Black-Logo.png" \
    --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_RESOURCES/DeepSeek.icns"

cp "$ROOT_DIR/distribution/windows/templates/default-web.patch.yml" "$APP_RESOURCES/defaults/cordis.patch.yml"
for plugin in deepseek-desktop-free-fallback deepseek-desktop-vision-preflight deepseek-desktop-web-diagnostics dsh-vision-sidecar; do
  cp -R "$ROOT_DIR/distribution/windows/plugins/$plugin" "$APP_RESOURCES/plugins/$plugin"
done

cat > "$APP_RESOURCES/app/package.json" <<JSON
{
  "name": "deepseek-desktop-runtime",
  "version": "${VERSION}",
  "private": true,
  "dependencies": {
    "@deepseek-ai/dsh": "${VERSION}",
    "deepseek-desktop-free-fallback": "file:../plugins/deepseek-desktop-free-fallback",
    "deepseek-desktop-vision-preflight": "file:../plugins/deepseek-desktop-vision-preflight",
    "deepseek-desktop-web-diagnostics": "file:../plugins/deepseek-desktop-web-diagnostics",
    "dsh-vision-sidecar": "file:../plugins/dsh-vision-sidecar"
  }
}
JSON

PATH="$APP_RESOURCES/runtime/bin:$PATH" "$APP_RESOURCES/runtime/bin/npm" install \
  --omit=dev --no-audit --no-fund --package-lock=false --install-links
"$APP_RESOURCES/runtime/bin/node" "$APP_RESOURCES/app/node_modules/@deepseek-ai/dsh/lib/bin.js" --help >/dev/null

swiftc -O -framework Cocoa -framework WebKit \
  -o "$APP_MACOS/DeepSeek Desktop" "$WORK_ROOT/DeepSeekDesktop.swift"
chmod +x "$APP_MACOS/DeepSeek Desktop"

if [[ -n "${DEEPSEEK_MACOS_CODESIGN_IDENTITY:-}" ]]; then
  codesign --deep --force --options runtime --sign "$DEEPSEEK_MACOS_CODESIGN_IDENTITY" "$WORK_ROOT/$APP_NAME"
else
  codesign --deep --force --sign - "$WORK_ROOT/$APP_NAME"
fi

ditto "$WORK_ROOT/$APP_NAME" "$APP_PATH"

DMG_STAGE="$WORK_ROOT/dmg-stage"
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/$APP_NAME"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "DeepSeek Desktop" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null

echo "Created: $APP_PATH"
echo "Created: $DMG_PATH"
