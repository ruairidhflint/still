#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release -debug-info-format none --disable-sandbox --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security
binary_directory=$(swift build -c release --show-bin-path --scratch-path .build --cache-path .build/cache --config-path .build/config --security-path .build/security)
mkdir -p dist/Still.app/Contents/MacOS dist/Still.app/Contents/Resources
cp "$binary_directory/Still" dist/Still.app/Contents/MacOS/Still.new
mv -f dist/Still.app/Contents/MacOS/Still.new dist/Still.app/Contents/MacOS/Still
cp Resources/Info.plist dist/Still.app/Contents/Info.plist
swift scripts/Icon.swift .build/AppIcon.iconset dist/Still.app/Contents/Resources/AppIcon.icns
cp .build/AppIcon.iconset/icon_512x512@2x.png dist/Still.app/Contents/Resources/AppIcon.png
codesign --force --sign - dist/Still.app
touch dist/Still.app
printf 'Built %s/dist/Still.app\n' "$PWD"
