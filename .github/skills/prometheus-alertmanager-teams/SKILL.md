---
name: prometheus-alertmanager-teams
description: Use when enabling Alertmanager with Microsoft Teams channels per cluster, adding a cluster channel, or testing alert delivery.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: argocd
---

# Alertmanager with one Teams channel per cluster

## Role

- Act as a senior platform engineer who treats webhook URLs as secrets and verifies delivery with a test alert.

## When to use

- Enabling Alertmanager on a cluster, adding or changing a cluster channel, alerts do not arrive, muting a known noisy alert

## Constraints

- Do not print, log, commit, or paste a webhook URL. Verify by hash or equality only, keep the file mode 600, and `shred -u` it once the parameter is proven.
- Do not store one webhook for a whole stage. One channel per cluster, parameter path `/<stage>/<cluster>/<app>/<name>`;
  use the account of the cluster's stage for the parameter (dev clusters share one account, production has its own).
- Do not leave a cluster out of the list of channels: alerts of a cluster without a channel go to a receiver without an integration and are dropped silently.
- Do not give Alertmanager an Istio sidecar if the Power Platform host must be reachable; test the egress from a pod without a sidecar first.
- Do not mute a real fault. Every mute names the reason and the change that removes it (for example a Phase that deletes the app).
- Do not promote before you know which alerts are firing; they are posted to the channel at once.

## Workflow

1. Create the channel and the workflow ("Send webhook alerts to a channel" template), save the URL to a private file.
2. Create the parameter in the account of the stage, read it back through the cluster's secret store (a temporary
   ExternalSecret) and compare it with the file by hash. Never display it.
3. Add the cluster to the list of channels in the chart values; the render then contains the Teams receiver and the ExternalSecret.
4. Check the render: AlertmanagerConfig routes, mutes (`Watchdog`, `InfoInhibitor`, severity `info`, known down targets),
   inhibition of warnings by critical alerts, replicas and anti-affinity (single replica on one-node clusters).
5. Promote (see `prod-tag-promotion`). Verify: Alertmanager cluster `ready` with all peers, Prometheus lists every
   Alertmanager as active, the ExternalSecret is synced.
6. Send a test alert with `amtool alert add` (end time five minutes ahead, quote the annotation) and ask the owner to confirm it in the right channel and the resolve message.

## Report

Per cluster: channel, parameter path (never the value), test alert result, mutes with their reasons.
