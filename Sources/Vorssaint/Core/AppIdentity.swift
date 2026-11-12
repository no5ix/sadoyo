// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Sadoyo's own macOS application identity, in one place.
///
/// Sadoyo is a fork of Vorssaint and is meant to be installed beside the
/// original app on the same Mac. macOS keys a lot of behaviour off the bundle
/// identifier, and none of it is per-bundle-file:
///
///   * `UNUserNotificationCenter` is scoped to the identifier, so the
///     notification store, the categories, the permission grant and — the one
///     that bites — the click target of a posted banner belong to the
///     identifier, not to the bundle that posted them. Clicking a banner asks
///     Launch Services for the app registered under that identifier, and with
///     two bundles registered under one identifier Launch Services picks one
///     (usually the original app), so the banner opens the app you did not
///     post it from;
///   * TCC grants (Accessibility, Screen Recording, …) follow the identifier
///     plus the signature;
///   * the preferences domain, the login item, the fan LaunchDaemon's label
///     and Mach service, and the app's Library folders all derive from it.
///
/// So every one of those has to be Sadoyo's own, and it has to be stated once.
///
/// The upstream identifiers live here as *foreign* identifiers: they name the
/// original app's installs, so Sadoyo's global Dock taps, Quit-all sweep, junk
/// cleaner and self-updater can recognise the neighbour and leave it alone.
/// They are never this app's identity, and nothing here resolves to them.
enum AppBundleIdentity {
    /// This build's identifier, as a compile-time constant. It has to be a
    /// constant: the fan helper is a bare Mach-O that launchd starts on its
    /// own, so `Bundle.main` there carries no identifier at all — the helper
    /// needs to know the app it serves, not itself.
    #if VORSSAINT_DEVELOPMENT
    static let bundleIdentifier = "com.sadoyo.app.dev"
    #else
    static let bundleIdentifier = "com.sadoyo.app"
    #endif

    /// The local "Sadoyo (Developer)" build, whichever variant is running.
    static let developerBundleIdentifier = "com.sadoyo.app.dev"

    /// The identifier this fork's variant carried before the identity split.
    /// It names the *old* preferences domain of a Sadoyo install, so the only
    /// thing allowed to read it is the migration that carries a user's choices
    /// across; nothing here resolves the running app to it.
    #if VORSSAINT_DEVELOPMENT
    static let legacyBundleIdentifier = "com.vorssaint.utils.dev"
    #else
    static let legacyBundleIdentifier = "com.vorssaint.utils"
    #endif

    /// Identifiers that mean "this application": the compiled one, the other
    /// variant of this fork, and the identifier the running bundle carries.
    static var ownBundleIdentifiers: Set<String> {
        var identifiers = [bundleIdentifier, developerBundleIdentifier]
        if let running = Bundle.main.bundleIdentifier { identifiers.append(running) }
        return Set(identifiers)
    }

    static func isOwn(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return ownBundleIdentifiers.contains(bundleIdentifier)
    }

    /// The original Vorssaint's installs. A different application on the same
    /// Mac: it drives its own Dock tile, quits itself, cleans its own data and
    /// updates itself, so nothing here may act on it.
    static let upstreamBundleIdentifiers: Set<String> = [
        "com.vorssaint.utils",
        "com.vorssaint.utils.dev",
    ]

    static func isUpstreamInstall(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return upstreamBundleIdentifiers.contains(bundleIdentifier)
    }

    /// Reverse-DNS domains whose Library data is never junk: this fork's, and
    /// the original app's. A fork that cleans must not eat the neighbour's
    /// preferences, caches or saved state, and must not eat its own.
    static let protectedDomainPrefixes = ["com.sadoyo", "com.vorssaint"]

    static func isProtectedDomain(_ bundleIdentifier: String) -> Bool {
        let lowered = bundleIdentifier.lowercased()
        return protectedDomainPrefixes.contains {
            lowered == $0 || lowered.hasPrefix($0 + ".")
        }
    }

    /// Namespace for notification categories, actions and userInfo keys.
    /// UserNotifications scopes them per identifier already; naming them
    /// Sadoyo's keeps a Sadoyo log, a Sadoyo category and a Sadoyo undo
    /// action recognisably Sadoyo's, and keeps this app's category set from
    /// colliding with the neighbour's in a shared plist.
    static let notificationNamespace = "com.sadoyo.notification"

    static func notificationCategoryIdentifier(_ name: String) -> String {
        "\(notificationNamespace).category.\(name)"
    }

    static func notificationActionIdentifier(_ name: String) -> String {
        "\(notificationNamespace).action.\(name)"
    }

    static func notificationUserInfoKey(_ name: String) -> String {
        "\(notificationNamespace).\(name)"
    }

    /// The privileged fan helper of an app bundle. The LaunchDaemon label, its
    /// Mach service, the codesign identifier and the plist name inside
    /// `Contents/Library/LaunchDaemons` all use this, so two installs each
    /// register their own daemon instead of fighting over one label.
    static func fanControlHelperIdentifier(for appBundleID: String = AppBundleIdentity.bundleIdentifier) -> String {
        "\(appBundleID).fan-control"
    }
}
