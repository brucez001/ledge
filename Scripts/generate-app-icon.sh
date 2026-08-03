#!/usr/bin/env bash
#
# Regenerates the README PNG and ICNS app icon from Assets/AppIcon.svg.
#
# Requirements: macOS `sips` and `iconutil` (both ship with macOS).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ASSETS_DIR="${REPO_ROOT}/Assets"
SOURCE="${ASSETS_DIR}/AppIcon.svg"
PNG="${ASSETS_DIR}/AppIcon.png"
README_PNG="${ASSETS_DIR}/AppIcon-256.png"
ICNS="${ASSETS_DIR}/AppIcon.icns"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ledge-app-icon.XXXXXX")"
MASTER_PNG="${WORK_DIR}/AppIcon.png"
TEMP_README_PNG="${WORK_DIR}/AppIcon-256.png"
TEMP_ICNS="${WORK_DIR}/AppIcon.icns"
ICONSET="${WORK_DIR}/AppIcon.iconset"

trap 'rm -rf "${WORK_DIR}"' EXIT
mkdir -p "${ICONSET}"

if [[ ! -f "${SOURCE}" ]]; then
  echo "error: missing ${SOURCE}" >&2
  exit 1
fi

# Build everything in a temporary directory. The committed assets are replaced
# only after every render and iconutil step succeeds.
echo "==> Rendering app icon"
sips -s format png "${SOURCE}" --out "${MASTER_PNG}" >/dev/null

WIDTH="$(sips -g pixelWidth "${MASTER_PNG}" | awk '/pixelWidth/ {print $2}')"
HEIGHT="$(sips -g pixelHeight "${MASTER_PNG}" | awk '/pixelHeight/ {print $2}')"
if [[ "${WIDTH}" != "1024" || "${HEIGHT}" != "1024" ]]; then
  echo "error: expected a 1024x1024 master, got ${WIDTH}x${HEIGHT}" >&2
  exit 1
fi

sips -z 256 256 "${MASTER_PNG}" --out "${TEMP_README_PNG}" >/dev/null

for size in 16 32 128 256 512; do
  sips -z "${size}" "${size}" "${MASTER_PNG}" \
    --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "${double_size}" "${double_size}" "${MASTER_PNG}" \
    --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Building ICNS"
iconutil -c icns "${ICONSET}" -o "${TEMP_ICNS}"

mv "${MASTER_PNG}" "${PNG}"
mv "${TEMP_README_PNG}" "${README_PNG}"
mv "${TEMP_ICNS}" "${ICNS}"
echo "Done."
