---
name: postgres-operator-major-upgrade
description: >-
  Use when raising the major PostgreSQL version of a Zalando postgres-operator cluster in place
  (for example 14 to 15): rehearsal, backups, maintenance window, and the Argo CD interplay.
version: 1.0.1
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: postgres
---

# Major version upgrade of a postgres-operator cluster

Raising `spec.postgresql.version` of a `postgresql` resource makes the operator (mode `manual`) run `pg_upgrade` in
place on the leader and rebuild the replicas.

## Role

- Act as a senior database engineer who treats the upgrade as irreversible, rehearses it on a clone, proves the backups,
  and stops on the first unexpected value.

## When to use

- A major version reaches end of life, or the operator or Spilo image would otherwise force the change.

## Constraints

- `pg_upgrade` cannot be undone. The only way back is a restore: the logical backup (state of its start time) or
  WAL-G point in time on the old lineage. The WAL path contains the major version, so the old lineage stays untouched
  and the new one has no base backup until you take one. Writes after the restart live only in the new lineage: neither
  the logical dump nor the old WAL can restore them.
- Do not upgrade the operator or the Spilo image in the same window. A new Spilo image changes every cluster of the
  operator. Check which versions the image ships (`ls /usr/lib/postgresql` in a pod) and the operator's
  `major_version_upgrade` range before you plan.
- Standby clusters and anything that reads the old WAL path break after the upgrade and must be rebuilt. A resource
  that only looks like a standby may be an independent cluster: check for a `standby` or `clone` section and for
  consumers before you decide to delete or upgrade it.
- Do not patch the version while Argo CD syncs the application: it applies the change with the application connected,
  or it reverts your patch (self-heal). Use `argocd-maintenance-mode`.
- Do not run queries on production database pods outside the guarded script; do not print passwords or keys.
- One cluster per window, outside the scheduled logical backups (a `pg_dump` during the upgrade fails or holds locks)
  and outside the node reboot window.

## Workflow

### 1. Inventory

List every `postgresql` resource with its version, instances, volume, StorageClass reclaim policy, backup settings,
and whether Argo CD tracks it (`argocd.argoproj.io/tracking-id`). Read the operator's upgrade mode and range. Record
the application's own compatibility (release notes for the target version).

### 2. Rehearse

- First on dev: raise the version, measure the downtime, check the application.
- Then on the production operator with a throwaway clone of the production data: a `postgresql` resource with
  `clone: {cluster, uid, timestamp}` restored from the WAL-G archive, one instance, version unchanged. The clone needs
  the S3 credentials as `CLONE_AWS_ACCESS_KEY_ID`, `CLONE_AWS_SECRET_ACCESS_KEY`, and `CLONE_AWS_REGION` in `spec.env`;
  take the values by `secretKeyRef` from the keys the source pod uses, never as literals. Without them the restore
  fails at `wal-g backup-list`.
- Use a new clone name for every attempt: with StorageClass reclaim policy `Retain` the NFS directory of the volume
  stays, and the next clone with the same name would pick it up.
- Compare the clone with the source (row counts of key tables, schema version, extensions, size), raise the version
  of the clone, and measure the time. Check `pg_upgrade` ran, tables have statistics, no invalid index.
- Delete the clone and list what stays: the PV in `Released`, the NFS directory, the WAL prefix of the clone.

### 3. Record the new state in Git

Open a pull request that sets the version value of the production stage only. The production render must differ in the
`postgresql` version and nothing else. Merge it before the window; it changes nothing until the `prod` tag moves.
Read the Copilot review after the push.

### 4. Guards (read-only, a dry run prints them all)

- A completed logical backup job that started less than three hours ago, and no backup job running.
- WAL archiver healthy (no failure newer than the last success), newest WAL-G base backup younger than 26 hours.
- Patroni: a leader in state `running`, all replicas in state `streaming` (not `running`), lag 0, the member count
  you expect.
- Free space on the data volume, the target binaries in the image, the application healthy on its current version,
  no maintenance marker, all other Applications Synced and Healthy.
- At least 75 minutes to the next scheduled logical backup.

### 5. Window

1. Maintenance mode on. Wait until no application session is left in `pg_stat_activity`.
2. Take the facts while the application is off. Gate on the logical invariants: row counts of key tables, the
   application schema version, the number of user tables, invalid indexes (must be none), and the extension names.
   Nothing can write now, so these must be identical afterwards. Record, but do not gate on, the diagnostics that a
   healthy upgrade changes: database size, catalog contents, statistics, extension versions.
3. Patch `spec.postgresql.version`. Wait for status `Running`, `PGVERSION` of every pod at the target, every pod
   ready, every Patroni member healthy, and `server_version_num` of the target on every pod (up to 40 minutes).
4. Compare the facts. Run `ANALYZE` if tables have no statistics. Stop on a difference in an invariant.
5. Take a WAL-G base backup for the new lineage with the Spilo backup script and check that the newest entry is newer
   than the upgrade. Do this before the application is switched on. If it fails, hold with the application off and
   let the user decide; only the user can accept a window of writes that cannot be recovered.
6. Move the `prod` tag to the merge commit of the pull request while the sync is paused (see
   `prod-tag-promotion` for the backup tag), then maintenance mode off.
7. Check health on all hosts, the application version, git over SSH, the logs for errors, runners, ExternalSecrets,
   and all Applications. Confirm the `postgresql` resource still says the target version.

On any failed check after step 1, stop with the application off and print what to look at. Do not switch it on by
itself.

### 6. Afterwards

Ask the user to log in, push, and run a workflow. Clean up the clone leftovers (NFS directories, PV objects, WAL
prefixes) by hand with the owner. Plan the operator and Spilo upgrade as its own window.

## Report

The versions before and after, the measured downtime, the upgrade duration per step, the facts before and after, the
backup used as the safety net, the new base backup, and what is left to clean up.
