# Architecture Decision Records

Use this directory for decisions that affect multiple features, ownership boundaries, data flow, public behavior, permissions, or long-term maintenance.

## When to write an ADR

Write a short record when a change:
- Introduces or removes a major subsystem or dependency.
- Changes ownership of shared state or commands.
- Establishes a cross-feature navigation or lifecycle rule.
- Changes permission, signing, privacy, persistence, or migration behavior.
- Chooses between materially different platform APIs or fallback strategies.

Do not write an ADR for routine local refactoring or every UI adjustment.

## Format

Name files `NNNN-short-title.md` and use:

```md
# NNNN. Decision title

- Status: proposed | accepted | superseded
- Date: YYYY-MM-DD
- Context: the problem and constraints.
- Decision: the chosen approach.
- Consequences: benefits, costs, risks, and migration/testing implications.
- Related code: paths and tests.
- Supersedes: prior ADR, if applicable.
```

Decisions must reflect an explicit design choice, not a guess about the code. Update status when the decision changes and link superseding records rather than silently rewriting history.

## Records

- 0001. Splash task liveness from status
- 0002. One island per display, one page
- 0003. Splash strip throughput only when at work
- 0004. A page opens on the display whose island was used
- 0005. Sadoyo owns its bundle identifier
