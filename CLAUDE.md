# databasus-operator — Agent Context

A standalone Kubernetes operator (kubebuilder v4) that reconciles `Storage`,
`Notifier`, and `DatabaseBackup` CRs against the REST API of a stock
[databasus](https://github.com/databasus/databasus) instance. It is **not** a fork
of databasus — it deploys alongside the upstream Helm chart and drives the same API
the web UI uses.

## Repo model

- **origin** (primary): `ssh://git@gitea.zen.lofi:30022/sf1tzp/databasus-operator.git`
- `github.com/sf1tzp/databasus-operator` is a **push mirror** of origin — never push
  to it directly, and never merge community PRs on GitHub. Fetch the PR branch,
  merge on gitea (regular merge, not squash/rebase, so GitHub auto-marks the PR
  merged when the commits mirror back).
- The Go module path is the GitHub path (public identity), even though development
  happens on gitea.
- CI lives in `.github/workflows/` and runs on both Gitea Actions and GitHub Actions.
  Caveat: Gitea only falls back to `.github/workflows` while `.gitea/workflows`
  does not exist — the first gitea-only workflow added there requires copying
  `ci.yml` in as well.

## Upstream compatibility

databasus's API is explicitly unstable. Every change that touches
`internal/client/` must keep the README compatibility matrix truthful, and the
pinned databasus version used by tests is the source of truth for what "tested"
means. Current target and the v3.38 → v3.48 migration plan: see
[docs/ROADMAP.md](docs/ROADMAP.md).

## Commands

- `make lint` — golangci-lint (keep it clean; it was cleaned up in July 2026)
- `make test` — envtest-based tests
- `make build` — manager binary; `make manifests generate` after API type changes

## History

Extracted July 2026 from a databasus fork (`~/oss/databasus-operator`, now an
archive) via `git subtree split -P operator`. The fork's upstream PR was rejected
(maintainer priorities + API instability), which is why this exists as a separate
project.
