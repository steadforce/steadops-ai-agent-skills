---
name: crossplane-stepwise-upgrade
description: >-
  Use when upgrading Crossplane and its providers on a production cluster that deploys from Git: the supported
  upgrade path, blockers to check, provider family handling, and the transients to expect after a provider restart.
version: 1.1.0
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
- The package manager never upgrades an installed dependency. A provider version can declare its family provider with
  an exact version (`dependsOn: provider-family-aws, version v1.23.2`) where the old one only asked for `>= 0.0.0`.
  With the older family installed, the new provider revision becomes `Active` but unhealthy (`incompatible
  dependencies: existing package ...provider-family-aws@v1.17.0 is incompatible with constraint v1.23.2`), and the old
  revision goes `Inactive` and its pod is removed, so no provider pod runs until this is fixed. Before every provider
  step read `dependsOn` of the target package (pull the package image and read `package.yaml`). If the family
  constraint is not met, upgrade the family first by patching the auto-installed `Provider` to the exact version: the
  old provider keeps running because its constraint is loose, the family is healthy after about a minute, and the
  provider step is healthy about 75 seconds after the tag move. Patching the family while the provider is stuck also
  recovers it (healthy after about 90 seconds). From the provider major version on, define the family `Provider` in Git
  under the name of the auto-installed one (it adopts it) and move both together (healthy after about 160 seconds in
  the rehearsal below). A production tag points at a commit, so a provider bump in an earlier commit cannot be skipped
  by moving to a later core step.
- A core step cannot be undone (v2 to v1 is not supported): fix forward. A provider step can be rolled back by moving
  the tag back, because Crossplane keeps the old provider revision.
- The core image may come from another registry in the new version. Check that the cluster can pull it; a pull failure
  leaves the old pod running during the rollout.
- Give buckets and other stateful managed resources `deletionPolicy: Orphan`, and find out what depends on Crossplane.
  A backup tool that writes to the bucket directly does not.
- Rehearse a provider step in a `kind` cluster that reproduces production: Crossplane core at the production version,
  the family and the provider installed by hand at the production versions (the Lock and the revision names then equal
  production). When the cluster API port is not reachable from your shell (a remote or separate container daemon), drive
  the cluster with `docker exec <node> kubectl --kubeconfig=/etc/kubernetes/admin.conf`, and pipe `helm template` output
  into `kubectl apply --server-side -f -`. Delete the cluster afterwards.

## Workflow

1. **Inventory**: core and provider versions, the managed resources and their policies, the served and stored versions
   of their CRDs.
2. **Step table**: list the `main` commits since the production tag and pick one per step (core, provider, family).
   Skip reverted commits. Put the table in the promotion script header.
3. **Per step**: guard that the live versions equal the previous step, export the Providers, runtime configs,
   ProviderConfigs, managed resources, and the package lock. For a provider step compare `dependsOn` of the target
   package with the installed family (see Constraints) and upgrade the family first when it does not satisfy it. Then
   promote. Verify the core image tag, the provider
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
