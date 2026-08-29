#!/usr/bin/env bash
#
# package-release.sh
#
# Produces a distributable, notarised Ledge.dmg signed with a Developer ID
# Application certificate. Unlike Scripts/build-local-app.sh, this requires
# an Apple Developer Program membership: a Developer ID certificate in the
# keychain, plus notarisation credentials.
#
# Usage:
#   Scripts/package-release.sh [options]
#
#   --version X.Y.Z          Marketing version. Defaults to the current Git
#                            tag (v-prefix stripped), else 0.0.0-dev.
#   --identity NAME          Codesigning identity. Defaults to
#                            $LEDGE_SIGN_IDENTITY, else the first
#                            "Developer ID Application" identity in the
#                            keychain.
#   --keychain-profile NAME  notarytool profile created beforehand with
#                            `xcrun notarytool store-credentials`.
#   --skip-notarise          Build and sign, but do not submit to Apple. The
#                            result is NOT distributable; useful for dry runs.
#   --skip-verify            Skip the post-staple Gatekeeper assessment.
#   --adhoc                  Full dry run with no Apple credentials at all:
#                            ad-hoc signs and builds the disk image. Implies
#                            --skip-notarise and --skip-verify. The result is
#                            NOT distributable; use it to exercise packaging.
#
# Notarisation credentials, in order of precedence:
#   1. --keychain-profile NAME
#   2. $NOTARY_KEYCHAIN_PROFILE
#   3. $NOTARY_KEY_ID + $NOTARY_ISSUER_ID + $NOTARY_KEY_PATH (App Store
#      Connect API key; used by CI)
#
# Output:
#   build/Ledge-<version>.dmg

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="Ledge"
BUILD_DIR="${REPO_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

VERSION=""
IDENTITY="${LEDGE_SIGN_IDENTITY:-}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
SKIP_NOTARISE=0
SKIP_VERIFY=0
ADHOC=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2:?--version requires a value}"; shift 2 ;;
    --identity)
      IDENTITY="${2:?--identity requires a value}"; shift 2 ;;
    --keychain-profile)
      KEYCHAIN_PROFILE="${2:?--keychain-profile requires a value}"; shift 2 ;;
    --skip-notarise)
      SKIP_NOTARISE=1; shift ;;
    --skip-verify)
      SKIP_VERIFY=1; shift ;;
    --adhoc)
      ADHOC=1; SKIP_NOTARISE=1; SKIP_VERIFY=1; shift ;;
    -h|--help)
      grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# 1. Resolve the version
# ---------------------------------------------------------------------------

if [[ -z "${VERSION}" ]]; then
  if GIT_TAG="$(git describe --tags --exact-match 2>/dev/null)"; then
    VERSION="${GIT_TAG#v}"
  else
    VERSION="0.0.0-dev"
    echo "warning: no exact Git tag; falling back to ${VERSION}" >&2
  fi
fi

echo "==> Releasing ${APP_NAME} ${VERSION}"

# ---------------------------------------------------------------------------
# 2. Resolve the signing identity
# ---------------------------------------------------------------------------

if [[ "${ADHOC}" -eq 1 ]]; then
  IDENTITY="-"
  echo "warning: --adhoc dry run; the result is NOT distributable" >&2
fi

if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ -z "${IDENTITY}" ]]; then
  cat >&2 <<'MSG'
error: no "Developer ID Application" identity found in the keychain.

A distributable build needs an Apple Developer Program membership:
  1. Enrol at https://developer.apple.com/programs/
  2. Create a "Developer ID Application" certificate in Certificates,
     Identifiers & Profiles, and install it into your login keychain.
  3. Confirm it appears in: security find-identity -v -p codesigning

For an unsigned local build, use Scripts/build-local-app.sh instead.
To exercise this script's packaging without credentials, pass --adhoc.
MSG
  exit 1
fi

echo "==> Signing identity: ${IDENTITY}"

# ---------------------------------------------------------------------------
# 3. Build and sign the bundle
# ---------------------------------------------------------------------------

APP_VERSION="${VERSION}" \
APP_BUILD="${APP_BUILD:-$(date +%Y%m%d%H%M)}" \
LEDGE_SIGN_IDENTITY="${IDENTITY}" \
  "${SCRIPT_DIR}/build-local-app.sh"

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "error: expected ${APP_BUNDLE} after build" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 4. Assemble the disk image
# ---------------------------------------------------------------------------

DMG_PATH="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ledge-dmg.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT

echo "==> Building ${DMG_PATH}"
cp -R "${APP_BUNDLE}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "==> Signing ${DMG_PATH}"
if [[ "${IDENTITY}" == "-" ]]; then
  codesign --force --sign - "${DMG_PATH}"
else
  codesign --force --timestamp --sign "${IDENTITY}" "${DMG_PATH}"
fi

# ---------------------------------------------------------------------------
# 5. Notarise and staple
# ---------------------------------------------------------------------------

if [[ "${SKIP_NOTARISE}" -eq 1 ]]; then
  echo "==> Skipping notarisation (--skip-notarise)"
  echo "warning: ${DMG_PATH} is NOT notarised and will be blocked by Gatekeeper" >&2
else
  NOTARY_ARGS=()
  if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
    NOTARY_ARGS=(--keychain-profile "${KEYCHAIN_PROFILE}")
  elif [[ -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" && -n "${NOTARY_KEY_PATH:-}" ]]; then
    NOTARY_ARGS=(--key-id "${NOTARY_KEY_ID}" --issuer "${NOTARY_ISSUER_ID}" --key "${NOTARY_KEY_PATH}")
  else
    cat >&2 <<'MSG'
error: no notarisation credentials.

Locally, store them once:
  xcrun notarytool store-credentials "ledge" \
    --key-id <KEY_ID> --issuer <ISSUER_ID> --key /path/to/AuthKey.p8
then rerun with: --keychain-profile ledge

In CI, set NOTARY_KEY_ID, NOTARY_ISSUER_ID, and NOTARY_KEY_PATH.
Or pass --skip-notarise for a non-distributable dry run.
MSG
    exit 1
  fi

  echo "==> Submitting to Apple for notarisation (this can take several minutes)"
  xcrun notarytool submit "${DMG_PATH}" "${NOTARY_ARGS[@]}" --wait

  echo "==> Stapling"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
fi

# ---------------------------------------------------------------------------
# 6. Verify the way Gatekeeper will
# ---------------------------------------------------------------------------

if [[ "${SKIP_VERIFY}" -eq 0 && "${SKIP_NOTARISE}" -eq 0 ]]; then
  echo "==> Verifying"
  spctl --assess --type open --context context:primary-signature -v "${DMG_PATH}"
fi

echo
echo "==> ${DMG_PATH}"
shasum -a 256 "${DMG_PATH}"
echo "Done."
