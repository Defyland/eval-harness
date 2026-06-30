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

## 2026-06-30 - Add A Canonical Check Entrypoint And A Five-Minute Proof Path

Context: `eval-harness` already had tests, CI, and a concise README, but it
still made a reviewer infer the operational path from separate sections. That
is enough for a careful engineer, not for a cheap model or a five-minute
technical review. The repo needed one canonical local gate plus a short
evidence path that proves both self-evaluation and cross-project output.

Options considered:

- keep `bundle exec rake test` as the only verification entrypoint
- document a quick proof path without adding a canonical script
- add `bin/check`, route CI through it, and document a short evaluation flow

Choice: add `bin/check`, make CI use it, and add a five-minute evaluation path
to the README.

Pros:

- gives humans and models a single verification entrypoint to run first
- reduces drift between local verification and CI
- makes the repo's operational contract visible in under five minutes
- proves both human-readable and JSON output paths from the public README

Cons:

- adds a small shell wrapper that must stay aligned with the intended contract
- self-evaluation inside the workspace still depends on context-pack freshness
  as part of the broader readiness system

Consequences:

- future changes should update `bin/check` first when the local verification
  contract changes
- CI now exercises the same entrypoint the README recommends
- reviewers and cheap models get a shorter, more reproducible path to trust the
  tool

Verification evidence:

- `bundle exec rake test`
- `bin/check`
- `bin/eval-harness .`
- `bin/eval-harness ../rails_doctor --format json --output /tmp/rails_doctor-readiness.json`

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

## 2026-06-29 - Prefer Explicit Context Pack Provenance And Narrow Railway Only For Declared Non-Service Assets

Context: The first context-pack freshness rule used file mtime, which can produce stale warnings for the right reason but is still a weak proxy for artifact truth. The current readiness report also showed Railway warnings on repos that explicitly describe themselves as CLI-only, competition-first, or research assets, plus missed test signals on repos whose executable contract lives in nested `_test` files or a documented `bin/check`.

Options considered:

- Keep the earlier heuristics and just regenerate more packs.
- Add broad repo-name allowlists for non-service assets.
- Read explicit source-commit provenance from generated packs, detect real recursive test surfaces, and narrow Railway only when the repo itself clearly declares a non-service boundary.

Choice: Use embedded pack provenance first, fall back to mtime for legacy packs, and tighten the non-service heuristics around explicit README/doc signals.

Pros:

- Removes tooling-caused false warnings without weakening the release bar.
- Makes context-pack freshness comparisons deterministic when the artifact was generated by the current builder.
- Recognizes honest competition/research/CLI assets without inventing coordinator-side folklore.
- Accepts real executable contracts such as nested Go tests and documented `bin/check` flows.

Cons:

- README-driven heuristics still depend on accurate repository prose.
- Legacy packs remain on the weaker mtime fallback until regenerated.

Consequences:

- Repositories can clear `ai.context_pack` by regenerating packs with current builder output.
- Railway stays required for true runnable services, but not for assets that explicitly reject that deployment boundary.
- `quality.tests` now reflects real verification evidence more closely for Go bootstraps and R&D repositories.

Verification evidence:

- `ruby -Itest test/eval_harness_test.rb`
- `bin/eval-harness ../context-pack-builder`
- `bin/eval-harness ../ractorized-rails-kernel`

## 2026-06-29 - Publish The Harness Under MIT

Context: `eval-harness` is a public contract tool for the workspace. It is
supposed to be copied, adapted, and embedded into future repo-facing
automation, so leaving the repo unlicensed would undercut that intended use.

Options considered:

- leave the repo unlicensed
- choose a restrictive or reciprocal license
- publish under MIT

Choice: publish under MIT.

Pros:

- keeps the evaluator easy to reuse across future assets
- matches the workspace goal of cheap-model-operable tooling
- removes ambiguity for repos that want to copy the readiness contract locally

Cons:

- broad reuse comes with limited reciprocity
- does not impose contribution-back requirements

Consequences:

- the readiness contract is now explicitly reusable, not only practically copyable
- future publication audits can treat license surface as part of the tooling standard

Verification evidence:

- `bundle exec rake test`
- `bin/eval-harness .`
