#!/usr/bin/env bash
# Rebuilds prebuilt/ from the pinned sea-g2p release.
# Needs rust (with the android and ios targets), cargo-ndk, ANDROID_NDK_HOME
# (or ANDROID_NDK_ROOT) and, for iOS, Xcode.
set -euo pipefail

TAG=v0.10.0
COMMIT=dae5ca83ea45f356c43bdb70a1bcd42e8729ff16
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${1:-$(mktemp -d)}"

if [ ! -d "$WORK/sea-g2p" ]; then
  git clone --depth 1 --branch "$TAG" https://github.com/pnnbao97/sea-g2p.git "$WORK/sea-g2p"
fi
cd "$WORK/sea-g2p"
[ "$(git rev-parse HEAD)" = "$COMMIT" ] || { echo "unexpected commit $(git rev-parse HEAD)" >&2; exit 1; }

export CARGO_PROFILE_RELEASE_STRIP=symbols
export CARGO_PROFILE_RELEASE_LTO=true
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1
FEATURES="--release --no-default-features --features capi"

# Android: 16 KB page alignment comes from NDK r28+ defaults.
cargo ndk -t arm64-v8a -t x86_64 -P 26 build $FEATURES
mkdir -p "$ROOT/prebuilt/android-arm64" "$ROOT/prebuilt/android-x64"
cp target/aarch64-linux-android/release/libsea_g2p_rs.so "$ROOT/prebuilt/android-arm64/"
cp target/x86_64-linux-android/release/libsea_g2p_rs.so "$ROOT/prebuilt/android-x64/"

# iOS device and simulator.
export IPHONEOS_DEPLOYMENT_TARGET=15.0
for pair in "aarch64-apple-ios:ios-arm64" "aarch64-apple-ios-sim:ios-sim-arm64"; do
  triple="${pair%%:*}"
  dir="$ROOT/prebuilt/${pair##*:}"
  cargo build $FEATURES --target "$triple"
  mkdir -p "$dir"
  cp "target/$triple/release/libsea_g2p_rs.dylib" "$dir/"
  install_name_tool -id @rpath/libsea_g2p_rs.dylib "$dir/libsea_g2p_rs.dylib"
done
