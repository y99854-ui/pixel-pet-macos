#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo '请在 macOS 12 或更新版本上构建。'
    exit 1
fi
if ! swift_tool="$(xcrun --find swift 2>/dev/null)"; then
    echo '请先运行 xcode-select --install 安装 Xcode 命令行工具，再重新运行此脚本。'
    exit 1
fi
mkdir -p .build
log="$PWD/.build/pixel-pet-build-$(date +%Y%m%d-%H%M%S).log"
: > "$log"
build_failed() {
    local status="$1"
    trap - ERR
    echo
    echo '构建失败，关键错误如下：'
    awk '/error:|failed|not found|No such file/ { print; count++; if (count >= 30) exit }' "$log"
    echo "完整日志：$log"
    if [[ -t 0 && "${PIXEL_PET_NONINTERACTIVE:-0}" != 1 ]]; then
        read -r -p '请复制上方错误或保存日志，按回车结束。' || true
    fi
    exit "$status"
}
trap 'build_failed $?' ERR
run_step() {
    local status=0
    "$@" 2>&1 | tee -a "$log" || status=$?
    if (( status != 0 )); then
        echo "error: 步骤失败（退出码 ${status}）：$*" | tee -a "$log"
        tail -n 15 "$log"
    fi
    return "$status"
}
run_step "$swift_tool" --version
# Use SwiftPM's native backend so packaging has a consistent resource layout.
# Command Line Tools can build the app without XCTest. Developer unit tests
# remain available in Test-Pixel-Pet.command and run separately in CI.
run_step "$swift_tool" build --build-system native --product PixelPet --jobs 4 -c release
bin_dir="$("$swift_tool" build --build-system native -c release --show-bin-path)"
app="$PWD/dist/Pixel Pet.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
run_step cp "$bin_dir/PixelPet" "$app/Contents/MacOS/PixelPet"
run_step cp "$PWD/Assets/PixelPet.icns" "$app/Contents/Resources/PixelPet.icns"
# SpriteCatalog explicitly loads the app's resource bundle without using the
# SwiftPM build-directory fallback, so a relocated .app remains self-contained.
run_step cp -R "$bin_dir/PixelPetMac_PixelPetCore.bundle" "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PixelPet</string>
<key>CFBundleIdentifier</key><string>io.github.y99854-ui.PixelPetMac</string>
<key>CFBundleName</key><string>Pixel Pet</string>
<key>CFBundleIconFile</key><string>PixelPet.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>6722</string>
<key>CFBundleVersion</key><string>6722</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
run_step plutil -lint "$app/Contents/Info.plist"
run_step codesign --force --deep --sign - "$app"
run_step codesign --verify --deep --strict "$app"
# Exercise packaged resources and real AppKit rendering without requiring XCTest.
run_step "$app/Contents/MacOS/PixelPet" --self-test
echo "构建完成：$app"
echo "完整日志：$log"
echo '双击应用启动，或复制到 Applications 文件夹。'
