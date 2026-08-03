#!/usr/bin/env bash
#
# build-local-app.sh
#
# Builds the Ledge Swift package in release mode and packages the
# resulting executable into a local, ad-hoc-signed Ledge.app bundle
# for personal use on this Mac. No App Store / notarization / signing
# credentials are required.
#
# Usage:
#   Scripts/build-local-app.sh [--open] [--install]
#
#   --open   Launch the freshly-built app after packaging.
#   --install Copy the app to ~/Applications/Ledge.app (replaces a prior
#             local Ledge.app, if present).
#
# The resulting bundle is written to build/Ledge.app relative to the
# repository root.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_NAME="Ledge"
BUNDLE_ID="io.github.brucez001.ledge"
EXECUTABLE_NAME="Ledge"

BUILD_DIR="${REPO_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="${REPO_ROOT}/Assets/AppIcon.icns"

OPEN_AFTER_BUILD=0
INSTALL_AFTER_BUILD=0
for arg in "$@"; do
  case "${arg}" in
    --open)
      OPEN_AFTER_BUILD=1
      ;;
    --install)
      INSTALL_AFTER_BUILD=1
      ;;
    -h|--help)
      grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//'
      exit 0
      ;;
    *)
      echo "Unknown argument: ${arg}" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Build in release mode
# ---------------------------------------------------------------------------

echo "==> Building ${APP_NAME} (release)"
cd "${REPO_ROOT}"
swift build -c release --product "${EXECUTABLE_NAME}"

BUILT_BINARY="$(swift build -c release --show-bin-path)/${EXECUTABLE_NAME}"

if [[ ! -x "${BUILT_BINARY}" ]]; then
  echo "error: expected built executable not found at ${BUILT_BINARY}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Assemble the .app bundle
# ---------------------------------------------------------------------------

echo "==> Packaging ${APP_BUNDLE}"
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BUILT_BINARY}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

if [[ ! -f "${ICON_SOURCE}" ]]; then
  echo "error: missing ${ICON_SOURCE}; run Scripts/generate-app-icon.sh" >&2
  exit 1
fi
cp "${ICON_SOURCE}" "${RESOURCES_DIR}/AppIcon.icns"

# macOS 26 resolves the icon of an app linked against the 26 SDK from a
# compiled asset catalogue; the .icns above only serves older systems. Compile
# one when actool (full Xcode) is available, otherwise warn and continue.
HAS_ASSET_CATALOG_ICON=0
if xcrun --find actool >/dev/null 2>&1; then
  echo "==> Compiling asset-catalogue icon"
  ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/ledge-actool.XXXXXX")"
  APPICONSET="${ICON_WORK}/Assets.xcassets/AppIcon.appiconset"
  mkdir -p "${APPICONSET}" "${ICON_WORK}/out"
  MASTER_PNG="${REPO_ROOT}/Assets/AppIcon.png"
  for size in 16 32 128 256 512; do
    sips -z "${size}" "${size}" "${MASTER_PNG}" \
      --out "${APPICONSET}/icon_${size}x${size}.png" >/dev/null
    double_size=$((size * 2))
    sips -z "${double_size}" "${double_size}" "${MASTER_PNG}" \
      --out "${APPICONSET}/icon_${size}x${size}@2x.png" >/dev/null
  done
  cat > "${APPICONSET}/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
  xcrun actool "${ICON_WORK}/Assets.xcassets" \
    --compile "${ICON_WORK}/out" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "${ICON_WORK}/partial.plist" >/dev/null
  if [[ -f "${ICON_WORK}/out/Assets.car" ]]; then
    cp "${ICON_WORK}/out/Assets.car" "${RESOURCES_DIR}/Assets.car"
    HAS_ASSET_CATALOG_ICON=1
  else
    echo "warning: actool produced no Assets.car; the icon may show as generic on macOS 26+." >&2
  fi
  rm -rf "${ICON_WORK}"
else
  echo "warning: actool not found (requires full Xcode); the icon may show as generic on macOS 26+." >&2
fi

APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}"

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Bruce Zhu.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- WebKit will ask macOS for capture access on behalf of a page (video
         calls, voice notes). Without these strings the system terminates the
         process instead of showing a prompt. -->
    <key>NSCameraUsageDescription</key>
    <string>Allows websites you open in ${APP_NAME} to use the camera, for example for video calls.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Allows websites you open in ${APP_NAME} to use the microphone, for example for calls and voice notes.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ "${HAS_ASSET_CATALOG_ICON}" -eq 1 ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "${CONTENTS_DIR}/Info.plist"
fi

# ---------------------------------------------------------------------------
# 3. Ad-hoc code sign so macOS is happy launching a local build
# ---------------------------------------------------------------------------

if command -v codesign >/dev/null 2>&1; then
  echo "==> Ad-hoc signing ${APP_BUNDLE}"
  codesign --force --sign - "${APP_BUNDLE}" || {
    echo "warning: ad-hoc codesign failed; the app may show a Gatekeeper prompt on first launch." >&2
  }
fi

echo "==> Built ${APP_BUNDLE}"

# ---------------------------------------------------------------------------
# 4. Optionally install a copy into ~/Applications
# ---------------------------------------------------------------------------

LAUNCH_BUNDLE="${APP_BUNDLE}"

if [[ "${INSTALL_AFTER_BUILD}" -eq 1 ]]; then
  LOCAL_APPLICATIONS_DIR="${HOME}/Applications"
  mkdir -p "${LOCAL_APPLICATIONS_DIR}"
  rm -rf "${LOCAL_APPLICATIONS_DIR}/${APP_NAME}.app"
  cp -R "${APP_BUNDLE}" "${LOCAL_APPLICATIONS_DIR}/${APP_NAME}.app"
  LAUNCH_BUNDLE="${LOCAL_APPLICATIONS_DIR}/${APP_NAME}.app"
  echo "==> Installed a copy to ${LOCAL_APPLICATIONS_DIR}/${APP_NAME}.app"
fi

if [[ "${OPEN_AFTER_BUILD}" -eq 1 ]]; then
  echo "==> Launching ${APP_NAME}"
  open "${LAUNCH_BUNDLE}"
fi

echo "Done."
