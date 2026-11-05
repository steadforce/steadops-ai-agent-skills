---
name: prod-tag-promotion
description: Use when promoting any deployment repository to production by moving its prod tag, or when listing what still needs promotion.
version: 1.3.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: argocd
---

# Promote a deployment repository to production

Use this skill for every Argo CD application that production deploys from the annotated Git tag `prod`. Moving the tag is
the deployment. For Istio use `istio-prod-promotion`, which adds the order and the data plane checks. For repositories
on `environments/<cluster>` branches use `hydrated-deployment-status` instead; they have no `prod` tag.

## Role

- Act as a senior platform engineer who changes production only after a reviewed render diff, a dry run, and a backup tag.
- Stop on any unexpected difference, failed guard, or unclear state.

## When to use

- "Promote X to prod", "move the prod tag of X", "what needs promotion to production"

## Constraints

- Put `prod` only on commits of `main`. A change goes through a pull request and a squash merge first; tag the merge commit.
  Ask before moving a tag that sits on a branch commit.
- Create the annotated backup tag `prod-<tag date, German time>` before the move. Annotate `prod` with `Staged to prod`.
- Do not hand-edit, sync, or restart production resources; Argo CD applies the tag move (check the sync policy first: with
  auto-sync and prune a removed object is deleted at once, with prune off it only shows as out of sync).
- Do not promote a commit you have not rendered and diffed. Do not promote `main` blindly after other pull requests merged.
- Do not print tokens. Use `http.extraheader` or an `Authorization` header, never a token in a URL.
- Move tags only inside the allowed time window (not during the node reboot window) and only with a token valid for
  two more hours.
- Never reuse a confirm string from an earlier promotion; it contains the target commit.
- When the change migrates data (database schema, a major version), require a completed backup that started less than
  three hours ago and name the restore path. Moving the tag back does not undo a migration.
- When the upgrade path is supported only one minor version at a time, promote one `main` commit per run in that order
  (see "Stepwise promotion"). Do not move `prod` straight to `main`.
- When the change must be applied by hand first (a database major upgrade) and Argo CD would undo or mis-time it, use
  `argocd-maintenance-mode` and `postgres-operator-major-upgrade` instead of a plain tag move.
- After every push to a pull request branch, read the Copilot review (reviews and inline comments) and fix the findings
  that are sensible on the same branch. Do not merge with open findings. Do not name local-only scripts in committed
  comments; a reviewer cannot open them.

## Workflow

### 1. Inventory

List the application's source, target revision, value files, parameters, and inline `helm.values` from the live
Application. Compare the current `prod` commit (resolve with `^{commit}`) with `main`:

```sh
kubectl -n argocd get application <app> -o jsonpath='{.spec.source}{"\n"}{.status.sync.revision}{"\n"}'
git fetch origin main
git fetch origin '+refs/tags/prod:refs/tags/prod'
git log --oneline 'prod^{commit}..origin/main'
```

To find everything that needs promotion, read the source repository and `targetRevision` of every production Application,
then compare each `prod` with `main`. Count only commits that touch more than tests, workflows, and Markdown.

### 2. Review the production render

Render the current and the target commit with the production value files, the live Helm parameters, and inline values;
diff per object, keyed by API group, kind, namespace, and name (`kind/name` alone merges objects of different
namespaces or groups and hides changes), not per line.

- Use the Helm major version of Argo CD and render from `git archive` copies inside the workspace; Docker cannot see
  the scratchpad. A missing value file is not an error when the application sets `ignoreMissingValueFiles`.
- Pass `--api-versions` for every CRD group the chart checks with `.Capabilities.APIVersions.Has` (Istio, cert-manager,
  monitoring, external-secrets), with exactly the string the template tests: `pkg.crossplane.io/v1` satisfies
  `Has "pkg.crossplane.io/v1"`, while `pkg.crossplane.io/v1/Provider` does not. The reverse holds as well:
  `kubectl api-versions` lists only `group/version`, so a template that tests the kind form (Harbor alerts:
  `Has "monitoring.coreos.com/v1/PrometheusRule"`) renders empty. Grep the templates for `Has "` and pass each string as
  written. Without them whole templates render empty and the diff looks clean. Compare the object count before and
  after to catch it.
- Render the current commit twice before you trust a diff. Charts that generate secrets or certificates at render time
  (`randAlphaNum`, `genSignedCert`; the Harbor chart does) differ on every render in Secrets and in `checksum/...` pod
  annotations. Leave Secrets and checksum lines out of the comparison and check that the Application's
  `ignoreDifferences` covers those annotations (otherwise a sync would roll the pods). When you show a diff, list kinds
  and names only: a raw diff of rendered manifests prints private keys into the log.
- Stop when `git fetch` or `git worktree add` fails. A loop that carries on renders the working copy and compares the
  wrong trees. When the remote is SSH and not usable from the shell, fetch from the HTTPS URL with `http.extraheader`
  and use `FETCH_HEAD`.
- Check removed objects, changed CRDs, replaced workloads, changed namespace labels (compare with the live namespaces),
  and values of other Applications that the change feeds (for example an app-of-apps entry that drives a gateway chart).
