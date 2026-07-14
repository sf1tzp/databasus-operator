# Roadmap

## Current state (July 2026)

The operator was developed and tested against **databasus v3.38.0**. It reconciles
`Storage`, `Notifier`, and `DatabaseBackup` CRs against the databasus REST API via
the client in `internal/client/`. Lint is clean; there is no automated test coverage
of the API client yet — that is the top gap.

## 1. Migrate the API client to databasus v3.48.x

databasus does not guarantee API stability. An audit of upstream changes between
v3.38.0 (fork point `41de3b7c`, 2026-05-12) and v3.48.0 found these contract changes
relevant to the operator:

| Endpoint area | Verdict | Detail |
|---|---|---|
| `POST /api/v1/users/signin` | unchanged | |
| `GET /api/v1/workspaces` | unchanged | |
| `GET /api/v1/system/health` | unchanged | |
| `/api/v1/notifiers` | unchanged | |
| `/api/v1/healthcheck-config` | unchanged | |
| `/api/v1/storages` | near-unchanged | `isSystem` removed from responses (harmless) |
| `/api/v1/databases/*` | **breaking** | type enum `POSTGRES` split into `POSTGRES_LOGICAL` / `POSTGRES_PHYSICAL`; request/response field `postgresql` split into `postgresqlLogical` / `postgresqlPhysical` |
| `/api/v1/backup-configs/*` | **breaking** | endpoints split into logical (`/backup-configs/save`, `/backup-configs/database/{id}`) and physical (`/backup-configs/physical/...`) paths; interval DTO renamed `interval` → `type` and no longer carries an `id`; physical configs add required retention/interval fields |

Migration scope: the operator targets **logical** backups (pg_dump-style), so only
the logical paths of each split need to be adopted. Tasks:

- [ ] Update `internal/client/database.go` for the type-enum and DTO field splits
- [ ] Update `internal/client/backup_config.go` for the logical endpoint paths and interval rename
- [ ] Drop `isSystem` from `StorageResponse`
- [ ] Update CRD enums/docs where `POSTGRES` is exposed (`DatabaseBackup.spec.database.type`)
- [ ] Update the README compatibility matrix

## 2. Contract tests in CI

Make the compatibility matrix verified instead of asserted:

- [ ] Integration test suite that runs the `internal/client` calls against a real
      databasus instance (pinned image tag + postgres) started in CI
- [ ] Pin the databasus image version in one greppable place so Renovate can bump it;
      each upstream release then arrives as a PR whose CI proves (or disproves)
      compatibility
- [ ] Internal-cluster e2e (operator deployed alongside the upstream Helm chart)
      as a Gitea-only workflow

## 3. Release engineering

- [ ] Release workflow: semver tag → build/push image to `ghcr.io/sf1tzp/databasus-operator`,
      attach install manifests (`make build-installer`)
- [ ] Versioned compatibility rows in the README (operator vX.Y ↔ databasus vA.B)

## 4. Later ideas

- Runtime version check: warn (via a status condition) when the connected databasus
  version is outside the tested range
- Surface upstream's backup-verification feature (v3.34+) in the CRDs
- Helm chart for the operator itself
