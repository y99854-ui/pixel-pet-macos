#!/bin/bash
set -Eeuo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo '此入口用于 macOS 开发测试；Linux 开发环境可直接运行 swift test。'
    exit 1
fi
if ! swift_tool="$(xcrun --find swift 2>/dev/null)"; then
    echo '未找到 Swift 工具链。'
    exit 1
fi
mkdir -p .build
log="$PWD/.build/pixel-pet-tests-$(date +%Y%m%d-%H%M%S).log"
: > "$log"
tests_failed() {
    local status="$1"
    trap - ERR
    echo
    echo '单元测试未通过。完整日志：'
    echo "$log"
    if [[ -t 0 && "${PIXEL_PET_NONINTERACTIVE:-0}" != 1 ]]; then
        read -r -p '请保存上方错误，按回车结束。' || true
    fi
    exit "$status"
}
trap 'tests_failed $?' ERR
# Use the compiler for type checking; the swift runner does not support -typecheck.
swift_compiler="$(xcrun --find swiftc)"
swift_sdk="$(xcrun --show-sdk-path)"
# Report a missing developer test framework before compiling package tests.
if ! printf '%s\n' 'import XCTest' | "$swift_compiler" -sdk "$swift_sdk" -typecheck - 2>> "$log"; then
    echo '当前工具链没有 XCTest，无法执行开发单元测试。' | tee -a "$log"
    echo '运行宠物请使用 Start-Pixel-Pet.command。开发测试需要包含 XCTest 的完整 Xcode 工具链。' | tee -a "$log"
    echo '安装完整 Xcode 后，可执行 sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer 再重试。' | tee -a "$log"
    tests_failed 1
fi
"$swift_tool" test --build-system native --jobs 4 2>&1 | tee -a "$log"
echo "测试完成。完整日志：$log"
