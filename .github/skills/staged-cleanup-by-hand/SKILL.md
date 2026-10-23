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
- Do not delete objects that a live controller recreates; remove the owner (Application, operator custom resource) first.
- Do not delete persistent volumes or data on the storage server; state the reclaim policy and what stays.
- Do not run the delete without the exact confirm string that the dry run prints.

## Workflow

1. **plan** (read-only): list the candidates and the reason for each (not tracked, no consumer, no traffic, no workload uses it).
   Evidence of "unused": traffic in the ingress logs, last logins and last pushes for a service, consumers in config maps and workloads.
2. **export**: write the objects as JSON without Secrets into a private directory (mode 700) with a time stamp, plus the list of retained volumes and their paths.
3. **delete `<group>`**: refuse to run without an export of the same cluster that is less than a day old; evaluate the
   candidates again live; guard on the health of all other Applications; run `kubectl delete --dry-run=server` first;
   require `--confirm "delete <group> <count>"`.
4. Order the groups so that controllers go first: Applications, then workloads, then the database custom resources,
   then routing, then namespaces, then cluster-wide objects (roles, CRDs) last, refused while instances exist.
5. After each group: list what is left, check all Applications, check the public URLs.

## Report

Per group: objects deleted, objects left, volumes retained with their paths, and the export directory.
