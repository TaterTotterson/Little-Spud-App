#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd "$(dirname "$0")" && pwd -P)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
DERIVED_DATA="${LITTLE_SPUD_IOS_DERIVED_DATA:-${PROJECT_DIR}/build/DerivedData}"
DESTINATION="${LITTLE_SPUD_IOS_DESTINATION:-generic/platform=iOS Simulator}"
CONFIGURATION="${LITTLE_SPUD_IOS_CONFIGURATION:-Debug}"
CODE_SIGNING_ALLOWED="${LITTLE_SPUD_IOS_CODE_SIGNING_ALLOWED:-NO}"

xcodebuild \
  -project "${PROJECT_DIR}/LittleSpud.xcodeproj" \
  -scheme LittleSpud \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED}" \
  build
