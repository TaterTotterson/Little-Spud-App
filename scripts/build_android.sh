#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANDROID_PROJECT_DIR="$PROJECT_DIR/android"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
  elif [[ -d "$HOME/Library/Android/sdk" ]]; then
    export ANDROID_HOME="$HOME/Library/Android/sdk"
  elif [[ -d "$HOME/Android/Sdk" ]]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
  else
    echo "Set ANDROID_HOME or ANDROID_SDK_ROOT to an Android SDK containing Platform 37." >&2
    exit 1
  fi
fi

cd "$ANDROID_PROJECT_DIR"
if [[ $# -eq 0 ]]; then
  exec ./gradlew :app:assembleDebug
fi
exec ./gradlew "$@"
