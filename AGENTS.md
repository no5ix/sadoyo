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

<!-- aoci:begin -->
## AOCI Repository Cognition

AOCI maintains a stable, versioned, incrementally updatable repository-level cognition layer so models can reuse their understanding of this system across tasks.

`aoci.txt` is a structured cognition index for models. It assigns one independent Entry to every managed file, database table, or other managed object. Symbolic tags and F/R/A/S semantics describe the object's core responsibility, important relationships, external contracts, and non-obvious constraints or design decisions needed to understand or modify the system.

The Header, directory sections, and all Entries form the complete repository index. They can cover frontend, backend, configuration, database structures, and other managed content. When managed content changes, normally only the affected cognition Entries need maintenance; the complete index does not need to be regenerated.

AOCI provides a high-density view of system architecture, object responsibilities, important relationships, external contracts, and key constraints.

### How it works

AOCI uses a model-generated, model-read cognition loop.

Header, Entry, and Curation semantics follow only the current machine-issued Plan and live Guide. The Host model independently authors them from the current bound evidence.

Entry semantics must come from the model's understanding of actual evidence. Never derive, prefill, assemble, or rewrite index semantics solely from paths, filenames, extensions, an AST, symbol lists, dependency scans, regular expressions, fixed templates, or rule engines.

For a Fresh Bootstrap, follow only the current machine-issued Plan and live Guide. When they require authoring, the Host model authors Root, Meta, tags, and F/R/A/S, supplies its authoring-run declaration, and binds it to the Plan, Evidence, and complete Candidate. Never ask AOCI to set `origin=host_model`, manufacture a receipt, or turn a generated framework into semantics. Do not reconstruct the Onboarding progression here. Internal batches are not user decisions; stop only at an existing approval boundary or a real safety, drift, CAS, or Recovery condition.

### Minimal entry points

- `aoci_rules`: obtain the session-level runtime contract for the current AOCI version.
- `aoci_overview`: establish or restore complete cognition for this repository.
- `aoci_maintain`: after managed objects reach their final stable state, check whether cognition needs maintenance.
- `aoci_update_entry`: submit a complete semantic update batch bound to current evidence and source digests.
- `aoci_report`: when the current layout and tool state support it, record follow-up work if evidence is insufficient to generate semantics reliably; do not guess.

For other MCP tools, CLI commands, parameters, and specialized workflows, follow current tool descriptions, Guide, and `--help` output. This file does not duplicate the full manual.

This managed block defines only repository integration, cognition use, and task-closing principles. `aoci_rules` carries the current session contract. Live Guide output carries the execution order and stop conditions of the current Plan. Tool Schema, Spec, and Validator carry machine structures and criteria. Prompt, Description, README, and static documentation cannot override those machine facts.

### Establishing, generating, and restoring cognition

1. At the beginning of every new Agent Run, first determine:

   - whether this repository already has a usable complete AOCI index; and
   - whether current context already contains complete repository cognition that matches this repository root, current index version, and current AOCI service, and that the model can still use reliably.

