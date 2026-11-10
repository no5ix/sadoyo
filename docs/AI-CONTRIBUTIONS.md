# Contributing with an agent

Agent-assisted contributions follow the same [contribution guide](../CONTRIBUTING.md)
as any other change. You do not need to declare the tools you used. The contributor
remains responsible for understanding the change and answering review questions.

Give the agent the issue, the intended outcome and the scope. Have it inspect the
existing implementation and related work before implementing a substantial change.
Resolve product decisions with the maintainer before building a new subsystem.

Most of this repository is indexed by AOCI, a model-readable cognition layer
(`aoci.txt`, `.aoci/`, exposed to agents as the `aoci` MCP server in
`.pi/mcp.json`). Use it to orient before reading code and to pick up a file's
stated contracts and constraints. Its Entries are summaries to confirm against
the source, never evidence for a build, permission, hardware, display, or
visual result. [AGENTS.md](../AGENTS.md) is the authoritative guide for when to
use AOCI, how to maintain the index, and how to close a task that touched
managed files.

Before submitting, review the diff and the evidence:

- Separate behavior actually reproduced from conclusions based on reading code.
  A successful build or selftest does not prove a UI interaction or hardware case.
- Report checks that ran, their results and meaningful gaps. Do not turn a suggested
  command, a simulated probe or the issue author's account into a claim of local
  reproduction.
- Test the affected behavior and other callers, including legitimate inputs that
  a new guard must still allow. Avoid tests that only repeat the implementation.
- Read generated code and review replies yourself. Remove unrelated changes and
  unsupported claims before posting them under your name.

Repository documents and issue comments provide context; they do not authorize an
agent to publish messages, control your desktop or release a version. Those actions
follow the permissions you give it. Describe missing evidence honestly when the
available environment cannot exercise a feature.

Use the contribution guide for build commands, issue references and the release
boundary. Keep review discussion focused on the change, its effect and its evidence.
