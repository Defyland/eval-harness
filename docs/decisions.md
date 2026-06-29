# Technical Decisions

## 2026-06-29 - Start With Static Readiness Rules

Context: The workspace needs a common bar for AI-operable projects: good docs, explicit decisions, tests, CI, deployment readiness where relevant, and no obvious sensitive local files. Running every project's full toolchain from one harness would be slow and brittle at this stage, because the workspace spans Ruby, Rails, Go, Rust, Elixir, Kubernetes, gems, and CLI tools.

Options considered:

- Execute each project's full CI locally.
- Build a GitHub release dashboard first.
- Start with static readiness rules over files, manifests, docs, and Git state.

Choice: Start with static readiness rules.

Pros:

- Fast enough to run across many projects.
- Works across stacks without installing every toolchain.
- Gives cheap models an immediate quality signal before they touch code.
- Catches major release blockers: missing README, missing decisions, missing tests, missing CI, dirty worktree, and sensitive local files.
- Can be used in future CI as a preflight.

Cons:

- Does not prove tests actually pass.
- Heuristics can misclassify whether Railway is important.
- Does not inspect remote GitHub visibility or live workflow status.
- Does not replace stack-specific review.

Consequences:

- Project-specific threads must still run real tests and CI-equivalent commands.
- Release coordinator tooling should later combine this static report with command results and GitHub state.
- Railway remains a warning-level deployment rule, not a hard universal gate.

Verification evidence:

- `bundle exec rake test`
- `bin/eval-harness .`
