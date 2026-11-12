// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure helpers for the self-update installer: the shell script text, the
/// quoting for its elevated (admin) variant and the parsing of the result
/// marker the script leaves behind. No AppKit, so the unit tests cover the
/// quoting and the script's failure-reporting contract.
enum UpdateInstallerSupport {
    /// Marker the script writes before each fallible step (write-ahead, so
    /// the marker names the failing step even if the script dies mid-way)
    /// and replaces with "ok" once the new bundle is in place.
    static func installFailureCode(fromMarker marker: String) -> String? {
        let trimmed = marker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("fail") else { return nil }
        return trimmed
    }

    /// The Developer ID team whose certificate a published Sadoyo release must
    /// carry, for the updater's signature requirement. Empty by default: this
    /// fork has no Apple-issued identity of its own, so the updater pins the
    /// bundle identifier (below) and leaves the developer trust to Gatekeeper's
    /// notarization assessment. A publisher with a Developer ID puts its team id
    /// here and the requirement tightens to that team as well.
    static let publishingTeamID = ""

    /// The requirement the downloaded DMG must satisfy. The bundle inside it is
    /// checked for this app's own identifier below, and Gatekeeper's
    /// notarization assessment vouches for the publisher, so the team pin is
    /// optional. Built as one string so the script states it once.
    static var dmgVerifyRequirement: String {
        publishingTeamID.isEmpty
            ? "anchor apple generic"
            : "anchor apple generic and certificate leaf[subject.OU] = \"\(publishingTeamID)\""
    }

    /// The requirement the app staged from the DMG must satisfy: this app's own
    /// identifier, plus the publishing team when this fork has one. A neighbour's
    /// bundle can never satisfy it, which is what keeps an upstream release from
    /// being installed over Sadoyo.
    static func stagedVerifyRequirement(expectedBundleIdentifier: String) -> String {
        var requirement = "identifier \"\(expectedBundleIdentifier)\" and anchor apple generic"
        if !publishingTeamID.isEmpty {
            requirement += " and certificate leaf[subject.OU] = \"\(publishingTeamID)\""
        }
        return requirement
    }

