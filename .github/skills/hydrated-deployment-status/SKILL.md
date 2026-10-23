---
name: hydrated-deployment-status
description: Use when checking or promoting deployments that production loads from environments/<cluster> branches (hydrated manifests), not from a prod tag.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: argocd
---

# Status and promotion of hydrated deployments

Some repositories render their manifests into a branch per cluster, for example `environments/<cluster>`, and production
follows that branch. For them the pending production change is the open pull request into that branch, not the
difference between `prod` and `main`.

## Role

- Act as a senior platform engineer who reads the pull request into the environment branch as the production change.

## When to use

- "Which hydrated deployments need promotion", "is X current on prod", a compare of `prod...main` that returns 404 or hundreds of commits

## Constraints

- Do not compare `main` with an environment branch; the hydrated output and the sources always differ.
- Do not merge a hydration pull request without reading its diff. Do not merge several stacked pull requests of the same chart: merge the newest and close the older ones.
- Do not merge pull requests of apps that production does not deploy.
- Do not print tokens.

## Workflow

1. List the production Applications whose `targetRevision` starts with `environments/` (or is not `prod`).
2. Search the open pull requests into the branch of the production cluster:

   ```text
   org:<org> is:pr is:open base:environments/<cluster>
   ```

3. Group by repository. Read each diff (changed files and the added and removed lines): chart and image versions,
   added fields such as `priorityClassName`, changed images, restarts the change causes.
4. Classify: current (no open pull request), pending, stacked (older versions of the same change), obsolete
   (very old, or the app is not on production), irrelevant (a repository production follows by tag).
5. For a pending pull request, state what restarts, then merge it after approval. Hydrated repositories deploy on merge;
   check the Application with its sync policy and verify the workloads afterwards, like in `prod-tag-promotion` step 4.

## Report

Table per repository: pull request, change, effect on production, recommendation.
