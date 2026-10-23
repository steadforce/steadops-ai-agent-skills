---
name: prod-tag-promotion
description: Use when promoting any deployment repository to production by moving its prod tag, or when listing what still needs promotion.
version: 1.0.0
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
  monitoring, external-secrets). Without them whole templates render empty and the diff looks clean.
- Check removed objects, changed CRDs, replaced workloads, changed namespace labels (compare with the live namespaces),
  and values of other Applications that the change feeds (for example an app-of-apps entry that drives a gateway chart).
- Explain every difference. Investigate the rest before going on.

### 3. Write a guarded script

Create one script per promotion (copy the latest) with:

- the reviewed target commit and the expected current `prod` commit as guards;
- all Applications Synced and Healthy with no running sync (name known exceptions explicitly in the script);
- the time window and token validity checks;
- a dry run by default that prints the plan and the exact `--confirm "promote <name> <7 chars>"` string;
- tag handling in a temporary bare repository (backup tag, then `prod` pushed with `--force-with-lease` against the
  tag object read before), a wait loop that survives restarts of the controller, and result checks (pods, images,
  URLs, all Applications).

Put the review result in the script header: what changes, what happens at once, what is not done, the rollback.

### 4. Run and verify

Run the dry run, show the result, and wait for the explicit approval of the user. Then run with the confirm string and
verify: Application Synced and Healthy on the target commit, workloads ready on the new images, main URLs answer, no
new alerts, all other Applications healthy.

### 5. Roll back

Move `prod` back to the backup tag commit and push it; Argo CD restores the previous state. State what the rollback does
not undo (applied CRDs, pruned objects, restarted pods).

## Report

Name the backup tag and commit, the new `prod` commit, the time, what changed, the verification result, and what is
still open.
