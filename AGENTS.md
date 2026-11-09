# Instructions for AI Coding Agents

These instructions apply to every AI coding agent working in this repository. Read this file first, then read the relevant project documentation before changing code.

## Sources of truth

- [Contributing](CONTRIBUTING.md): project conventions, scope, localization, validation, PRs, and release boundaries.
- [Agent-assisted contributions](docs/AI-CONTRIBUTIONS.md): evidence standards and agent-specific responsibilities.
- [Architecture guide](ARCHITECTURE.md): source layout, ownership, and major runtime boundaries.
- [Development guide](DEVELOPMENT.md): build, test, signing, launch, and visual verification.
- [Permissions](docs/PERMISSIONS.md), [Privacy](docs/PRIVACY.md), and [Troubleshooting](docs/TROUBLESHOOTING.md): consult before changing permission-sensitive or privacy-sensitive behavior.
- [Design guidelines](docs/design-guidelines/README.md), [Testing guide](docs/testing/README.md), and [Architecture decisions](docs/decisions/README.md): consult for UI, verification, and cross-cutting design changes.

If documentation conflicts with executable code or build scripts, inspect the current implementation, identify the conflict, and update the relevant documentation. Do not silently assume either is current.

## Before editing

1. Inspect `git status`, the current branch, recent commits, and the relevant diff. Do not discard, reset, overwrite, or stage unrelated user work.
2. Read the target file and its callers, owning service/model, related tests, and relevant docs. Search for existing components and services before adding new ones.
3. Trace the complete data and event path. Understand who owns state, who mutates it, and how it reaches the UI.
4. Confirm supported macOS versions, permissions, signing requirements, and build inclusion for any new source file.
5. For user-visible behavior, write down the observable expected behavior and regression cases before implementation.

## Architecture and implementation rules

- Prefer the smallest coherent change that fixes the root cause. Do not rewrite working subsystems to make a local change easier.
- Reuse existing services, models, adapters, view components, permission handling, preferences, and navigation paths. Do not create a parallel implementation without documenting why the existing one cannot serve the requirement.
- Keep decisions and business logic testable outside SwiftUI views where consistent with the surrounding architecture.
- Preserve state ownership. A command sent to a secondary media player must not implicitly change the primary player or reorder the UI. A detail-navigation request must preserve the requested destination through fallback paths.
- Keep UI state, service state, and persisted preferences distinct. Avoid deriving persistent state from transient presentation state.
- Treat process identity, player identity, display identity, and metric identity as stable identifiers. Do not use array position or presentation order as identity.
- Handle unavailable hardware, unsupported APIs, permission denial, and unknown data explicitly. Never fabricate readings, metadata, or successful actions.
- Permission prompts must be initiated through the existing permission flow and explain the reason. Do not bypass macOS TCC, Accessibility, Automation, Screen Recording, or sandbox protections.
- Respect user preferences, feature enablement, background-work lifecycle, backup/restore behavior, and privacy boundaries.
- Update all required localizations and localization tests when user-facing strings change. Follow the existing locale registration and string-catalog patterns.
- Add the repository's SPDX/license and copyright header to new source files, following adjacent files.
- Avoid unrelated formatting churn, dependency additions, generated-file edits, and speculative abstractions.

## Testing and evidence

- Add regression tests for the behavior, not merely tests that mirror private implementation details.
- Test both the intended case and nearby legitimate cases that could be broken by a new guard or filter.
- Run the focused suite first, then relevant broader suites, then build and selftest whenever code or bundled resources change. Use the actual commands documented in [DEVELOPMENT.md](DEVELOPMENT.md).
- A passing test suite does not prove a real macOS interaction, hardware behavior, permission grant, or visual layout.
- For UI, window, menu bar, media, permission, display, and hardware changes, use real Release-app verification with Peekaboo when the environment permits. Record the exact app bundle, macOS version, Mac model, display/Spaces conditions, and actions performed.
- Separate verified results from inferred behavior and untested scenarios. Never claim a test, reproduction, screenshot, or manual check that did not happen.
- If the environment cannot verify a requirement, explain the blocker and provide the strongest evidence available. Do not silently mark it complete.

### Test execution efficiency and command visibility