    /// The installer: waits for the app to exit, verifies and mounts the DMG,
    /// stages and verifies the new bundle, swaps it in and relaunches.
    /// Arguments: $1 app path, $2 dmg path, $3 pid to wait for,
    /// $4 result marker path, $5 uid to relaunch as (used when running as
    /// root, where a plain `open` could launch the app as root), $6 expected
    /// version from the trusted release tag, $7 this app's bundle identifier,
    /// $8 the code requirement the staged bundle has to satisfy.
    static func installerScript() -> String {
        """
        #!/bin/sh
        APP="$1"; DMG="$2"; PID="$3"; RESULT="$4"; ASUSER="$5"; EXPECTED_VERSION="$6"; EXPECTED_ID="$7"; REQUIREMENT="$8"
        SCRIPT="$0"
        # Write-ahead markers go to a progress file; only a FINISHED run
        # promotes it to the real marker. The app may relaunch while this
        # script is still mid-install, and a transient step must not be
        # reported as a failure.
        running_as_root() { [ "$(/usr/bin/id -u)" = "0" ]; }
        note() {
            if running_as_root; then
                [ -n "$ASUSER" ] || return 1
                # The marker directory belongs to the user. Drop privileges
                # before opening it so a replaced path cannot make root follow
                # a symlink while the administrator prompt is on screen.
                /usr/bin/sudo -n -u "#$ASUSER" /bin/sh -c \
                    '/bin/echo "$1" > "$2.progress"' marker "$1" "$RESULT" 2>/dev/null
                return
            fi
            /bin/echo "$1" > "$RESULT.progress" 2>/dev/null
        }
        finalize() {
            if running_as_root; then
                [ -n "$ASUSER" ] || return 1
                /usr/bin/sudo -n -u "#$ASUSER" /bin/mv -f \
                    "$RESULT.progress" "$RESULT" 2>/dev/null
                return
            fi
            /bin/mv -f "$RESULT.progress" "$RESULT" 2>/dev/null
        }
        cleanup_script() { case "$SCRIPT" in /*) /bin/rm -f "$SCRIPT";; esac; }
        relaunch() {
            if [ -n "$ASUSER" ] && [ "$(/usr/bin/id -u)" = "0" ]; then
                /bin/launchctl asuser "$ASUSER" /usr/bin/open "$1" && return
            fi
            /usr/bin/open "$1"
        }
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        note fail-dmg-verify
        # The DMG has to be a complete, intact signed bundle. The app inside is
        # checked for this app's own identifier below, and Gatekeeper's
        # notarization assessment is what vouches for the publisher.
        DMG_VERIFY_REQ='\(dmgVerifyRequirement)'
        if ! /usr/bin/codesign -v --strict -R="$DMG_VERIFY_REQ" "$DMG" 2>/dev/null; then
            /bin/rm -f "$DMG"
            finalize
            relaunch "$APP"
            cleanup_script
            exit 1
        fi
        note fail-tempdir
        MNT="$(/usr/bin/mktemp -d)" || { /bin/rm -f "$DMG"; finalize; relaunch "$APP"; cleanup_script; exit 1; }
        note fail-mount
        if ! /usr/bin/hdiutil attach "$DMG" -nobrowse -quiet -mountpoint "$MNT"; then
            /bin/rmdir "$MNT" 2>/dev/null
            /bin/rm -f "$DMG"
            finalize
            relaunch "$APP"
            cleanup_script
            exit 1
        fi
        SRC="$(/usr/bin/find "$MNT" -maxdepth 1 -name '*.app' -print -quit)"
        LAUNCH="$APP"
        STAGED_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$SRC/Contents/Info.plist" 2>/dev/null)"
        if [ -z "$SRC" ]; then
            note fail-no-app-in-dmg
        elif [ -z "$EXPECTED_ID" ] || [ "$STAGED_ID" != "$EXPECTED_ID" ]; then
            # Identity gate. The bundle inside the DMG has to be THIS
            # application. A neighbour's bundle — the original Vorssaint, whose
            # releases were published under its own identifier — carries its own
            # identifier, and swapping it in here would delete Sadoyo,
            # install the neighbour in its folder and relaunch that. Refuse the
            # swap, keep the running app, and report the step.
            note fail-identity
        else
            # Install under the name the DMG ships, in the same folder. A rebrand
            # changes the bundle filename, so this renames it on disk too; a plain
            # update keeps the same name and replaces it in place.
            DIR="$(/usr/bin/dirname "$APP")"
            NAME="$(/usr/bin/basename "$SRC")"
            DEST="$DIR/$NAME"
            # Stage the full copy FIRST; the old app is only removed after the
            # copy completed, so a failure mid-copy never leaves the user with no
            # app at all. The staging name is hidden: Spotlight recognizes the
            # copy as an app bundle whatever its suffix, and when the swap lands
            # while that copy is still being indexed, the installed app keeps
            # showing up in search as "Vorssaint.app.update-new".
            STAGE="$DIR/.$NAME.update-new"
            # A copy an earlier build left behind under the visible name is the
            # same leftover, still indexed; it goes with this one.
            /bin/rm -rf "$STAGE" "$DEST.update-new"
            note fail-copy
            if /usr/bin/ditto "$SRC" "$STAGE"; then
                # Clear ALL xattrs (quarantine + FinderInfo the DMG round-trip
                # adds): FinderInfo breaks strict signature verification.
                /usr/bin/xattr -cr "$STAGE" 2>/dev/null
                note fail-version
                BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$STAGE/Contents/Info.plist" 2>/dev/null)"
                if [ "$BUNDLE_VERSION" = "$EXPECTED_VERSION" ]; then
                    # When the user disabled Gatekeeper, spctl cannot assess anything
                    # and rejects even a healthy bundle; the codesign identity check
                    # below stays as the gate in that case.
                    GATEKEEPER_OK=0
                    if /usr/sbin/spctl --status 2>/dev/null | /usr/bin/grep -q disabled; then
                        GATEKEEPER_OK=1
                    elif /usr/sbin/spctl -a -t exec "$STAGE" >/dev/null 2>&1; then
                        GATEKEEPER_OK=1
                    fi
                    # Pinned to this app's own identifier by the caller, so a
                    # neighbour's bundle can never pass for it.
                    if /usr/bin/codesign -v --deep --strict -R="$REQUIREMENT" "$STAGE" 2>/dev/null \
                        && [ "$GATEKEEPER_OK" = 1 ]; then                    note fail-verify
                        note fail-swap
                        # The backup name is unique per run: after an elevated
                        # install the old bundle is root-owned, a later user-run
                        # cannot delete that backup, and reusing a fixed name
                        # would make the NEXT swap fail on it. Strays from
                        # earlier runs are swept best-effort (an elevated run
                        # clears even the root-owned ones).
                        BACKUP="$DEST.update-old.$PID"
                        /bin/rm -rf "$DEST".update-old "$DEST".update-old.* 2>/dev/null
                        if { [ ! -d "$DEST" ] || /bin/mv "$DEST" "$BACKUP"; } \
                            && /bin/mv "$STAGE" "$DEST"; then
                            LAUNCH="$DEST"
                            note ok
                            # Installed as root: hand the bundle to the user, or
                            # the next user-path update cannot replace it.
                            if [ "$(/usr/bin/id -u)" = "0" ] && [ -n "$ASUSER" ]; then
                                /usr/sbin/chown -R "$ASUSER" "$DEST" 2>/dev/null
                            fi
                            /bin/rm -rf "$BACKUP"
                            # If the bundle was renamed, remove the old-named one.
                            # This happens only after the new bundle is in place.
                            [ "$DEST" != "$APP" ] && /bin/rm -rf "$APP"
                        else
                            [ -d "$BACKUP" ] && [ ! -d "$DEST" ] && /bin/mv "$BACKUP" "$DEST"
                        fi
                    fi
                fi
            fi
            /bin/rm -rf "$STAGE"
        fi
        /usr/bin/hdiutil detach "$MNT" -quiet 2>/dev/null \
            || /usr/bin/hdiutil detach "$MNT" -force -quiet 2>/dev/null \
            || true
        /bin/rmdir "$MNT" 2>/dev/null
        /bin/rm -f "$DMG"
        finalize
        relaunch "$LAUNCH"
        cleanup_script
        """
    }

