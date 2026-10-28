---
name: argocd-maintenance-mode
description: Use when an application must be switched off for a maintenance window while Argo CD auto-sync is paused, for example a database major upgrade that needs the application disconnected.
version: 1.0.3
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: argocd
---

# Maintenance mode for an Argo CD application

Blocks all traffic to one application by scaling its Deployment (and, if needed, its runners or workers) to zero while
Argo CD does not scale it back. Nothing in the data is changed. Use it with `postgres-operator-major-upgrade`.

## Role

- Act as a senior platform engineer who takes an application offline on purpose, keeps the way back in the cluster, and
  never switches it on again before the maintenance work is verified.

## When to use

- A change needs the application disconnected and Argo CD would revert or race it: a database major upgrade, a
  restore, a manual migration.

## Constraints

- Do not only pause the application. Read the sync policy of its parent (the app-of-apps root) and pause the parent
  whenever it has auto-sync on, with or without `selfHeal`. With `selfHeal: true` it re-applies the child's spec from
  Git within seconds and silently restores the child's auto-sync (on dev this scaled Gitea back up after about two
  minutes). Without `selfHeal` any new root revision, such as a merged pull request or a moved tag, still syncs and
  restores it. Refuse to start when the parent is not paused.
- Pause the parent first, wait about 25 seconds until its controller is quiet, then pause the child. A sync that was
  decided before the pause still runs and undoes it (a race found in the second dev test).
- Do not start while jobs are running unless the user accepts that running jobs fail. A check for tasks that started
  in the last ten minutes misses a long job that started earlier and is still running. Ask the runners for their
  running job containers (with rootless docker in each runner pod: `docker ps` filtered on the job container name
  prefix) or ask the CI system for running jobs, and keep the recent-start check as a second signal. Prove the
  detector with a job that sleeps: a job that only prints a line is gone in seconds and slips between two polls.
- Do not scale down while a sync is pending or running. Pausing auto-sync does not cancel an operation in flight, and
  a slow hook or rollout can outlast the waits below. Require that neither Application has an `operation` and that
  `status.operationState.phase` is not `Running`, wait for it, and abort without scaling on a timeout.
- Do not rely on the pause: after scaling to zero, watch for 45 seconds that auto-sync is still off and no pod came back.
- Do not switch off on a failed check of the maintenance work. The script holds and prints what to look at; the user
  decides.
- Do not move a tag or change the target revision expecting a deployment while the mode is on: nothing syncs.
- Do not restore auto-sync before Argo CD has compared the current revision. It compares with the revision it has
  cached, and a moved tag is seen only after the next poll. With self-heal back on, a stale revision re-applies the old
  desired state over a change made by hand (a database version).

## Workflow

1. **Record the state** before changing anything: replicas of the Deployment and the runners, the application's
   `syncPolicy`, the parent's `syncPolicy`. Store it as an annotation on the Application (so `off` works from any shell)
   and in a private file with a time stamp.
2. **On**: pause the parent (if its auto-sync is on), wait, pause the child, wait until neither Application has a
   pending or running sync (abort on a timeout), scale to zero, wait until the pods are gone, check that the health
   endpoint no longer answers 200, then hold-check for 45 seconds.
   A HorizontalPodAutoscaler does not scale a target that is at zero replicas.
3. **Do the maintenance work** and verify it while the application is off. If the live resource must stay as changed
   (a database version), move the `prod` tag to the commit that records the new state before step 4, while the sync is
   still paused: nothing deploys, and Argo CD finds live equal to desired afterwards. Otherwise self-heal reverts the
   change as soon as auto-sync returns.
4. **Off**: scale back to the recorded replicas, wait for readiness and the health endpoint. Then force a hard refresh
   (`argocd.argoproj.io/refresh=hard`) while auto-sync is still paused and wait until `status.reconciledAt` is newer
   than the refresh. For a change that must stay, also wait until the resource that carries it shows Synced at the new
   revision in `status.resources`. Only then restore the recorded sync policies (child, then parent), remove the
   annotation, and wait for Synced and Healthy.
5. If the script died, restore from the state file; a `--defaults` fallback assumes one replica and auto-sync with
   prune and self-heal and must be chosen on purpose.

## Test first

Run the full cycle on the dev stage before production: on, hold for several minutes (longer than the parent's refresh),
off. Both failures above were found only by this test.

## Report

When maintenance mode went on and off, how long the application was down, the recorded and restored sync policies, and
what was verified in between.
