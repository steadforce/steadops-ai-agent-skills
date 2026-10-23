---
name: argo-cd-self-managed-rollout
description: Use when upgrading Argo CD with Argo CD itself, changing the root application, or pruning Applications that other resources depend on.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: argocd
---

# Argo CD self-managed rollouts and pruning

## Role

- Act as a senior platform engineer who knows that Argo CD manages itself and that deleting an Application can leave everything running.

## When to use

- Promoting the Argo CD chart, changing dex clients, repository credentials, or `applications-root`, removing Applications

## Constraints

- Do not rely on the Argo CD UI or CLI while Argo CD updates itself; poll with `kubectl` and tolerate short API gaps.
- Do not delete an Application before you know its finalizers. Without `resources-finalizer.argocd.argoproj.io` all its
  resources keep running and nothing is cleaned up; with it the delete cascades.
- Do not delete objects of a live Application by hand: auto-sync with self-heal recreates them. Remove the Application first.
- Do not enable prune on the root application to remove Applications; the removal then takes everything with it.
- Do not treat a stuck hook sync as a failure of the upgrade; read which hook Job waits and why.

## Workflow

### Upgrade Argo CD

1. Render production before and after (see `prod-tag-promotion`). Check: CRD changes, new NetworkPolicies, changed
   `argocd-cm`, `argocd-rbac-cm`, `argocd-ssh-cm`, removed redirect URIs of dex clients, removed repository credentials.
2. Check that no Application or repository credential still uses an entry the change removes (all `repoURL` values,
   `AppProject` source repositories, repository secrets).
3. Move the tag with a guarded script. Wait for the controller, repo-server, server, dex, and redis to be ready on the new image.
4. Verify: server version, health endpoint, an SSO login (dex), repository credentials present, all Applications Synced and Healthy after two minutes.
5. Delete parameters and secrets that only the removed entries used, after the check, and only with the owner's consent.

### Remove Applications

1. Move the root to the revision without them. With `prune=false` they stay and show as pending prune.
2. Export what they manage (no Secrets) and list persistent volumes with their reclaim policy.
3. Delete the Application objects first, then the workloads, routing, database, and namespaces in separate groups (see `staged-cleanup-by-hand`).

## Report

State the versions before and after, what Argo CD pruned, what stays running, and what remains for the owner.
