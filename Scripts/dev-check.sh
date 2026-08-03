#!/usr/bin/env bash
#
# dev-check.sh
#
# Builds the package and runs the unit tests, printing only warnings,
# errors, and the test summary. Intended for quick local verification
# while iterating.
#
# Usage:
#   Scripts/dev-check.sh [--build-only]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUILD_ONLY=0
for arg in "$@"; do
  case "${arg}" in
    --build-only) BUILD_ONLY=1 ;;
    -h|--help)
      grep -E '^#( |$)' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//'
      exit 0
      ;;
    *) echo "Unknown argument: ${arg}" >&2; exit 1 ;;
  esac
done

echo "==> swift build"
swift build 2>&1 | grep -E "error:|warning:" | sort -u | head -60
BUILD_STATUS="${PIPESTATUS[0]}"

if [[ "${BUILD_STATUS}" -ne 0 ]]; then
  echo "==> build FAILED (exit ${BUILD_STATUS})"
  exit "${BUILD_STATUS}"
fi
echo "==> build OK"

if [[ "${BUILD_ONLY}" -eq 1 ]]; then
  exit 0
fi

echo "==> swift test"
swift test 2>&1 | grep -E "error:|failed|passed|Executed [0-9]+ test" | tail -20
exit "${PIPESTATUS[0]}"