- Use a risk-based, incremental testing strategy. Do not run the full test suite after every individual file edit or small implementation change.
- **After small changes:** Prefer targeted tests, relevant test cases, or quick compilation checks.
- **After completing a logical group of changes:** Run the relevant focused test suites together.
- **Before declaring a task complete:** Run the required broader test suites, Release build, and app self-test according to `DEVELOPMENT.md`.
- Batch related implementation changes before running expensive verification commands. Avoid redundant full-suite executions when no relevant code or test changes have occurred since the previous successful run.
- When a test fails, inspect the failure, identify its root cause, implement the fix, and rerun the smallest relevant test first. Run broader verification afterward.
- Do not skip required tests, weaken assertions, or remove existing test coverage to save execution time.
- Distinguish compilation checks, targeted test executions, and complete test-suite executions. Never report a compilation check as a successful full test run.
- For long-running commands, preserve and display live output. Prefer `tee` to save complete logs while allowing output to remain visible.
- Avoid pipelines such as `grep ... | head` that can hide progress, suppress diagnostic information, or make a running command appear frozen. If filtering is necessary, preserve the original complete log.
- Do not interrupt a command merely because it produces no output temporarily. Check whether it is still running before deciding it is stuck.
- Record the actual commands, execution durations, test scope, and results in the final report.


## macOS Release, Developer, and permissions

- The authoritative app bundle is built by `build.sh`; `Package.swift` supports editor indexing and does not assemble or sign the app bundle.
- `./build.sh` builds the Release variant at `build/stage/Vorssaint.app`.
- `./build.sh --dev` builds a separate Developer variant with a different bundle identifier, preferences, and TCC permissions. Do not assume permissions granted to one bundle apply to the other.
- For final visual verification, use the Release app unless the task explicitly concerns the Developer variant. Confirm the running process and bundle identity before claiming which build was tested.
- Preserve stable signing identities. Ad-hoc re-signing/rebuilding can invalidate macOS TCC grants. Read [Contributing](CONTRIBUTING.md) and [Troubleshooting](docs/TROUBLESHOOTING.md) before changing signing or permission behavior.

## Git and delivery

- Follow the user's requested branch. Do not create, switch, rebase, reset, or force-push branches unless explicitly requested and safe.
- Review the full diff and staged file list before committing. Stage only task-related files.
- Do not change version numbers or `CHANGELOG.md` unless the maintainer explicitly requests it; the contribution guide reserves those changes for the maintainer.
- Use the repository's conventional commit format: `type(scope): lowercase imperative phrase`.
- Do not publish a release, create a tag, merge a PR, or post public communication unless explicitly requested.
- In the final report, list changed files, actual commands and results, visual evidence, limitations, commit SHA, and push status.

## Git workflow for coding agents (mandatory)

These rules apply to every coding agent working in this repository, on every task, unless the maintainer says otherwise in that task.

- Commit the work. When implementation, testing, and verification for the task are complete, commit the completed changes on the task branch. Do not leave finished work uncommitted.
- Push the task branch. Push the completed branch to the remote repository and confirm the commit exists there (`git log --oneline -1 origin/<branch>` or `git status -sb`).
- Report the delivery. The final report must include the commit hash and the remote push confirmation.
- Never push directly to `main` unless the maintainer has explicitly authorized it for that task. Work on a feature branch.
- Never commit secrets. API keys, credentials, bearer tokens, passwords, cookies, and private keys stay out of commits, tests, fixtures, screenshots, logs, and reports. Keep a locally supplied key in the user's own settings, never in tracked source, and check the staged diff for it before committing.
- Never commit work that has not passed the required verification. Run the focused suite, the relevant broader suites, the release build, and the app self-test first, and record the actual results.
- If verification fails, investigate and fix the problem, then re-run the verification. Do not declare completion over a failing check, and do not weaken, skip, or delete an existing test to make a check pass.
- Preserve unrelated work. Never use `git reset --hard`, `git checkout -- <paths>`, `git clean`, or any other destructive command to obtain a clean working tree. Uncommitted changes that are not yours are left in place, stashed, or committed on a branch so they are not lost.

## Required working style

Do not stop after producing a plan when implementation has been requested. Make reasonable engineering decisions autonomously, continue through implementation and verification, and ask only when an unresolved product decision materially changes the result or a genuine external blocker prevents safe progress.