    /// Single-quotes a string for POSIX sh, closing and reopening the quote
    /// around every embedded single quote (same scheme as
    /// HomebrewSupport.shellQuote, minus its bare-word fast path).
    static func shellSingleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The shell command run with admin rights when the app's folder is not
    /// writable by the current user. The whole installer travels inline (no
    /// script file that another process could rewrite before root runs it)
    /// and is started in its own session (`DetachedProcess`) so the prompt
    /// returns immediately and the installer outlives the app it replaces.
    static func elevatedInstallCommand(appPath: String,
                                       dmgPath: String,
                                       pid: Int32,
                                       resultPath: String,
                                       uid: uid_t,
                                       expectedVersion: String,
                                       expectedBundleIdentifier: String,
                                       verifyRequirement: String? = nil) -> String {
        let script = shellSingleQuoted(installerScript())
        let args = [appPath, dmgPath, "\(pid)", resultPath, "\(uid)", expectedVersion,
                    expectedBundleIdentifier,
                    verifyRequirement ?? stagedVerifyRequirement(expectedBundleIdentifier: expectedBundleIdentifier)]
            .map(shellSingleQuoted)
            .joined(separator: " ")
        return DetachedProcess.detachedShellCommand(
            quotedArgv: "/bin/sh -c \(script) sadoyo-installer \(args)")
    }

    /// Whether the next install attempt should go straight through the admin
    /// prompt: a previous run failed at the copy or swap step, which is what
    /// missing write permission looks like from inside the installer. Other
    /// codes (bad mount, failed verification, a bundle that is not this app)
    /// are not permission problems, so elevating would just add a password
    /// prompt to the same failure.
    static func shouldForceAdminInstall(afterFailureCode code: String?) -> Bool {
        code == "fail-copy" || code == "fail-swap"
    }

    /// Whether a new download fraction crossed into the next whole percent,
    /// so the published state changes ~100 times per download instead of on
    /// every URLSession callback. The first known fraction always counts.
    static func progressStepAdvanced(from current: Double?, to fraction: Double) -> Bool {
        guard let current else { return true }
        return Int(fraction * 100) > Int(current * 100)
    }

    /// Absolute ceiling for an update download. Releases are DMGs of roughly
    /// ten megabytes, so this is far above any real asset and only exists to
    /// stop a response that never ends.
    static let downloadCeilingBytes: Int64 = 200 * 1024 * 1024

    /// How many bytes the download may write before it is abandoned. The
    /// release lists the asset's exact size, so that is the bound whenever it
    /// looks sane; an absent or absurd size falls back to the ceiling.
    static func downloadByteLimit(expectedBytes: Int64?,
                                  ceiling: Int64 = downloadCeilingBytes) -> Int64 {
        guard let expectedBytes, expectedBytes > 0, expectedBytes <= ceiling else {
            return ceiling
        }
        return expectedBytes
    }

    /// Whether a finished download may be handed to the installer. The
    /// signature check still decides what gets installed; this only refuses
    /// bodies that cannot be the asset before they are handed to the installer
    /// and mounted.
    static func downloadIsUsable(status: Int,
                                 receivedBytes: Int64,
                                 expectedBytes: Int64?,
                                 ceiling: Int64 = downloadCeilingBytes) -> Bool {
        guard status == 200, receivedBytes > 0, receivedBytes <= ceiling else { return false }
        guard let expectedBytes, expectedBytes > 0 else { return true }
        return receivedBytes == expectedBytes
    }

    /// True when the app cannot be updated in place at all: running from the
    /// randomized read-only mount Gatekeeper uses for translocated apps, or
    /// from any other read-only volume (the mounted DMG). External writable
    /// volumes are fine, so this asks the file system instead of guessing
    /// from the path.
    static func runsFromImmutableLocation(appPath: String,
                                          volumeIsReadOnly: (String) -> Bool) -> Bool {
        appPath.contains("/AppTranslocation/") || volumeIsReadOnly(appPath)
    }
}