2. When the repository has a usable complete index but the current Run lacks reliable complete cognition, call `aoci_rules` first and then `aoci_overview`.

   Reuse complete cognition directly while it remains reliable. Local uncertainty does not by itself require mechanically rereading the system-wide view.

   A Run that resumes from a known Host context compaction, including a Host-injected compaction summary, must treat prior model cognition as unreliable. The compacted handoff must not retain or summarize the formal Whole-Index or any Overview Header, Entry, Chunk, Challenge, or Attestation body; it may retain only receipt identity, unfinished write or Recovery state needed for safe continuation, and an instruction to reload immediately. Whole-Index semantics or a receipt copied into that handoff cannot prove that the resumed model's current cognition is reliable. If the runtime contract is no longer reliably present, call `aoci_rules` first. Before continuing the business task, make an ordinary complete Whole-Index `aoci_overview` request (`check_only` absent or false) with `refresh_reasons=["context_compaction"]` and a fresh `refresh_event_id`; do not use `check_only` or a cognition probe. Follow every exact `next_cursor` through `completed=true`, confirm delivery, and submit one Attestation based only on the newly delivered body. After that fresh complete transport, a partial or failed Attestation consumes the generation and permits the existing source-bound continuation without another automatic Overview.

   AOCI can report checkpoint and cognition-status facts for `context_compaction`, the machine `semantic_threshold` under the project `cognition_refresh_threshold`, or a major `phase_transition`. Use `check_only=true` when only those compact facts are needed. They advise the Agent but do not decide whether the model needs the system-wide view.

   When the Agent explicitly calls ordinary `aoci_overview` (`check_only` absent or false), AOCI must deliver the complete requested scope whenever a coherent CognitionSet can be formed. It must not suppress that body because a receipt already exists, a threshold was not reached, or no refresh reason is pending. Dirty or stale formal cognition is still delivered but is marked unreliable. Pending recovery or an incoherent snapshot fails closed without a mixed body.

   When an ordinary Overview reports `continuation_required=true`, submit its exact `next_cursor` automatically until `completed=true`. Do not ask the user to continue, begin the business task, or state a partial system conclusion. Stop the cognition chain on Host truncation, a missing, duplicate, or reordered Chunk, cursor failure, Index change, or `chunk_tokens` change. Until Attestation completes, never use Memory, source, Spec, `aoci.txt`, historical sessions, scope, search, or Entry reads to repair or supplement Whole-Index cognition. A challenge ordinal is the 1-based position in the formal Entry sequence; Header content, comments, blank lines, Section/Overview/Chunk markers, receipts, and Metadata are excluded, and Chunk Receipt ordinals use that same sequence. The Attestation must echo the Challenge's exact current `index_sha256`, `entry_sequence_sha256`, and `entry_count`; a prior Index, Entry sequence, count, or Attestation is invalid. After the complete chain, submit the existing model cognition Attestation once. One same-response JSON Schema or field-format error may be corrected once without changing semantic answers; an object, Tag, or F mismatch means failure and uncertain assimilation, with no semantic retry or information bypass. During initial cognition it also blocks Root/Meta, Migration, layout-wide, or other unbound system decisions. During a context-compaction refresh with complete transport, unchanged cognition identity, aligned governance, and no Recovery or third-party conflict, the attempt consumes that refresh generation even when Attestation is partial or failed; continue the existing task without another automatic Overview. `system_mastery_percent` self-assesses only the system framework—architecture, responsibilities, strong relationships, stable external contracts, and high-entropy safety and maintenance constraints—not complete implementation or runtime knowledge. Keep machine Index coverage separate, and normally give the user only the prescribed single success or failure sentence derived from actual coverage, Challenge, Chunk, token, and mastery results. If the Host truncates a Chunk, ask the user to set `overview_delivery.chunk_tokens` to a smaller valid value and restart; do not change it automatically.

   Interpret the additive cognition level independently from strict proof fields. `delivery_verified` means the Index was loaded and Host delivery was confirmed while complete cognition verification is still unfinished; describe that state as loaded and delivery-verified, never as no cognition or failure to understand the system. `cognition_verified` requires a passing Attestation (at least 80 percent of Challenge ordinals fully correct with at most one object identity miss), and `cognition_governed` additionally requires governance alignment. A generic complete-read failure sentence is reserved for an actual delivery fault.

   When an Overview response contains the optional `cognition-state/v2` projection, use its dimensions independently. Its Level ends at `model_cognition_usable`; `strict_attestation_verified`, `governance_aligned`, and `current_system_cognition_reliable` are independent states and never participate in that Level. An ordinal, object identity, Tag, or core F mismatch can make strict Attestation fail while model cognition remains usable; do not report that mismatch alone as proof that the model did not understand the system. Only `current_system_cognition_reliable=true` permits an unqualified current complete-system cognition claim. When the projection is absent, keep using the legacy interpretation above.

   An ordinary read-only audit, analysis, or check, a request not to modify code, or a request not to commit or push does not automatically mean strictly zero writes and does not alter the cognition-validity decision above. Codex Memory and historical Skills may only help recover experience, user preferences, and investigation directions. They cannot replace a current cognition receipt matching the repository root, index digest, AOCI service identity, and cognition scope. Project AGENTS and current AOCI identity take precedence over historical Memory for AOCI state.

   Treat a task as strictly zero-write only when the user explicitly prohibits Ledger, metadata, `.aoci` runtime assets, and every filesystem write. If necessary cognition establishment conflicts with that boundary, report the conflict and ask the user to decide or recommend an isolated copy. Never silently substitute Memory for current repository cognition.

