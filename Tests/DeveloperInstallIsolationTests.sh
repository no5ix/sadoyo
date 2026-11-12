#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

set -euo pipefail
cd "$(dirname "$0")/.."
install_test_dir=$(mktemp -d)
trap 'command rm -rf "$install_test_dir"' EXIT

# Run the real installation block against disposable bundles. No process is
# stopped and no app under /Applications is read, removed or installed.
sed -n '/^if (( INSTALL )); then$/,$p' build.sh \
    | sed 's|/Applications|$install_test_dir/Applications|g' > "$install_test_dir/install.zsh"
[[ -s "$install_test_dir/install.zsh" ]]
mkdir -p "$install_test_dir/stage"
print new > "$install_test_dir/stage/content"
INSTALL=1
STAGE="$install_test_dir/stage"
stopped=()
signed=()
stop_process() { stopped+=("$1"); }
sign_installed_bundle() { signed+=("$1"); }

# Writes a bundle that carries a bundle identifier: the only proof the install
# block may act on a leftover.
fake_bundle() {
    local name="$1" identifier="$2"
    mkdir -p "$install_test_dir/Applications/$name.app/Contents"
    print original > "$install_test_dir/Applications/$name.app/content"
    if [[ -n "$identifier" ]]; then
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<plist version="1.0"><dict>' \
            "<key>CFBundleIdentifier</key><string>$identifier</string>" '</dict></plist>' \
            > "$install_test_dir/Applications/$name.app/Contents/Info.plist"
    fi
}

joinedStopped() { print -r -- "${(j: :)stopped}" }

for DEV in 1 0; do
    stopped=()
    signed=()
    rm -rf "$install_test_dir/Applications"
    mkdir -p "$install_test_dir/Applications"
    # The original Vorssaint installs and this fork's own retired-name
    # leftover, side by side. The neighbours carry the upstream identifier; the
    # leftover carries this build's, which is what makes it sweepable.
    fake_bundle 'Vorss' 'com.sadoyo.app'
    fake_bundle 'Vorssaint Utils' 'com.vorssaint.utils'
    fake_bundle 'Vorssaint' 'com.vorssaint.utils'
    if (( DEV )); then
        APP_NAME='Sadoyo (Developer)'
        EXECUTABLE=SadoyoDeveloper
        APP_BUNDLE_ID=com.sadoyo.app.dev
        fake_bundle 'Sadoyo' 'com.sadoyo.app'
    else
        APP_NAME=Sadoyo
        EXECUTABLE=Sadoyo
        APP_BUNDLE_ID=com.sadoyo.app
        fake_bundle 'Sadoyo (Developer)' 'com.sadoyo.app.dev'
    fi
    source "$install_test_dir/install.zsh"

    # The install lands, and lands only on its own name.
    [[ "$(cat "$install_test_dir/Applications/$APP_NAME.app/content")" == new ]]
    [[ "${signed[*]}" == "$install_test_dir/Applications/$APP_NAME.app" ]]
    # Coexistence: the original Vorssaint keeps its files and its processes.
    for neighbour in 'Vorssaint' 'Vorssaint Utils'; do
        [[ -e "$install_test_dir/Applications/$neighbour.app" ]]
        [[ "$(cat "$install_test_dir/Applications/$neighbour.app/content")" == original ]]
    done
    [[ "$(joinedStopped)" != *Vorssaint* ]]

    if (( DEV )); then
        # A Developer install stops nothing but itself, and touches no bundle
        # that is not its own — not even the official Sadoyo beside it.
        [[ "$(joinedStopped)" == SadoyoDeveloper ]]
        [[ "$(cat "$install_test_dir/Applications/Sadoyo.app/content")" == original ]]
        [[ -e "$install_test_dir/Applications/Vorss.app" ]]
    else
        # The official install retires only the leftover that carries its own
        # identifier, and leaves every neighbour install alone.
        [[ "$(joinedStopped)" == 'Sadoyo Vorss' ]]
        [[ ! -e "$install_test_dir/Applications/Vorss.app" ]]
        [[ "$(cat "$install_test_dir/Applications/Sadoyo (Developer).app/content")" == original ]]
    fi
done
print 'DEVELOPER INSTALL ISOLATION TESTS OK'
