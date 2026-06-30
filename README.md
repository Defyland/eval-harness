# Eval Harness

`eval-harness` evaluates whether backend projects are ready to be operated by humans and cheap/small AI models. It turns the workspace's quality expectations into executable checks: documentation, decisions, tests, CI, deployment shape, Git state, manifests, and sensitive local-file warnings.

It is not a replacement for each project's test suite. It is a readiness gate that answers: "Does this project expose enough verified context for a model to make safe changes?"

## Why This Exists

The `backend-challenges` workspace is becoming an AI-ready technical asset system. `context-pack-builder` makes context compact. `eval-harness` makes readiness measurable.

Without a harness, every project can claim to have good docs, tests, CI, and deployment support while drifting in different directions. The harness gives each project a common contract and lets future automation fail fast before publishing or delegating work to cheaper models.

## Checks

The current rules evaluate:

- README presence
- runnable shell commands in README
- technical decision docs or ADRs
- architecture docs or engineering case study
- test surface, including recursive language-native test files and documented root verification scripts such as `bin/check` or `bin/ci`
- GitHub Actions CI
- workspace context-pack coverage/freshness when a `.agents/context-packs` registry is present
- Railway/deployment surface when recommended
- common sensitive local files
- Git repository state
- recognized project manifests

Rules produce `pass`, `warn`, `fail`, or `n/a`.

## Usage

Evaluate one project:

```sh
bin/eval-harness ../rails_doctor
```

Evaluate several projects and write Markdown:

```sh
bin/eval-harness ../rails_doctor ../solid_lens --output tmp/readiness.md
```

Write JSON:

```sh
bin/eval-harness ../rails_doctor --format json --output tmp/readiness.json
```

Fail the process when any project has a failing rule:

```sh
bin/eval-harness ../rails_doctor --fail-on fail
```

## How to evaluate this repo in 5 minutes

1. Run the standard local gate:

```sh
bin/check
```

2. Prove the harness evaluates itself and reports the current repo state:

```sh
bin/eval-harness .
```

3. Prove it emits a reusable machine-readable report for another project:

```sh
bin/eval-harness ../rails_doctor --format json --output /tmp/rails_doctor-readiness.json
sed -n '1,40p' /tmp/rails_doctor-readiness.json
```

What those checks prove:

- `bin/check` proves the canonical verification entrypoint runs the Ruby test
  suite and the harness's own readiness gate together.
- `bin/eval-harness .` proves the repo is measured by the same contract it
  expects from other technical assets. On a clean checkout with a current
  workspace context pack, that should report `yes / 10 pass / 0 warn / 0 fail`.
- The JSON export proves the tool is not only human-readable; it can also feed
  cheap models, dashboards, and release automation with structured evidence.

## Interpreting Results

- `fail`: project is not ready for public release or cheap-model operation.
- `warn`: project is operable but has a known gap or unresolved local state.
- `pass`: evidence exists for the rule.
- `n/a`: rule does not apply to that project shape.

The summary marks a project as ready only when there are no `fail` or `warn` rules. The harness is intentionally strict about missing README, decisions, tests, CI, manifests, stale or missing workspace context packs, and sensitive local files. It is intentionally softer about Railway when the repo clearly declares a CLI-only, research, or competition-first boundary.

## Development

Run the standard local gate:

```sh
bin/check
```

Run the narrower Ruby test suite directly:

```sh
bundle exec rake test
```

Run the harness against itself without the test suite:

```sh
bin/eval-harness .
```

## Current Boundary

This is a local static evaluator. It does not execute each project's full test suite, query GitHub Actions status, or publish repositories. When the project lives under a workspace with `.agents/context-packs`, it checks whether the generated context pack exists and whether its embedded source-commit provenance matches the latest repo commit, falling back to file mtime for older packs. Deeper freshness guarantees still belong in later release-coordinator tooling.

## License

MIT. See [LICENSE.txt](./LICENSE.txt).
