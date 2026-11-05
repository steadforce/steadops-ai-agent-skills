---
name: node-disk-triage
description: >-
  Use when a Kubernetes node runs low on disk or CI jobs fail with "no space left on device": find what fills the
  disk, free it safely, and set a permanent limit.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: kubernetes
---

# Triage of a node that runs out of disk

## Role

- Act as a senior platform engineer who measures before deleting, frees only what is provably unused, and sets a limit
  so the problem does not come back.

## When to use

- A node is above 85 percent, DiskPressure is near, pods are evicted, or a job fails with `no space left on device`.

## Constraints

- You usually have no shell on the node. Read from the Kubernetes API and ask the user to run the node commands.
- Do not run `docker system prune` or delete directories on a node. Free journals, package caches, and unused images
  only, and only after you saw their size.
- Do not start more image pulls (tests, CI runs) on a node that is above 85 percent: each fresh job image adds gigabytes.
- Do not guess the runtime. `crictl` may not exist: read `containerRuntimeVersion` of the node first.

## Workflow

1. **Measure from the API**: `kubectl get --raw /api/v1/nodes/<node>/proxy/stats/summary` shows the node filesystem
   (capacity, used, available), the image filesystem, and the ephemeral storage of every pod. Compare all nodes of the
   cluster. Images, pod storage, and the rest (OS, journal, runtime store) add up to the used space.
2. **On the node** (the user runs them): `du -xh --max-depth=2 / | sort -h | tail -20`, `journalctl --disk-usage`, and
   for a Docker runtime `docker system df` (for containerd use `crictl images`). If every image is in use and nothing
   is reclaimable, an image prune frees nothing.
3. **Free**: the journal first (`journalctl --rotate`, then `journalctl --vacuum-size=500M`; vacuum alone leaves the
   active file), then the package cache (`apt-get clean`) and old kernels if you know the running one.
4. **Limit permanently** with a drop-in file `/etc/systemd/journald.conf.d/50-size.conf` that sets `SystemMaxUse`,
   `SystemKeepFree`, and `SystemMaxFileSize`, then restart `systemd-journald`. A manual vacuum is a one-off.
   On nodes managed by a configuration tool such as puppet, check after the next run that the file survived; if the tool
   purges the directory, the setting belongs in its code. The agent catalog may not be where you expect it.
5. **Structural**: a disk that holds 18 GB of images that are all in use is too small. Enlarge it, or keep the heavy
   workloads and the CI runners' docker data off the node root disk (a volume with a size limit). The kubelet cleans
   images above about 85 percent and evicts below about 10 percent free.
6. To read the oldest journal entry, run `journalctl --no-pager | head -n 2` or `journalctl --list-boots`. Note that
   `journalctl -n 1` shows the NEWEST entry.

## Report

The numbers before and after (used, available, images, journal), what was freed, what stays, and the permanent limit.
