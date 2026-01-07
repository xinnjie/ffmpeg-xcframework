#!/usr/bin/env bash
set -euo pipefail

# Build FFmpeg static libraries for iOS (device + simulator) and package them as XCFrameworks.
# Outputs are kept under build/ to avoid touching the ffmpeg source tree.

ROOT="$(cd "$(dirname "$0")" && pwd)"
FFMPEG_SRC="$ROOT/ffmpeg"
BUILD_ROOT="$ROOT/build"
BUILD_DIR="$BUILD_ROOT/src"
INSTALL_DIR="$BUILD_ROOT/install"
UNIVERSAL_DIR="$BUILD_ROOT/universal"
XCFRAMEWORK_DIR="$BUILD_ROOT/xcframework"
LOG_DIR="$BUILD_ROOT/logs"

MIN_IOS_VERSION="${MIN_IOS_VERSION:-12.0}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-11.0}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu)}"

DEVICE_ARCHS=("arm64")
SIM_ARCHS=("arm64")
# Optional macOS slices
MAC_ARCHS=("arm64")

FF_LIBS=(avcodec avdevice avfilter avformat avutil swresample swscale)

ensure_dirs() {
  mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$UNIVERSAL_DIR/iphonesimulator/lib" "$XCFRAMEWORK_DIR" "$LOG_DIR"
}

configure_and_build() {
  local platform="$1" arch="$2"
  shift 2

  local sdk cflags ldflags min_flag workdir prefix log
  local -a extra_args=()
  if (($#)); then
    extra_args+=("$@")
  fi

  sdk="$(xcrun --sdk "$platform" --show-sdk-path)"
  if [[ ! -d "$sdk" ]]; then
    echo "SDK not found for $platform" >&2
    exit 1
  fi

  if [[ "$platform" == "iphoneos" ]]; then
    min_flag="-mios-version-min=${MIN_IOS_VERSION}"
  elif [[ "$platform" == "iphonesimulator" ]]; then
    min_flag="-mios-simulator-version-min=${MIN_IOS_VERSION}"
  else
    min_flag="-mmacosx-version-min=${MIN_MACOS_VERSION}"
  fi

  cflags="-arch ${arch} ${min_flag}"
  ldflags="-arch ${arch} ${min_flag}"

  # Bitcode is only relevant for iOS targets
  if [[ "$platform" != "macosx" ]]; then
    cflags+=" -fembed-bitcode"
  fi

  workdir="$BUILD_DIR/${platform}-${arch}"
  prefix="$INSTALL_DIR/${platform}-${arch}"
  log="$LOG_DIR/${platform}-${arch}.log"

  mkdir -p "$workdir" "$prefix"

  pushd "$workdir" >/dev/null
  if [[ "$arch" == "x86_64" ]] && ! command -v nasm >/dev/null 2>&1; then
    echo "nasm not found; building $platform $arch with --disable-x86asm" | tee -a "$log"
    extra_args+=("--disable-x86asm")
  fi

  local -a cfg_args=(
    --arch="$arch"
    --target-os=darwin
    --cc="xcrun -sdk ${platform} clang"
    --sysroot="$sdk"
    --enable-cross-compile
    --enable-pic
    --enable-static
    --disable-shared
    --disable-programs
    --disable-doc
    --disable-debug
    --prefix="$prefix"
    --extra-cflags="$cflags"
    --extra-ldflags="$ldflags"
  )
  if ((${#extra_args[@]})); then
    cfg_args+=("${extra_args[@]}")
  fi

  "$FFMPEG_SRC/configure" "${cfg_args[@]}" 2>&1 | tee "$log"

  make -j"$JOBS" 2>&1 | tee -a "$log"
  make install 2>&1 | tee -a "$log"
  popd >/dev/null
}

create_simulator_fat_libs() {
  local lib
  for lib in "${FF_LIBS[@]}"; do
    local inputs=()
    local arch
    for arch in "${SIM_ARCHS[@]}"; do
      local src="$INSTALL_DIR/iphonesimulator-${arch}/lib/lib${lib}.a"
      if [[ -f "$src" ]]; then
        inputs+=("$src")
      fi
    done
    if [[ ${#inputs[@]} -eq 0 ]]; then
      echo "No simulator binaries found for lib${lib}.a" >&2
      exit 1
    fi
    local out="$UNIVERSAL_DIR/iphonesimulator/lib/lib${lib}.a"
    if [[ ${#inputs[@]} -eq 1 ]]; then
      cp -f "${inputs[0]}" "$out"
    else
      lipo -create "${inputs[@]}" -output "$out"
    fi
  done
}

create_xcframeworks() {
  local lib
  for lib in "${FF_LIBS[@]}"; do
    local device_lib="$INSTALL_DIR/iphoneos-arm64/lib/lib${lib}.a"
    local device_headers="$INSTALL_DIR/iphoneos-arm64/include"
    local sim_lib="$UNIVERSAL_DIR/iphonesimulator/lib/lib${lib}.a"
    local sim_headers="$INSTALL_DIR/iphonesimulator-arm64/include"
    local mac_lib="$INSTALL_DIR/macosx-arm64/lib/lib${lib}.a"
    local mac_headers="$INSTALL_DIR/macosx-arm64/include"

    if [[ ! -f "$device_lib" ]]; then
      echo "Missing device library: $device_lib" >&2
      exit 1
    fi
    if [[ ! -f "$sim_lib" ]]; then
      echo "Missing simulator library: $sim_lib" >&2
      exit 1
    fi

    local xc_args=(
      -create-xcframework
      -library "$device_lib" -headers "$device_headers"
      -library "$sim_lib" -headers "$sim_headers"
    )

    if [[ -f "$mac_lib" ]]; then
      xc_args+=(-library "$mac_lib" -headers "$mac_headers")
    fi

    xc_args+=(-output "$XCFRAMEWORK_DIR/lib${lib}.xcframework")

    xcodebuild "${xc_args[@]}"
  done
}

main() {
  ensure_dirs

  local arch
  for arch in "${DEVICE_ARCHS[@]}"; do
    configure_and_build "iphoneos" "$arch"
  done
  for arch in "${SIM_ARCHS[@]}"; do
    configure_and_build "iphonesimulator" "$arch"
  done
  for arch in "${MAC_ARCHS[@]}"; do
    configure_and_build "macosx" "$arch"
  done

  create_simulator_fat_libs
  create_xcframeworks

  echo "Done. XCFrameworks are under: $XCFRAMEWORK_DIR"
}

main "$@"
