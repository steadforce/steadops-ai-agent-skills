---
name: istio-prod-promotion
description: Use when promoting an Istio version from main to production by moving the prod tag in the istio repositories.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: argocd
---

# Promote Istio to production

Use this skill to stage an Istio version that already runs on the dev clusters to production. Production Argo CD
applications deploy each Istio repository from the annotated Git tag `prod`, so moving that tag is the deployment.

For the rules that apply to every promotion (tags only on `main` commits, render diff with the live parameters and `--api-versions`,
guarded dry-run script, time window), read `prod-tag-promotion` as well; this skill adds the Istio order and data
plane checks.

## Role

- Act as a senior platform engineer who promotes one component at a time and verifies each step before the next.
- Treat production as the quality gate: stop on any unexpected difference, failed check, or unclear state.

## Scope

- Applies to the repositories `istio-cni`, `istio-deployment` (base and istiod), `istio-ingress`, and `istio-egress`.
- Covers the diff review, the backup tag, the `prod` tag move, verification, and rollback.
- Does not cover the dev upgrade itself (Renovate pull requests on `main`) or minor version jumps of more than one.

## When to use

Use this skill for requests like:

- "Promote Istio 1.x to prod"
- "Stage istio-cni / istiod / the gateways to production"
- "Move the prod tag of the istio repositories"

## Prerequisites

- The target version runs on dev with all proxies updated and no errors.
- Production runs at most one minor version below the target. Istio supports upgrades of one minor version only.
- A kubeconfig for the production cluster and for the dev cluster.
- Push access to the four repositories. When tags are created through the GitHub API instead of `git push`, the token
  needs `Contents: write` **and** `Workflows: write`; without the latter GitHub answers
  `403 Resource not accessible by personal access token` for commits that touch workflow files.
- A quiet time window: the istiod step restarts every workload with a sidecar once.

## Constraints

- Do not change the order: `istio-cni` → `istio-deployment` → `istio-ingress` → `istio-egress`.
- Do not move `prod` before the backup tag of the current `prod` exists.
- Do not start the next step before the previous one is Synced, Healthy, and verified.
- Do not use lightweight tags; both the backup tag and `prod` are annotated with the message `Staged to prod`.
- Do not sync, patch, or restart production resources by hand; Argo CD applies the tag move.
- Do not rely on `istioctl proxy-status` to find outdated proxies; it misses proxies that are still reconnecting
  right after the istiod rollout. Read the proxy image tags from the pod specs instead.
- Do not confuse a tag object SHA with a commit SHA; always resolve tags with `^{commit}`.
- Do not print tokens or secrets in logs or reports.

## Workflow

### 1. Inventory

Read the production Argo CD applications and record source, target revision, value files, Helm parameters, and the
deployed commit:

```sh
kubectl -n argocd get application istio istio-cni istio-ingress istio-egress \
  -o custom-columns='NAME:.metadata.name,REV:.spec.source.targetRevision,SYNC:.status.sync.status,HEALTH:.status.health.status,AT:.status.sync.revision'
```

For each repository, fetch the tags and compare `prod` with `main`:

```sh
git fetch origin main
git fetch --force origin 'refs/tags/prod*:refs/tags/prod*'
git rev-parse 'prod^{commit}' origin/main
git log --oneline 'prod^{commit}..origin/main'
```

Pick the target commit per repository: the `main` commit that contains the target version and nothing that must not
reach production yet.

### 2. Review what changes on production

Render the current `prod` commit and the target commit with the production value files, the Helm parameters, and any
inline `helm.values` of the Argo CD application, then diff the output. Use the Helm major version Argo CD uses.

```sh
helm template <release> . -n <namespace> --kube-version <cluster version> \
  -f values-subchart-overrides.yaml -f values-production.yaml -f values-<cluster>.yaml \
  --set global.stage=production --set global.clusterName=<cluster>
```

Accept only upstream chart changes of the new version (CRDs, injector template, labels) and changes you intended,
such as an update job fix. Investigate everything else before continuing.

