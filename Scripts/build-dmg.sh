#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_root/Resources/Info.plist")"
version="${WINDOWS_TASKBAR_VERSION:-$plist_version}"
if [[ "$version" != "$plist_version" ]]; then
    echo "WINDOWS_TASKBAR_VERSION ($version) must match CFBundleShortVersionString ($plist_version)." >&2
    exit 2
fi
dist_path="$project_root/dist"
dmg_path="$dist_path/WindowsTaskbar-$version.dmg"
staging_path="$(mktemp -d "${TMPDIR:-/tmp}/windows-taskbar-dmg.XXXXXX")"

cleanup() {
    rm -rf "$staging_path"
}
trap cleanup EXIT

"$project_root/Scripts/build-app.sh"

mkdir -p "$dist_path"
cp -R "$project_root/.build/WindowsTaskbar.app" "$staging_path/Windows Taskbar.app"
ln -s /Applications "$staging_path/Applications"
rm -f "$dmg_path"

diskutil image create from \
    --volumeName "Windows Taskbar" \
    --format UDZO \
    "$staging_path" \
    "$dmg_path"

echo "$dmg_path"
