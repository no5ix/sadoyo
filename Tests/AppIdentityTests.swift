// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Sadoyo's own macOS application identity, and the coexistence rules that go
/// with it.
///
/// The behaviour under test is the one the shared bundle identifier broke: a
/// notification banner is attributed to an identifier, and clicking it asks
/// Launch Services for the app registered under that identifier. With the fork
/// and the original app registered under one identifier, the banner opened
/// whichever bundle Launch Services preferred — the original app. So the
/// identity has to be Sadoyo's, end to end: in the source, in the shipped
/// plists, in build.sh, in the notification identifiers and in the installer
/// that must never put a neighbour's bundle in this app's folder.
///
/// The bundle that comes out of `./build.sh` is inspected separately (see
/// docs/app-identity.md); these checks keep the source and shipped resources
/// from drifting back apart.
enum AppIdentityTests {
    private static func source(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func plist(_ path: String) -> [String: Any] {
        (NSDictionary(contentsOfFile: path) as? [String: Any]) ?? [:]
    }

    static func run(_ suite: TestSuite) {
        identityIsThisAppsOwn(suite)
        notificationIdentifiersAreOwn(suite)
        fanDaemonIdentityIsOwn(suite)
        shippedResourcesCarryTheIdentity(suite)
        buildScriptCarriesTheIdentity(suite)
        neighbourInstallStaysUntouched(suite)
        preferencesCrossTheIdentityOnce(suite)
    }

    // MARK: - Source identity

    private static func identityIsThisAppsOwn(_ suite: TestSuite) {
        suite.expect(AppBundleIdentity.bundleIdentifier == "com.sadoyo.app"
                         || AppBundleIdentity.bundleIdentifier == "com.sadoyo.app.dev",
                     "the compiled identity is a Sadoyo identifier, got \(AppBundleIdentity.bundleIdentifier)")
        suite.expect(AppBundleIdentity.developerBundleIdentifier == "com.sadoyo.app.dev",
                     "the Developer variant keeps its own Sadoyo identifier")
        suite.expect(AppBundleIdentity.bundleIdentifier != AppBundleIdentity.developerBundleIdentifier,
                     "the two variants never share one identifier")
        suite.expect(AppBundleIdentity.ownBundleIdentifiers.isDisjoint(with: AppBundleIdentity.upstreamBundleIdentifiers),
                     "this app's identifiers exclude the original Vorssaint's")
        suite.expect(AppBundleIdentity.isOwn(AppBundleIdentity.bundleIdentifier)
                         && AppBundleIdentity.isOwn(AppBundleIdentity.developerBundleIdentifier),
                     "both Sadoyo variants are this app")
        suite.expect(!AppBundleIdentity.isOwn("com.vorssaint.utils")
                         && !AppBundleIdentity.isOwn("com.vorssaint.utils.dev")
                         && !AppBundleIdentity.isOwn("com.example.editor") && !AppBundleIdentity.isOwn(nil),
                     "the neighbour app and a stranger are not this app")
        suite.expect(AppBundleIdentity.isUpstreamInstall("com.vorssaint.utils")
                         && AppBundleIdentity.isUpstreamInstall("com.vorssaint.utils.dev")
                         && !AppBundleIdentity.isUpstreamInstall(AppBundleIdentity.bundleIdentifier)
                         && !AppBundleIdentity.isUpstreamInstall(nil),
                     "the original Vorssaint installs are recognised as the neighbour")
        suite.expect(AppBundleIdentity.legacyBundleIdentifier == "com.vorssaint.utils"
                         || AppBundleIdentity.legacyBundleIdentifier == "com.vorssaint.utils.dev",
                     "the domain this fork used to live in is named for the migration only")
        suite.expect(AppInfo.name == "Sadoyo",
                     "the app names itself Sadoyo in its own UI and window titles")
        suite.expect(AppInfo.repositoryURL.path.hasPrefix("/no5ix/sadoyo"),
                     "the source and release feed of this build are this fork's")
    }

    private static func notificationIdentifiersAreOwn(_ suite: TestSuite) {
        let action = Notifier.whatsAppOrganizerUndoActionIdentifier
        suite.expect(action.hasPrefix(AppBundleIdentity.notificationNamespace)
                         && action == "com.sadoyo.notification.action.whatsapp-organizer.undo",
                     "the notification's undo action is a Sadoyo identifier, got \(action)")
        suite.expect(!action.lowercased().contains("vorssaint"),
                     "a notification identifier carries no neighbour name")
        suite.expect(AppBundleIdentity.notificationCategoryIdentifier("x") == "com.sadoyo.notification.category.x"
                         && AppBundleIdentity.notificationUserInfoKey("x") == "com.sadoyo.notification.x",
                     "categories and userInfo keys share the Sadoyo namespace")
        // The whole notification path must resolve to Sadoyo: the delegate
        // handler reads the transaction id out of the response and calls the
        // organizer directly, with no bundle identifier and no URL in between.
        let delegate = source("Sources/Vorssaint/App/AppDelegate.swift")
        let handler = delegate.components(separatedBy: "extension AppDelegate: UNUserNotificationCenterDelegate")
            .dropFirst().first.map { $0.components(separatedBy: "\n}").first ?? "" } ?? ""
        suite.expect(!handler.isEmpty && !handler.contains("NSWorkspace")
                         && !handler.contains("openApplication")
                         && !handler.contains("com.vorssaint"),
                     "the notification response opens no application by identifier — macOS activates this app")
    }

    private static func fanDaemonIdentityIsOwn(_ suite: TestSuite) {
        suite.expect(AppBundleIdentity.fanControlHelperIdentifier(for: "com.sadoyo.app") == "com.sadoyo.app.fan-control",
                     "each install derives its own LaunchDaemon identifier")
        suite.expect(AppBundleIdentity.fanControlHelperIdentifier(for: "com.sadoyo.app.dev") != AppBundleIdentity.fanControlHelperIdentifier(for: "com.sadoyo.app"),
                     "the Developer variant registers a daemon of its own, not the official one")
        let helper = source("Sources/Vorssaint/Services/FanControl/FanControlXPC.swift")
        suite.expect(helper.contains("static let appBundleID = AppBundleIdentity.bundleIdentifier")
                         && helper.contains("AppBundleIdentity.fanControlHelperIdentifier(for: appBundleID)"),
                     "the fan helper derives its app and service names from the shared identity")
    }

    // MARK: - Shipped resources

    private static func shippedResourcesCarryTheIdentity(_ suite: TestSuite) {
        let info = plist("Resources/Info.plist")
        suite.expect(info["CFBundleIdentifier"] as? String == "com.sadoyo.app",
                     "Info.plist ships Sadoyo's bundle identifier")
        suite.expect(info["CFBundleName"] as? String == "Sadoyo"
                         && info["CFBundleDisplayName"] as? String == "Sadoyo",
                     "Info.plist ships Sadoyo's display name")
        suite.expect(info["CFBundleExecutable"] as? String == "Sadoyo",
                     "Info.plist launches Sadoyo's executable")
        suite.expect(info["LSUIElement"] as? Bool == true,
                     "the identity change keeps the menu bar app's launch style")
        let prompts = info.keys.filter { $0.hasPrefix("NS") && $0.contains("UsageDescription") }
        suite.expect(prompts.count >= 8, "the permission prompts are in the shipped plist")
        suite.expect(prompts.allSatisfy { !(info[$0] as? String ?? "").contains("Vorssaint") },
                     "every permission prompt names Sadoyo, not the neighbour")

        let fan = plist("Resources/com.sadoyo.app.fan-control.plist")
        suite.expect(fan["Label"] as? String == "com.sadoyo.app.fan-control",
                     "the shipped LaunchDaemon label is Sadoyo's, so two installs register two daemons")
        suite.expect(fan["BundleProgram"] as? String == "Contents/Library/LaunchServices/com.sadoyo.app.fan-control",
                     "the shipped LaunchDaemon points at Sadoyo's helper binary")
        suite.expect((fan["MachServices"] as? [String: Any])?["com.sadoyo.app.fan-control"] as? Bool == true,
                     "the shipped Mach service is Sadoyo's, so the XPC connection reaches Sadoyo's helper")
        for locale in (try? FileManager.default.contentsOfDirectory(atPath: "Resources")) ?? [] {
            guard locale.hasSuffix(".lproj") else { continue }
            let strings = source("Resources/\(locale)/InfoPlist.strings")
            suite.expect(!strings.contains("Vorssaint"),
                         "the \(locale) permission prompts name Sadoyo")
        }
    }

    private static func buildScriptCarriesTheIdentity(_ suite: TestSuite) {
        let script = source("build.sh")
        suite.expect(!script.isEmpty, "build.sh is readable for the identity contract")
        suite.expect(script.contains("APP_BUNDLE_ID=\"com.sadoyo.app\""),
                     "the Release build stamps Sadoyo's bundle identifier")
        suite.expect(script.contains("APP_BUNDLE_ID=\"com.sadoyo.app.dev\""),
                     "the Developer build stamps its own Sadoyo identifier")
        suite.expect(script.contains("APP_NAME=\"Sadoyo\"") && script.contains("EXECUTABLE=\"Sadoyo\""),
                     "the Release bundle and executable are Sadoyo's")
        suite.expect(script.contains("cp Resources/com.sadoyo.app.fan-control.plist"),
                     "the bundle carries Sadoyo's LaunchDaemon plist")
        suite.expect(!script.contains("APP_BUNDLE_ID=\"com.vorssaint"),
                     "build.sh assigns no neighbour identifier")
        // The identity gate is what keeps `--install` from deleting the
        // neighbour: a leftover is only swept when it carries this build's id.
        let install = script.components(separatedBy: "if (( INSTALL )); then").dropFirst().first?
            .components(separatedBy: "\nfi").first ?? ""
        suite.expect(install.contains("Print CFBundleIdentifier")
                         && install.contains("!= \"$APP_BUNDLE_ID\"")
                         && install.contains("continue"),
                     "an install leaves a foreign bundle in /Applications alone")
    }

    // MARK: - Coexistence rules

    private static func neighbourInstallStaysUntouched(_ suite: TestSuite) {
        suite.expect(CleanerSupport.isProtectedBundleID("com.sadoyo.app")
                         && CleanerSupport.isProtectedBundleID("com.sadoyo.app.fan-control"),
                     "Sadoyo's own domains are never junk")
        suite.expect(CleanerSupport.isProtectedBundleID("com.vorssaint.utils")
                         && CleanerSupport.isProtectedBundleID("com.vorssaint.utils.dev"),
                     "the neighbour's domains are never junk either, so the cleaner cannot eat its data")
        suite.expect(!CleanerSupport.isProtectedBundleID("com.vendor.editor")
                         && !CleanerSupport.isProtectedBundleID("com.sadoyoish.editor"),
                     "a vendor editor stays cleanable, and a lookalike domain is not protected")
        suite.expect(AppBundleIdentity.isProtectedDomain("com.sadoyo.app")
                         && AppBundleIdentity.isProtectedDomain("com.vorssaint.utils")
                         && !AppBundleIdentity.isProtectedDomain("com.sadoyoish.app"),
                     "a protected domain ends at a dot")
        let dev = AppBundleIdentity.developerBundleIdentifier
        suite.expect(ScreenshotSharingSupport.developerBundleIdentifier == dev,
                     "the Developer endpoint follows Sadoyo's identifier, not the neighbour's")
        suite.expect(RecordingSharingSupport.developerBundleIdentifier == dev,
                     "the video Developer endpoint follows Sadoyo's identifier too")
        let update = UpdateInstallerSupport.installerScript()
        suite.expect(!update.contains("com.vorssaint"),
                     "the self-updater names no neighbour identifier")
        suite.expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-identity") == false,
                     "an identity refusal is not retried as an elevated install")
    }

