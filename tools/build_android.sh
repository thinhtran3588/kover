#!/usr/bin/env bash
# Builds signed release APKs, one per ABI, named Kover-<version>+<build>-<abi>.apk.
#
# Each run bumps the build number in pubspec.yaml once the build succeeds.
# Signing comes from KOVER_KEYS_ENV (default ~/keys/kover-release.env), which
# exports KEYSTORE_PATH, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD and,
# optionally, SENTRY_DSN. Extra arguments go to `flutter build apk`, e.g.
# `--target-platform android-arm64` to build only that ABI. Set UNIVERSAL=1 to
# build a single APK with every ABI instead (Kover-<version>+<build>-universal.apk).
set -euo pipefail

cd "$(dirname "$0")/.."

keys_env="${KOVER_KEYS_ENV:-$HOME/keys/kover-release.env}"
if [[ ! -f "$keys_env" ]]; then
  echo "Signing config not found: $keys_env" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$keys_env"
: "${KEYSTORE_PATH:?missing in $keys_env}"
: "${KEYSTORE_PASSWORD:?missing in $keys_env}"
: "${KEY_ALIAS:?missing in $keys_env}"
: "${KEY_PASSWORD:?missing in $keys_env}"
export KEYSTORE_PATH KEYSTORE_PASSWORD KEY_ALIAS KEY_PASSWORD

version_line="$(grep -m1 '^version:' pubspec.yaml)"
if [[ ! "$version_line" =~ ^version:\ *([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+) ]]; then
  echo "Cannot parse '$version_line' in pubspec.yaml" >&2
  exit 1
fi
version="${BASH_REMATCH[1]}"
build=$((BASH_REMATCH[2] + 1))

defines=()
if [[ -n "${SENTRY_DSN:-}" ]]; then
  defines+=(--dart-define="SENTRY_DSN=$SENTRY_DSN")
fi

out=build/app/outputs/flutter-apk
rm -f "$out"/app-*release.apk

split=(--split-per-abi)
if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  split=()
fi

fvm flutter build apk --release ${split[@]+"${split[@]}"} \
  --build-name="$version" --build-number="$build" \
  ${defines[@]+"${defines[@]}"} "$@"

sed -i '' -E "s/^version: .*/version: $version+$build/" pubspec.yaml

for apk in "$out"/app-*release.apk; do
  abi="${apk#"$out"/app-}"
  abi="${abi%release.apk}"
  abi="${abi%-}"
  abi="${abi:-universal}"
  target="$out/Kover-$version+$build-$abi.apk"
  mv "$apk" "$target"
  echo "Built $target"
done