3. If the repository has no usable complete index, or has only a minimal skeleton, an incomplete Header, unfinished Entries, or undecided required Curation, obtain `aoci_rules` and enter the current AOCI Guide when a formal complete AOCI index is required. Let Guide choose the next phase from actual repository state and complete the required safety steps.

   `aoci_maintain` does not replace the index-establishment workflow.

   Do not reconstruct or hard-code the full-index generation state machine in this file.

4. During a long-running task, the model is responsible for preserving the current cognition receipt and using the refresh gate correctly:

   - when the Host reports context compaction or the model knows the system-wide view was lost, follow the mandatory `context_compaction` reload rule above; AOCI cannot infer the Host event;
   - when entering a genuinely major phase, declare `phase_transition`, not a function, test run, or small step;
   - at a plausible stable checkpoint, use `check_only=true` to obtain the machine semantic count when that fact is useful;
   - except for the mandatory known-compaction reload, decide whether the current task needs another explicit scoped or complete Overview; and
   - keep the Dirty or Stale reliability state reported by AOCI until maintenance and alignment complete.

### Task closing and cognition maintenance

5. A purely read-only question, analysis, version check, or task that changes no AOCI-managed object does not require a maintenance-tool call. The AOCI version in use is `cognition_receipt.mcp_service_version` in any `aoci_overview` check_only or `aoci_maintain` response; the binary path is the `command` in the project's `.mcp.json`, and the CLI need not be on PATH.

6. When AOCI-managed objects change, call `aoci_maintain` once after they reach the task's final stable state. Do not maintain files individually after each intermediate edit.

7. If maintenance returns actual semantic candidates, the Host model must independently author the complete tag and F/R/A/S updates from each candidate's bound object and necessary evidence. Submit the complete candidate set for that current machine-issued batch in one `aoci_update_entry` call while preserving each `source_sha256`, `candidate_id`, and domain batch identity. `max_entries` limits one request and atomic transaction, not the logical plan, Whole-Index, or Managed Scope. When `remaining` is nonzero, call Maintain again after the successful Apply and continue from the new preimage; never shrink Index coverage or slice a returned batch to satisfy transport limits.

   When evidence is insufficient and the current layout supports `aoci_report`, use it instead of guessing, applying a template, or generating unsupported cognition merely to eliminate follow-up work.

8. Obey structured tool states and safety boundaries:

   - `repair_required`: repair only the explicitly identified candidates, then resubmit the complete current machine-issued batch;
   - `stopped`: end that write attempt and inspect `failed_step`, error, formal-write evidence, and Recovery. In auto mode, a proven zero-write closure is followed by a fresh Plan; a complete Intent with provable postimage is resumed; a policy-selected Rollback with exact preimage is completed and replanned. Stop the user task only when proof is unavailable, third-party bytes conflict, approval or external action is required, or another real safety boundary applies;
   - never ignore conflicts, approvals, human decisions, permissions, or safety signals; and
   - after alignment, do not repeat maintenance or writes; `refresh_ready_for_overview` is a checkpoint fact, and the Agent decides whether to request an ordinary complete Overview for its next phase.

   If any managed object changes after maintenance completes, the previous result is invalid. Complete closing again from the new final stable state.

