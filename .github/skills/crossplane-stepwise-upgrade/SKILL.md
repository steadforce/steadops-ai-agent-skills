---
name: crossplane-stepwise-upgrade
description: >-
  Use when upgrading Crossplane and its providers on a production cluster that deploys from Git: the supported
  upgrade path, blockers to check, provider family handling, and the transients to expect after a provider restart.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: crossplane
---

# Stepwise Crossplane upgrade

Use it with `prod-tag-promotion`: every step is one promotion of a `main` commit with its own guards and checks.

## Role

- Act as a senior platform engineer who upgrades one supported step at a time, checks what the cluster really runs
  before and after each step, and does not judge a step before the known transients are over.

## When to use

- The core is more than one minor version behind, or a provider major version is due (for example v1 to v2).

## Constraints

- Crossplane v2 is reachable only from v1.20, and each minor version is a step: v1.19, v1.20, v2.0, v2.1, v2.2. Do not
  move the production tag from the old state straight to `main`.
- Check the blockers on the live cluster before step one: Compositions, XRDs, Usages, EnvironmentConfigs, objects of
  kinds that v2 removes (ControllerConfig), external secret stores, and package names that are not fully qualified.
  Production that uses none of them has a short list of risks.
- The package manager never upgrades an installed dependency. A provider that needs a matching family provider stays
  stuck on the old family. Define the family `Provider` in Git under the name of the auto-installed one (it adopts it)
  and move both together. Do not stop on a commit that moves the provider to a new major version without that
  definition.
- A core step cannot be undone (v2 to v1 is not supported): fix forward. A provider step can be rolled back by moving
  the tag back, because Crossplane keeps the old provider revision.
- The core image may come from another registry in the new version. Check that the cluster can pull it; a pull failure
  leaves the old pod running during the rollout.
- Give buckets and other stateful managed resources `deletionPolicy: Orphan`, and find out what depends on Crossplane.
  A backup tool that writes to the bucket directly does not.

## Workflow

1. **Inventory**: core and provider versions, the managed resources and their policies, the served and stored versions
   of their CRDs.
2. **Step table**: list the `main` commits since the production tag and pick one per step (core, provider, family).
   Skip reverted commits. Put the table in the promotion script header.
3. **Per step**: guard that the live versions equal the previous step, export the Providers, runtime configs,
   ProviderConfigs, managed resources, and the package lock, then promote. Verify the core image tag, the provider
   packages (Installed and Healthy), the managed resources (Synced, Ready, spec unchanged), all pods Ready, 60 seconds
   without restarts, and the logs.
4. **Expect transients after a provider pod is replaced**:
   - The pod is Ready before its conversion webhook (port 9443) answers. For about two to five minutes reading a
     resource in a served version other than the stored one fails with `conversion webhook ... connection refused`,
     while the resource itself stays Synced and Ready. Reading the stored version through the raw API path works.
   - Argo CD shows the application as Degraded for a moment while the pods roll.
   - Retry the final checks for about 90 seconds and wait five minutes before you treat either as a failure.
5. Stop on the first failed check that does not clear. Do not run the next step on a warning you have not read.

## Report

Per step: the commit, the versions before and after, what the checks showed, the transients you saw, and the next
step with its risk (core steps are one way).
