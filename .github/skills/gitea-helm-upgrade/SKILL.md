---
name: gitea-helm-upgrade
description: >-
  Use when promoting a Gitea Helm chart or application upgrade to production: schema migration, backup guard,
  removed config and API routes, runner pods, and verification.
version: 1.1.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: gitea
---

# Gitea upgrade through the Helm chart

Use it with `prod-tag-promotion` for every Gitea chart or application bump. Gitea runs as one replica with the
`Recreate` strategy, so a promotion restarts it, migrates the database, and takes it down for a short time.

## Role

- Act as a senior platform engineer who treats the first start of a new Gitea version as an irreversible database
  change and checks everything that talks to Gitea, not only Gitea itself.

## When to use

- Renovate opens a chart pull request, or a Gitea release has to reach production.

## Constraints

- The first start of a new version migrates the schema and it cannot be undone. Moving the tag back restarts the old
  pod on the migrated schema. The way back is a restore. Require a completed logical backup that started less than three
  hours ago, and WAL archiving, before the tag moves.
- Go one minor version at a time (for example 1.24, 1.25, 1.26). Configure Renovate to open separate pull requests
  (`separateMultipleMajor` and `separateMultipleMinor` for the chart) so a major or minor jump is never merged by
  accident. Test each step on the development stage first and promote only a commit you rendered and diffed.
- Do not change the PostgreSQL major version in the same window as a Gitea upgrade. Promote Gitea first, then the
  database (`postgres-operator-major-upgrade`).
- Do not assume that nothing else uses Gitea. Look at every workload that calls it (runners, exporters, webhooks,
  init containers).
- Expect a short outage and measure it. Gitea 1.25 took about 30 seconds and 1.26 about 110 seconds on the production
  database; 28.3.0 took about 36 seconds (schema 343 to 358).
- Start the logical backup yourself when the last one is older than three hours (about 70 minutes; see
  `prod-tag-promotion`) and read WAL archiving on the master before the tag moves:
  `select last_archived_time, failed_count from pg_stat_archiver` (failed 0, last archive a few minutes old).

## Workflow

### 1. Read the release notes against our configuration

List removed or renamed settings, routes, and environment handling, then compare with the values of the chart.
Examples: from 1.26 the chart writes `app.ini` with `gitea config edit-ini --apply-env` and not with
`environment-to-ini`; 1.26 adds cross-origin protection for browser POSTs through proxies; deprecated authentication
sources disappear in 1.25.

Gitea 28 follows 1.27.3 (the 1.x line ended there). It renames the outbound host settings: `[migrations]
ALLOWED_DOMAINS` becomes `ALLOWED_HOST_LIST` plus `EGRESS_MODE` (`strict` for an explicit list), `[security]` takes
`ALLOWED_HOST_LIST` with `EGRESS_MODE=lax`, and a bare `*` is invalid (use `private,loopback`). `[actions]
RUN_RETENTION_DAYS` sets the run retention. Job-level `if:` is evaluated before the matrix, `fail-fast` is enforced, and
nested workflows have permission limits: tell the workflow owners. After the first start expect one `[E]` deprecation
line while `[migrations].ALLOWED_DOMAINS` is still in the persisted `app.ini`, possibly `[E]` lines for empty legacy
files in `/data/gitea/public` (move them away), and a warning that the old bleve index is rebuilt.

A setting that you remove from the chart values does NOT leave the configuration. The init step merges the rendered
config into the `app.ini` on the data volume (`gitea config edit-ini --apply-env`), so a renamed or moved key keeps its
old line for ever and Gitea keeps logging the deprecation. After such a change read the effective `app.ini` (the
sections only, no secrets) and the start log, not only the rendered Secret. Remove the stale line with a guarded,
one-key edit and restart Gitea, or rebuild the file with `gitea config edit-ini --config-keep-keys`. Until then count the
known deprecation line as expected in the post-start error check. The chart does not offer a reset yet; this is
requested upstream as helm-gitea issue 1117 (a related report, 1109, covers the same effect for the inline config Secret).

### 2. Probe removed routes

Request the old and the new path without credentials. `401` means the route exists, `404` means it is gone. Gitea 1.26
removed `/api/v1/admin/runners/registration-token`; the new path is `/api/v1/admin/actions/runners/registration-token`.
The act_runner init container of our chart called the old path, so every new runner pod crash-looped in `Init` while
the running ones kept working, until the template used the new path.

### 3. Diff the production render

Render the current and the target commit with the live parameters of production and diff per object. Expect the Gitea
image, chart labels, the config checksum, and the init command. A changed pod template of the runner StatefulSet rolls
all runner pods, and a running job gets the termination grace period to finish before it is killed.

### 4. Test on dev, then promote

On dev check the version, the schema migration in the log, login through the identity provider, a push, a workflow
run, a WebSocket request to `/-/ws` through the ingress (101 over HTTP/1.1), and the pods the change touches. Promote with the guarded procedure of
`prod-tag-promotion`.

### 5. Verify

- Application Synced and Healthy on the target commit; Gitea pod 1/1 on the new image; health 200 on all hosts; the
  version endpoint; SSH port; no `[E]` or `[C]` lines since the start except the known deprecation line; all
  ExternalSecrets synced.
- Runners: StatefulSet updated, ready, and desired replicas equal; no pod in `Init`, `CrashLoopBackOff`, or `Error`
  (an autoscaler may have raised the desired count). Runners whose pod template did not change keep their pods and do
  not log `declare successfully` again, so check that `failed to fetch task` errors stop after the outage instead. A
  KEDA-scaled pool may have no pods at all when idle.
- Run `gitea-smoke-test`.

## Report

The backup used, the measured downtime, the schema versions before and after, what the render diff showed, the runner
state, the smoke test result, and what is left (identity provider login and cross-origin POSTs by hand).