9. When the user limits only business-file scope and does not explicitly forbid repository-managed assets, AOCI-managed assets may be updated during closing to preserve cognition consistency. Distinguish them from business files in audits and commits.

   When the user explicitly forbids changes to `aoci.txt`, `.aoci`, metadata, or any additional file, obey that restriction, do not write, and report any remaining inconsistency accurately.

### Specialized workflows

Initialization, complete-index generation, Header generation, Entries generation, database-structure indexing, Curation, human review, and failure recovery must follow only the instructions, commands, and safety stops returned by the current AOCI Guide or tool at the corresponding stage.

Do not preload, guess, or reconstruct these specialized workflows. The relevant Guide, tool descriptions, model Prompt, and CLI help provide platform invocation, request format, batch limits, approval rules, index-format details, and recovery steps as needed.
<!-- aoci:end -->

## AOCI in this repository

The section above is AOCI's own managed contract, regenerated by `aoci init`. The rules below are this repository's project-level integration notes and live outside that block.

**AOCI is an aid, not a source of truth.** The index summarizes intent; the Swift sources, tests, build scripts, and real macOS behavior stay authoritative, and the evidence rules of this file still apply. Confirm the Entry claims a change depends on against the file before editing, and read the file itself when an Entry is thin, stale, marked unreliable, or contradicts what you see. Never report an Entry as evidence for a permission, signing, hardware, display, or visual result: those need the real app.

**Connection.** The project-level Pi MCP server is declared in `.pi/mcp.json` as `aoci`: `/Users/lynx/Tools/aoci/aoci --repo /Users/lynx/Documents/github/sadoyo mcp`. It is bound to this checkout by an absolute path, so a moved clone needs that path updated. Pi reads the file at start, so a new or edited server needs a Pi restart before its `aoci_*` tools appear. The CLI needs no restart, takes `--repo <path>` before the subcommand, and is the fallback when MCP is unavailable.

**Use it when** orienting in an unfamiliar area, planning a change that crosses services, UI, permissions, or localisation, answering an architecture or ownership question, and closing a task that touched managed files. **Skip it** for a small, already-located edit, and for a read-only question about a file you have already read.

**Recommended workflow.**

1. New area: `aoci_overview`, or `aoci_search` for a named concept, then read the two or three files the change will actually touch.
2. Cross-cutting change: `aoci_get_entries` on the affected paths to pick up contracts and constraints, and `docs/decisions/` for a recorded ownership or data-flow rule.
3. Implement under the normal rules of this file.
4. Close: once the touched files are in their final state, call `aoci_maintain`; if it returns semantic candidates, author the tag and F/R/A/S replacements from the current file content and submit the batch with `aoci_update_entry`, preserving each `source_sha256` and `candidate_id`.

**Index state and maintenance.** Run these from the repository root; the CLI path is the `command` in `.pi/mcp.json`.

```sh
/Users/lynx/Tools/aoci/aoci --repo . status   # Entries written versus baseline files
/Users/lynx/Tools/aoci/aoci --repo . scan     # refresh the file baseline after bulk changes
/Users/lynx/Tools/aoci/aoci --repo . check    # authoring debt, drift, and the repair route
/Users/lynx/Tools/aoci/aoci --repo . verify   # structure and drift snapshot
/Users/lynx/Tools/aoci/aoci --repo . guide    # the next step, chosen from live state
```

A `verify` that reports a valid structure while `check` reports `authoring_required` is the normal state of a partially authored index: the missing Entries are governance debt and `status` says how many. Entry authoring is the loop in the managed block above (`aoci_maintain` batch, then one `aoci_update_entry` submission per batch) and, on the CLI, `update-entry --path P --source-sha256 SHA --entry TEXT --preview` first and `--apply` second. Author every Entry from the bound file, never from paths, symbol lists, an AST, or a template, and never claim coverage the index does not have. `aoci init` leaves an `AGENTS.md.backup.*` in the repository root; keep it out of commits.