    // MARK: - Settings continuity

    private static func preferencesCrossTheIdentityOnce(_ suite: TestSuite) {
        let token = UUID().uuidString
        let legacy = "com.vorssaint.tests.app-identity.legacy-\(token)"
        let current = "com.vorssaint.tests.app-identity.current-\(token)"
        // The instance IS the new domain, as `UserDefaults.standard` is the
        // running app's domain in the app: the migration writes there and reads
        // the old one by name.
        let defaults = UserDefaults(suiteName: current)!
        defaults.setPersistentDomain([
            "notchSize": 2,
            "mixerShowFinder": true,
            "AppleLanguages": ["en"],
            "NSFakeInjectedKey": "noise",
            "keepMe": "from this app",
        ], forName: legacy)
        defaults.setPersistentDomain(["keepMe": "already chosen here"], forName: current)

        Defaults.migrateIdentityPreferencesDomain(in: defaults,
                                                  legacyDomainName: legacy,
                                                  domainName: current)
        suite.expect(defaults.persistentDomain(forName: current)?["notchSize"] as? Int == 2
                         && defaults.persistentDomain(forName: current)?["mixerShowFinder"] as? Bool == true,
                     "a Sadoyo install keeps the shortcuts and toggles it chose before the identity split")
        suite.expect(defaults.persistentDomain(forName: current)?["keepMe"] as? String == "already chosen here",
                     "the import never overwrites what this install already has")
        suite.expect(defaults.persistentDomain(forName: current)?["AppleLanguages"] == nil
                         && defaults.persistentDomain(forName: current)?["NSFakeInjectedKey"] == nil,
                     "keys macOS injects into a suite domain stay in it")
        suite.expect(defaults.bool(forKey: DefaultsKey.identityPreferencesImported),
                     "the import is marked done")

        // The neighbour keeps writing to its own domain afterwards. The marker
        // makes the second pass a no-op, so a Sadoyo choice made after the
        // import can never be moved by a write next door.
        defaults.setPersistentDomain([
            "notchSize": 99,
            "arrivingLate": true,
        ], forName: legacy)
        Defaults.migrateIdentityPreferencesDomain(in: defaults,
                                                  legacyDomainName: legacy,
                                                  domainName: current)
        suite.expect(defaults.persistentDomain(forName: current)?["arrivingLate"] == nil
                         && defaults.persistentDomain(forName: current)?["notchSize"] as? Int == 2,
                     "the neighbour writing to its own domain later never moves a Sadoyo choice")
        defaults.removePersistentDomain(forName: legacy)
        defaults.removePersistentDomain(forName: current)
        defaults.removeObject(forKey: DefaultsKey.identityPreferencesImported)
    }
}
