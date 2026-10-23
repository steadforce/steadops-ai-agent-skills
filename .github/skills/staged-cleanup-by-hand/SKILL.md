---
name: staged-cleanup-by-hand
description: Use when removing orphaned or retired Kubernetes resources from a cluster in reviewable groups with a dry run and an export.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: kubernetes
---

# Staged cleanup of retired resources

## Role

- Act as a senior platform engineer who deletes only what is proven unused, one group at a time, with a way back.

## When to use

- Orphaned certificates and gateways, retired applications, namespaces left behind by a removed Application

## Constraints

- Do not delete in one go. Run one group, look at the cluster, then the next.
- Do not delete Secrets one by one and never export Secrets. A namespace delete removes them with it; say so first.
- Do not delete objects that a live controller recreates; remove the owner (Application, operator custom resource) first,
  but only through a verified non-cascading procedure (see the owner rule in step 4).
- Do not delete namespaces, PVCs, or database custom resources before the reclaim policy of every bound volume is
  verified as `Retain` (or the data is backed up and the owner approved). With policy `Delete` the storage goes with the
  claim. Changing a policy needs the owner's approval. Never delete persistent volumes or data on the storage server.
- Do not run the delete without the exact confirm string that the dry run prints.

## Workflow

1. **plan** (read-only): list the candidates and the reason for each (not tracked, no consumer, no traffic, no
   workload uses it).
   Evidence of "unused": traffic in the ingress logs, last logins and last pushes for a service, consumers in config
   maps and workloads.
2. **export**: write the objects as JSON without Secrets into a private directory (mode 700) with a time stamp, plus
   the list of retained volumes and their paths.
3. **delete `<group>`**: refuse to run without an export of the same cluster that is less than a day old; evaluate the
   candidates again live; guard on the health of all other Applications; run `kubectl delete --dry-run=server` first;
   require `--confirm "delete <group> <count>"`.
4. Order the groups so that controllers go first: Applications, then workloads, then the database custom resources,
   then routing, then namespaces, then cluster-wide objects (roles, CRDs) last, refused while instances exist.
   Before deleting an owner, read its finalizers (for example `resources-finalizer.argocd.argoproj.io` on an Application)
   and the behavior of its operator: a finalizer or an operator can delete all managed resources at once, which a
   server-side dry run does not show. Delete the owner only when it has no cascading finalizer, or after the owner
   approved a procedure that does not cascade (for example removing the finalizer first), and stop if the later groups
   could not be kept apart.
5. After each group: list what is left, check all Applications, check the public URLs.

## Report

Per group: objects deleted, objects left, volumes retained with their paths, and the export directory.