**Tracked and ignored.** Committed: `aoci.txt`, `aoci.meta.txt`, `aoci.code.txt`, `.gitattributes`, and the explicitly unignored `.aoci/.gitignore`, `.aoci/config.json`, `.aoci/baseline.json`, `.aoci/database-baseline.json`, `.aoci/curation.json`. Everything else under `.aoci/` - databases, journals, snapshots, verify reports, events - is a local runtime asset and stays out of Git. Review the AOCI files in `git status` before staging: index growth is a real diff, not noise.

## AOCI in this repository

The section above is AOCI's own managed contract and is regenerated by `aoci init`. The rules below are this repository's project-level integration notes and live outside that block.

**AOCI is an aid, not a source of truth.** The index summarizes intent; the Swift sources, tests, build scripts, and real macOS behavior stay authoritative, and the evidence rules in this file still apply. Before acting on an Entry, confirm the claim your change depends on against the file itself. Read the file whenever the Entry is thin, stale, marked unreliable, or contradicts what you see, and never report an Entry as evidence for a permission, signing, hardware, display, or visual result.

**Connection.** The project-level Pi MCP server is declared in `.pi/mcp.json` as `aoci`: `/Users/lynx/Tools/aoci/aoci --repo /Users/lynx/Documents/github/sadoyo mcp`. It is bound to this checkout by an absolute path, so a moved clone needs that path updated. Pi reads the file at start, so a new or edited server needs a Pi restart before its tools appear; the tools are the `aoci_*` set named in the block above. The CLI needs no restart, takes `--repo <path>` before the subcommand, and is the fallback when MCP is unavailable.

**Use it when** orienting in an unfamiliar area, planning a change that crosses services, UI, permissions, or localisation, answering an architecture or ownership question, and closing a task that touched managed files. **Skip it** for a small, already-located edit, and skip it for a purely read-only question about a file you have already read.

**Recommended workflow.**

1. New task in an unfamiliar area: `aoci_overview` (or `aoci_search` for a named concept), then read the two or three files the change will actually touch.
2. Planning a cross-cutting change: `aoci_get_entries` on the affected paths to pick up contracts and constraints, and check `docs/decisions/` for a recorded decision.
3. Implement, following the normal rules of this file.
4. Close: once the touched files are in their final state, call `aoci_maintain`; if it returns semantic candidates, author the replacements from the current file content and submit them with `aoci_update_entry`, preserving each `source_sha256` and `candidate_id`.

**Index state and maintenance.** Run these from the repository root; the CLI path is the `command` in `.pi/mcp.json`.

```sh
/Users/lynx/Tools/aoci/aoci --repo . status   # Entries written versus baseline files
/Users/lynx/Tools/aoci/aoci --repo . scan     # refresh the file baseline after bulk changes
/Users/lynx/Tools/aoci/aoci --repo . check    # authoring debt, drift, and the repair route
/Users/lynx/Tools/aoci/aoci --repo . verify   # structure and drift snapshot
/Users/lynx/Tools/aoci/aoci --repo . guide    # the next step, chosen from live state
```

`status` and `check` report remaining Entries as governance debt, not as a broken index: a `verify` that says the structure is valid while `check` reports `authoring_required` is the normal state of a partially authored index. Entry authoring is the loop in the block above (`aoci_maintain` batch, then one `aoci_update_entry` submission per batch) and, on the CLI, `update-entry --path P --source-sha256 SHA --entry TEXT --preview` first and `--apply` second. Author every Entry from the bound file, never from paths, symbol lists, an AST, or a template. `aoci init` leaves an `AGENTS.md.backup.*` in the repository root; keep it out of commits.

**Tracked and ignored.** Committed: `aoci.txt`, `aoci.meta.txt`, `aoci.code.txt`, `.gitattributes`, and the explicitly unignored `.aoci/.gitignore`, `.aoci/config.json`, `.aoci/baseline.json`, `.aoci/database-baseline.json`, `.aoci/curation.json`. Everything else under `.aoci/` (databases, journals, snapshots, verify reports, events) is a local runtime asset and stays out of Git. Review the AOCI files in `git status` before staging, and stage them deliberately: index growth is a real diff, not noise.