### 3. Pre-checks on production

- istiod, ingress, and egress run at least 2 replicas; istiod has a `PodDisruptionBudget`.
- The Kubernetes version is supported by the target Istio version.
- Note the number of proxies and their version, and the applications that are already Degraded, as a baseline:

```sh
kubectl get pods -A -o jsonpath='{range .items[*]}{.spec.containers[?(@.name=="istio-proxy")].image}{.spec.initContainers[?(@.name=="istio-proxy")].image}{"\n"}{end}' \
  | grep . | sort | uniq -c
kubectl -n argocd get applications --no-headers \
  -o custom-columns=N:.metadata.name,S:.status.sync.status,H:.status.health.status | awk '$3!="Healthy"'
```

### 4. Promote one repository

Run in the local clone of the repository. The backup tag is named after the tag date of the current `prod` in German
local time and points to the current `prod` commit:

```sh
git fetch origin main
git fetch --force origin 'refs/tags/prod*:refs/tags/prod*'
old=$(git rev-parse 'prod^{commit}')
expected_prod=$(git rev-parse refs/tags/prod)   # tag object as fetched; the push below fails if it changed since
backup="prod-$(TZ=Europe/Berlin git for-each-ref --format='%(taggerdate:format-local:%Y%m%d-%H%M%S)' refs/tags/prod)"
echo "$backup -> $old"
git tag -a -m "Staged to prod" "$backup" "$old" \
  && git push origin "refs/tags/$backup" \
  && [ "$(git ls-remote origin "refs/tags/$backup^{}" | cut -f1)" = "$old" ] \
  && git tag -a -f -m "Staged to prod" prod <target commit> \
  && git push --force-with-lease="refs/tags/prod:$expected_prod" origin refs/tags/prod
```

The chain moves `prod` only after the backup tag exists on the remote and points to `$old`, and `--force-with-lease` makes
the push fail when someone else moved `prod` after your fetch. Do not split it into separate commands and do not use a
plain `-f`. Stop when `$backup` already exists or `$old` is not the commit Argo CD reports as deployed.

### 5. Verify after each step

| Step | Check |
| --- | --- |
| `istio-cni` | DaemonSet `istio-cni-node` rolled out on every node with the new image; no errors in its logs |
| `istio-deployment` | istiod rolled out with the new `pilot` image; the PostSync job `update-istio-dataplane` succeeded |
| `istio-ingress`, `istio-egress` | Deployment rolled out, all replicas ready, chart label shows the new version |
| every step | Argo CD application Synced and Healthy on the target commit; no new non-running pods; main URLs answer |

For the istiod step, follow the job log. The job waits for the istiod rollout, reads the target version from the
istiod image, and restarts one workload at a time:

```sh
kubectl -n istio-system logs -f job/update-istio-dataplane
```

A job pod that starts while the Argo CD sync is still running is expected; it only continues after istiod is rolled
out. When the job is done, every proxy must run the new version (the baseline command from step 3). The job also
restarts the gateway pods, so the gateway steps afterwards only change chart labels.

### 6. Roll back

Move `prod` back to the commit of the backup tag and push it; Argo CD restores the previous version:

```sh
git fetch --force origin 'refs/tags/prod*:refs/tags/prod*'
expected_prod=$(git rev-parse refs/tags/prod)
git tag -a -f -m "Staged to prod" prod "<backup tag>^{commit}" \
  && git push --force-with-lease="refs/tags/prod:$expected_prod" origin refs/tags/prod
```

If the push is rejected, someone moved `prod` after your fetch. Read the new state before rolling back, so you do
not undo a newer promotion.

Roll back in reverse order (`istio-egress` → `istio-ingress` → `istio-deployment` → `istio-cni`). After rolling back
istiod, restart the workloads again so the proxies match the control plane.

## Report

Summarize per repository: backup tag and commit, new `prod` commit, time, and the verification result. List the
proxy count per version before and after, restarts done by the update job, and any warning or deviation.
