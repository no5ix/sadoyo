# Testing Strategy

## Evidence levels

Report these separately:
1. **Automated tests:** named command/suite and actual result.
2. **Build/selftest:** whether the full app bundle compiled, was signed, and passed its selftest.
3. **Live visual/interaction tests:** actual app variant, device/macOS/display context, actions performed, and screenshot evidence.
4. **Not tested:** exact blocker or environmental limitation.

One level does not imply another. A unit test does not prove a menu-bar click works on a real Mac; a screenshot does not prove playback commands target the correct process.

## Recommended sequence

1. Inspect existing tests and use `./build.sh --list-tests`.
2. Add a regression test that fails for the reported behavior and covers adjacent legitimate cases.
3. Run the narrowest applicable suite using `./build.sh --test-suite=NAME`.
4. Run `./build.sh --test` for broad regression coverage.
5. Build with `./build.sh` and run `./build/Vorssaint --selftest`.
6. For UI/OS behavior, launch `build/stage/Vorssaint.app` and use Peekaboo where available.
7. Repeat tests after fixing defects found during visual verification.

## Live macOS test record

Record:
- Commit SHA and branch.
- Release bundle path and running bundle/process identity.
- Mac model and macOS version.
- Display count, resolution/scaling, active Space, full-screen state, and relevant hardware.
- Permission state relevant to the scenario.
- Exact sequence of user interactions.
- Expected and observed result.
- Screenshot/log paths.
- Any unverified paths.

## Important scenario families

Depending on the change, consider:
- First launch, permission denied, permission granted, permission revoked, and relaunch.
- Feature disabled/enabled and app relaunch.
- Single and multiple displays; display sleep/wake; full-screen and Mission Control.
- One and multiple media sessions, stale sessions, player termination, and independent command targeting.
- Dynamic content sizes, localization expansion, minimum window sizes, and scroll boundaries.
- Menu bar destination routing and every fallback route.
- Settings backup/restore and migration.

Do not run destructive permission resets or alter user data merely to make a test pass. Use a controlled test account or clearly documented test setup when appropriate.
