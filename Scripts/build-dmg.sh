#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
version="${WINDOWS_TASKBAR_VERSION:-0.3.0}"
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