- Explain every difference. Investigate the rest before going on.

### 3. Write a guarded script

Create one script per promotion (copy the latest) with:

- the reviewed target commit and the expected current `prod` commit as guards;
- all Applications Synced and Healthy with no running sync (name known exceptions explicitly in the script);
- the time window and token validity checks;
- a dry run by default that prints the plan and the exact `--confirm "promote <name> <7 chars>"` string;
- for migrations: the backup guard (a completed job that started less than three hours ago; do not wait for a new one if
  it takes an hour) and a measured downtime in the report. Start the backup yourself beforehand with
  `kubectl create job --from=cronjob/<logical backup>` when the last one is older (Gitea: about 70 minutes), run the
  script after it completed, and keep 75 minutes free before the next scheduled run. Check WAL archiving on the
  database master: `archive_mode` on, `failed_count` 0, `last_archived_time` a few minutes old (`pg_stat_archiver`);
- tag handling in a temporary bare repository (backup tag, then `prod` pushed with `--force-with-lease` against the
  tag object read before), a wait loop that survives restarts of the controller, and result checks (pods, images,
  URLs, all Applications).

Put the review result in the script header: what changes, what happens at once, what is not done, the rollback.

Run a long script in the background and read its log file afterwards. Do not let the script write to the file its own
output is redirected to (`tee /dev/stderr` inside `> log` truncates it); the live state is the final check anyway.

### Stepwise promotion

When a vendor supports an upgrade only through intermediate versions (for example Crossplane v1.19, v1.20, v2.0, v2.1,
v2.2), list the `main` commits since `prod` and pick one per step. Skip commits that were reverted or that leave a
dependency half done (a provider that needs a sibling package in the same commit).

- Put the step table (commit, versions, what changes) in the script header and let `--status` print it.
- Derive the current step from the `prod` tag and allow only the next one. A guard compares the live versions with the
  step table before the move and a wait loop compares them after it.
- Mark the steps that cannot be undone (a core downgrade is not supported) and wait between steps.
- Stop on the first failed check; never continue with the next step on a warning you have not read.
- Retry the final checks for about 90 seconds. A provider restart makes the Argo CD health flip to Degraded for a
  moment and delays a conversion webhook for minutes; see `crossplane-stepwise-upgrade` before you call that a failure.

### 4. Run and verify

Run the dry run, show the result, and wait for the explicit approval of the user. Then run with the confirm string and
verify: Application Synced and Healthy on the target commit, workloads ready on the new images, main URLs answer, no
new alerts, all other Applications healthy.

When a change must not restart anything, record the pod UIDs before and compare them after: that proves it (Harbor
alerts: no pod replaced). Do not check for a log line that a pod writes only at its start (a runner's `declare
successfully`): pods that were not restarted do not repeat it. For them check that the errors of the outage
(`failed to fetch task`) stop, and run the smoke test.

A check that only looks at ready pods misses pods that never started. After the move compare updated, ready, and
desired replicas of every StatefulSet and Deployment the change touches (an HorizontalPodAutoscaler may have raised
the desired count), list pods in `Init`, `CrashLoopBackOff`, or `Error`, and read one new pod's init container log.
A vendor upgrade can remove an API route that an init script still calls: Gitea 1.26 removed the admin runner
registration route, and new runner pods crash-looped until the template used the new path. Run a smoke test with a
non-admin user after every promotion of an application, and test the pod start path, not only the running pods.

### Alert rules (PrometheusRule)

- Evaluate every `expr` against the production Prometheus before the move (`/api/v1/query`). An expression that returns
  series fires at once: that is a finding. Name the expected one in the script (Harbor: `HarborProjectQuotaFillsSoon`,
  buildcache predicted to fill its limit) and fail on any other pending or firing alert after the load.
- Guard: the CRD exists, the Prometheus `ruleSelector` label matches the label of the rule, no rule of that name exists
  yet, the targets the rules need are up.
- After the move wait 70 to 120 seconds for the rule load, then read `/api/v1/rules?type=alert` for the group: every
  alert present, health `ok`, state as expected. State whether Alertmanager is on: without it nothing is notified.

### 5. Roll back

Move `prod` back to the backup tag commit and push it; Argo CD restores the previous state. State what the rollback does
not undo (applied CRDs, pruned objects, restarted pods, migrated databases, a core that cannot be downgraded). For a
migration the way back is the restore of the backup, not the tag.

Roll back only if nobody promoted again in the meantime:

```sh
git fetch --force origin 'refs/tags/prod*:refs/tags/prod*'
[ "$(git rev-parse 'prod^{commit}')" = "<target commit recorded for this rollout>" ] \
  && expected_prod=$(git rev-parse refs/tags/prod) \
  && git tag -a -f -m "Staged to prod" prod "<backup tag>^{commit}" \
  && git push --force-with-lease="refs/tags/prod:$expected_prod" origin refs/tags/prod
```

Stop if the fetched `prod` commit differs from the recorded target: someone promoted again, and moving the tag back
would undo that deployment. The lease protects against a move after the check. Record the full target commit when you
promote.

## Report

Name the backup tag and commit, the new `prod` commit, the time, what changed, the verification result, and what is
still open.
