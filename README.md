## FFmpeg XCFramework Builder

Scripts and CI to build static FFmpeg libraries for:
- iOS device (arm64)
- iOS simulator (arm64)
- macOS (arm64)

Outputs are packaged as XCFrameworks under `build/xcframework` without touching the upstream `ffmpeg/` source tree.

### Prerequisites
- macOS with Xcode command line tools (`clang`, `xcrun`, `xcodebuild`)
- Submodule `ffmpeg` checked out

### Quick start
```bash
# from repo root
chmod +x build_ffmpeg_xcframework.sh
./build_ffmpeg_xcframework.sh
```

Environment variables:
- `MIN_IOS_VERSION` (default `12.0`)
- `MIN_MACOS_VERSION` (default `11.0`)
- `JOBS` (defaults to logical CPU count)

### Outputs
- `build/src/<platform-arch>`: per-arch build trees
- `build/install/<platform-arch>`: installed static libs and headers
- `build/universal/iphonesimulator/lib`: fat simulator libs (arm64)
- `build/xcframework`: `lib*.xcframework`
- `build/logs`: configure/build logs

### CI release
On git tags, `.github/workflows/release.yml` builds and uploads as a GitHub Release asset.

### License
- Scripts and workflow files in this repository are licensed under MIT (see `LICENSE`).
- FFmpeg source and compiled artifacts follow FFmpeg’s own license terms; review the upstream FFmpeg license when redistributing binaries.
