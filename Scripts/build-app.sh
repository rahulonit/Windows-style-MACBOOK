#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
app_path="$project_root/.build/WindowsTaskbar.app"
contents_path="$app_path/Contents"
build_configuration="${BUILD_CONFIGURATION:-release}"
compatible_sdk="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
if [[ -n "${SDKROOT:-}" ]]; then
    sdk_root="$SDKROOT"
elif [[ -d "$compatible_sdk" ]]; then
    sdk_root="$compatible_sdk"
else
    sdk_root="$(xcrun --sdk macosx --show-sdk-path)"
fi
swift_bin="$(xcrun --find swift)"
swift_plugin_path="${swift_bin:h:h}/lib/swift/host/plugins"
swift_plugin_args=()

for plugin in libSwiftMacros.dylib libObservationMacros.dylib; do
    if [[ -f "$swift_plugin_path/$plugin" ]]; then
        swift_plugin_args+=(
            -Xswiftc -load-plugin-library
            -Xswiftc "$swift_plugin_path/$plugin"
        )
    fi
done

if [[ "$build_configuration" != "debug" && "$build_configuration" != "release" ]]; then
    echo "BUILD_CONFIGURATION must be 'debug' or 'release'." >&2
    exit 2
fi

cd "$project_root"
CLANG_MODULE_CACHE_PATH="$project_root/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/swiftpm-cache" \
SDKROOT="$sdk_root" \
swift build --disable-sandbox --configuration "$build_configuration" "${swift_plugin_args[@]}"

rm -rf "$app_path"
mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
cp "$project_root/.build/$build_configuration/WindowsTaskbar" "$contents_path/MacOS/WindowsTaskbar"
cp "$project_root/Resources/Info.plist" "$contents_path/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$contents_path/Resources/AppIcon.icns"
signing_identity="${CODE_SIGN_IDENTITY:--}"
if [[ "$signing_identity" == "-" ]]; then
    echo "warning: creating an ad-hoc signature; Accessibility permission will not survive binary updates" >&2
    codesign --force --deep --sign - "$app_path"
else
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_path"
fi

echo "$app_path"
