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

## 2026-06-29 - Check Workspace Context Pack Coverage Before Calling A Repo AI-Ready

Context: `context-pack-builder` now packages high-signal docs, manifests, CI, ADRs, and contract tests, but `eval-harness` still had no rule proving that a repository actually had a generated context pack available for review. In this workspace, cheap-model operability depends on that artifact being present and not obviously stale.

Options considered:

- Leave context-pack generation outside the readiness contract.
- Require context packs for every evaluated repository everywhere.
- Check for workspace context-pack coverage only when a shared `.agents/context-packs` registry exists, and warn when the pack is missing or older than the latest commit.

Choice: Add a workspace-aware context-pack rule that stays `n/a` outside the orchestrated workspace and warns for missing or stale packs inside it.

Pros:

- Makes reviewer-operability visible in under five minutes.
- Catches a real failure mode: code changes land but the shared context artifact is not regenerated.
- Preserves portability for repositories evaluated outside this workspace.
- Keeps the rule static and fast.

Cons:

- File mtime is a heuristic, not a semantic diff against project state.
- Repositories with unusual context-pack locations are not detected.
- A current-enough file can still be low quality.

Consequences:

- AI-ready readiness in this workspace now depends on regenerating context packs after meaningful commits.
- `context-pack-builder` remains the producer of the artifact; `eval-harness` only checks coverage/freshness.
- Later tooling can add stronger freshness proofs without changing this initial reviewer-facing contract.

Verification evidence:

- `ruby -Itest test/eval_harness_test.rb`
- `bundle exec rake test`
- `bin/eval-harness ../context-pack-builder`
