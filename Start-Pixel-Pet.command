#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if [[ "$(uname -s)" != Darwin ]]; then
    echo 'Pixel Pet macOS 版需要 macOS 12 或更新版本。'
    exit 1
fi
if [[ ! -x 'dist/Pixel Pet.app/Contents/MacOS/PixelPet' ]]; then
    ./Build-Pixel-Pet.command
fi
open 'dist/Pixel Pet.app'
