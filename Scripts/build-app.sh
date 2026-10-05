#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="$project_root/.build/WindowsTaskbar.app"
contents_path="$app_path/Contents"

cd "$project_root"
CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/swiftpm-cache" \
swift build --disable-sandbox

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$project_root/.build/debug/WindowsTaskbar" "$contents_path/MacOS/WindowsTaskbar"
cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$contents_path/Resources/AppIcon.icns"
signing_identity="${CODE_SIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --deep --sign - "$app_path"
else
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_path"
fi

echo "$app_path"
