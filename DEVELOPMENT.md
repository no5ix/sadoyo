# Development Guide

## Environment

The project is a native macOS Swift application. See [CONTRIBUTING.md](CONTRIBUTING.md) for the supported macOS/Xcode Command Line Tools requirements and the recommended onboarding path.

## Authoritative build system

Use `./build.sh` for actual application builds. `Package.swift` is for editor indexing and does not produce/sign the app bundle.

### Common commands

```sh
# Optimized Release app bundle
./build.sh

# Separate Developer variant
./build.sh --dev

# Install the Developer variant
./build.sh --dev --install

# Run the full custom test suite
./build.sh --test

# List available test suites
./build.sh --list-tests

# Run one named suite
./build.sh --test-suite=NAME

# Release selftest (after a Release build)
./build/Sadoyo --selftest

# Developer selftest (after a Developer build)
./build/SadoyoDeveloper --selftest
```

Expected local bundle locations documented by the current build workflow:
- Release: `build/stage/Sadoyo.app`
- Developer: `build/stage.noindex/Sadoyo (Developer).app`

Check the actual build output before launching. The Developer app uses a distinct bundle identifier, preferences, and macOS privacy permissions; grants do not automatically transfer between variants.

Sadoyo ships under its own application identity (`com.sadoyo.app`, Developer
`com.sadoyo.app.dev`) so it coexists with the original Vorssaint
(`com.vorssaint.utils`) on the same Mac: separate notifications, permissions,
preferences, login item and fan daemon. Read
[App identity and coexistence](docs/app-identity.md) before changing anything
that names the app, and `./build.sh --test-suite=app-identity` to check it.

## Tests and validation

1. Use `./build.sh --list-tests` to discover the current suites.
2. Run the narrowest relevant suite with `./build.sh --test-suite=NAME`.
3. Run broader tests with `./build.sh --test`.
4. Build the actual app with `./build.sh` after code, resource, source-list, or bundle changes.
5. Run the matching app selftest.
6. For UI or OS integration changes, test the real Release app and report the actual environment and interactions.

The repository's custom test executable compiles a selected set of sources. Passing tests do not replace a complete app build and selftest. Some tests exercise wall-clock, display, permission, or hardware behavior and may be environment-sensitive. Investigate failures; do not label them flaky or pre-existing without evidence.

## Release build and visual testing

For final product visual verification, use the Release bundle:
`build/stage/Sadoyo.app`

Use Peekaboo when available to inspect the real application, interact with the relevant controls, and capture screenshots. Verify the running process/bundle so a Developer instance is not mistaken for Release.

For each visual test, record:
- macOS version and Mac model.
- Release bundle path and process/bundle identity.
- Display configuration, resolution/scaling, and relevant Spaces/full-screen state.
- Exact interaction performed.
- Screenshot or other evidence path.
- What passed, failed, and remained untested.

Do not treat source inspection, SwiftUI previews, geometry probes, or unit tests as proof of a live UI interaction. If Peekaboo or a needed permission is unavailable, state the limitation and perform the strongest safe alternative.

## Signing and macOS permissions

Stable signing matters because macOS TCC permissions are associated with application identity/signing. Ad-hoc rebuilds can invalidate Accessibility and Screen Recording grants while System Settings still appears to show a grant.

- Read [CONTRIBUTING.md](CONTRIBUTING.md) for stable signing and installation guidance.
- Read [docs/app-identity.md](docs/app-identity.md) before changing the bundle identifier, display name, executable name, notification identifiers, the fan daemon label, or the self-updater's identity gate. Changing an identifier orphans existing TCC grants.
- Read [docs/PERMISSIONS.md](docs/PERMISSIONS.md) before changing permission behavior.
- Read [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for stale permission grants and recovery.
- Do not reset TCC permissions broadly as a convenience.
- Do not assume Release and Developer variants share grants.

Official releases use the protected signing/notarization workflow. Local builds are not official releases.

## Generated files and source inclusion

Before adding a source file, inspect how `build.sh` discovers or enumerates sources and whether a generator or manifest must be updated. Check `Tests/generate_sources.py` and related tooling when generated source lists or source ownership are involved. Do not assume SwiftPM automatically includes a new file in the authoritative build.

## Debugging and change hygiene

- Reproduce the issue and record the conditions.
- Trace the event/data path before modifying the code.
- Prefer structured logs and narrow diagnostics; remove temporary noisy logging once no longer needed, or keep intentional diagnostics consistent with project conventions.
- Test failure and fallback paths, not only the successful path.
- Review `git diff` and `git status`; stage only task-related files.
- Follow the contribution guide's commit format and release boundaries.

## Existing detailed guides

- [Contributing](CONTRIBUTING.md)
- [Agent-assisted contributions](docs/AI-CONTRIBUTIONS.md)
- [Permissions](docs/PERMISSIONS.md)
- [Privacy](docs/PRIVACY.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Scroll/zoom testing](docs/SCROLL-ZOOM-TESTING.md)
