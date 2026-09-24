---
name: create-readme
description: >-
  Use when creating, rewriting, or validating a repository README.md,
  especially for Helm umbrella chart repositories; enforces runnable,
  verified examples.
---

# Create README

## Role

Act as a senior software engineer with strong open-source documentation
experience, and as a quality gate.
Write README files that are appealing, informative, and easy to read.

## Scope

Work only within the target repository.
Do not perform workspace-wide analysis unless explicitly requested.
In large multi-repository workspaces, use terminal discovery commands (for
example `grep -R`, `find`, `ls`) scoped to the target repository path.

Exceptions: read-only fetches outside the repository are allowed for the
inspiration READMEs listed under Content and for reusable workflows that the
repository pins (see Verify Claims).

## When to use

Use this skill when the request asks to:

- Create or rewrite a repository `README.md`.
- Improve README structure, clarity, or onboarding flow.
- Validate README formatting and markdown quality.

## Constraints

- Do not change files other than `README.md` unless explicitly requested.
  Validation artifacts are the only exception; clean them up as described in
  the validation workflow.
- Do not commit; draft the commit message only, unless the user asks to commit.
- Do not invent badges, logos, URLs, or behavior that the repository does not
  contain or confirm.
- Do not include sections like "LICENSE", "CONTRIBUTING", or "CHANGELOG";
  there are dedicated files for those.
- Do not use `--pull=always` in Docker commands unless explicitly requested.
- Do not use the term `wrapper chart`; use `umbrella chart` for charts that
  package and configure dependencies.

## Task

Review the target repository, then create or update a well-structured
`README.md`. Work in this sequence: review the repository and verify claims,
write the README, run the validation workflow, then report and draft the commit
message. Apply the Helm Charts group only when the repository contains a
`Chart.yaml`.

### Content

- Keep the README complete but concise; do not overuse emojis.
- When updating an existing README, keep content that is still accurate (for
  example maintainer-written sections, troubleshooting notes, and links), even
  if the outline below has no place for it. Report every removed section and
  the reason.
- Take inspiration from these README files for structure and tone:
  - <https://raw.githubusercontent.com/Azure-Samples/serverless-chat-langchainjs/refs/heads/main/README.md>
  - <https://raw.githubusercontent.com/Azure-Samples/serverless-recipes-javascript/refs/heads/main/README.md>
  - <https://raw.githubusercontent.com/sinedied/run-on-output/refs/heads/main/README.md>
  - <https://raw.githubusercontent.com/sinedied/smoke/refs/heads/main/README.md>
- Use GFM (GitHub Flavored Markdown), and GitHub admonition syntax
  (<https://github.com/orgs/community/discussions/16925>) where appropriate.
- If the repository contains a logo or icon, use it in the README header.
- Use a human-readable main title in Title Case (for example
  `# External Secrets Deployment`) instead of a raw repository slug such as
  `# external-secrets-deployment`.
- Use Title Case for section headings (`##`, `###`) unless the target
  repository already enforces a different heading style.
- Keep lines at or below 120 characters where possible, including table rows.
  The markdownlint config disables MD013 for tables, so shorten table cells
  instead of relying on that exemption. Check with
  `awk 'length>120{print FNR": "length}' README.md`.
- End the file with exactly one trailing newline.

### Verify Claims

Verify every behavioral claim against the file that controls it, not against
the existing README. Do not carry over statements you have not verified:

- **Renovate:** read `renovate.json` completely. Later `packageRules` override
  earlier ones, so a catch-all minor/patch automerge rule can be overridden
  for specific managers (for example `helmv3` major and minor updates).
- **CI workflows:** when a workflow only calls a reusable workflow
  (`uses: org/repo/.github/workflows/x.yaml@ref`), read that reusable workflow
  at the pinned ref, for example with
  `curl -sf https://raw.githubusercontent.com/<org>/<repo>/<ref>/.github/workflows/<file>`
  when the `gh` CLI is unavailable. Document what it actually does (for
  example opening one pull request per environment branch instead of
  committing to `main`, or sending notifications on Renovate branches).
- **Values defaults:** describe the top-level keys that `values.yaml` sets and
  the values the chart itself defines; do not restate every nested subchart
  setting. Do not claim that it sets only some keys unless you checked all of
  them.

### Snippet Formatting

- Indent each command line with a single leading space.
- Place each command option on its own line (for example `helm template \`,
  then one flag per line).
- Sort options alphabetically where that does not change command behavior.
  Sort by option name, ignoring leading dashes, and keep the image name and its
  arguments last (for example `-e`, `--entrypoint`, `--rm`, `-u`, `-v`, `-w`).
  Keep repeated options, such as several `-e` flags, together in their original
  relative order.
- Mount the repository with `-v "$(pwd):/apps"` and `-w /apps`, and document
  that commands run from the repository root.
- These formatting rules apply to top-level commands. Heredoc bodies and
  commands inside `sh -c` scripts or loops are exempt where splitting them would
  change behavior or hurt readability.

### Tooling And Containers

- Always document a containerized flow with `docker run`, and include
  `-u $(id -u)`.
- Additionally document the `SteadOps-Steadies-K8s-Workplace` workbench flow
  when the repository's docs already reference that workbench or the user asks
  for it. In that flow, list the available tools (for example `helm`, `yq`,
  `kubectl`, `hetzner-k3s`, and `act`) and run them directly from the workbench shell,
  without a `docker run` wrapper.
- Document other local binaries only when the repository states them as a
  prerequisite.
- For `yq`, `kubectl`, or `hetzner-k3s` outside the workbench flow, use
  `ghcr.io/steadforce/steadops/workbenches/k8s:main`, even if local binaries
  are available. Exception: when `yq` only feeds a Helm command in the same
  container (for example deriving repositories for `helm dependency build`),
  use `alpine/helm`, which ships `yq`.
- If the README documents markdown linting, document the same command that
  the validation workflow runs for this repository.

### Helm Charts

- For Helm commands, use the `alpine/helm` image, and set `-e HOME=/tmp` on
  every invocation, including one-liners such as
  `alpine/helm dependency update .`. As a non-root uid, Helm otherwise fails
  with `Error: mkdir /.cache: permission denied`, or, for `dependency update`
  and `build`, with
  `open /.cache/helm/repository/helm-manager-…-index.yaml…: no such file or directory`.
- For Helm `template` examples, include `--include-crds` by default.
- For helm-unittest, use the `helmunittest/helm-unittest` image and set
  `-e HELM_CACHE_HOME=/tmp/helm/.config`. The image sets `HELM_DATA_HOME`
  itself, so only the cache must be writable; without it the unittest plugin
  fails to load as a non-root uid.

Use a README outline like this for umbrella chart repositories, and drop
sections that do not apply:

```text
 Title and one-line purpose
 Overview (upstream chart, what the umbrella chart configures)
 Prerequisites
 Repository Layout (table including Chart.yaml, Chart.lock, values files, tests)
 Setup (dependency build)
 Rendering (helm template per environment)
 Testing (helm-unittest)
 CI/CD (hydration, unittest, notifications)
 Dependency Updates (Renovate, dependency update)
```

For charts with a committed `Chart.lock` (for example charts hydrated by the
`helm-hydration.yaml` reusable workflow in `steadforce/steadops-workflows` v4+,
which runs `helm dependency build` when `Chart.lock` exists and falls back to
`helm dependency update` with a warning otherwise; verify this at the pinned
ref):

- Do not describe `Chart.lock` as generated or gitignored; only `charts/` is
  gitignored.
- Document `helm dependency build` for setting up after cloning and after any
  pull that changes `Chart.lock`.
- Document `helm dependency update` separately, only for regenerating
  `Chart.lock` after a dependency change in `Chart.yaml`, and state that the
  new lock must be committed together with `Chart.yaml`.
- List `Chart.lock` in the repository layout table.

Before `helm dependency build`, register the HTTP(S) dependency repositories.
`build` resolves them by registered name and fails on a fresh Helm home with
`Error: no repository definition for https://…/. Please add the missing repos
via 'helm repo add'`. Do not hardcode `helm repo add` per dependency; derive
the repositories from `Chart.yaml` the way the pipeline does:

- Use `explode(.)`, because `Chart.yaml` often sets dependency names through
  YAML anchors.
- Include only `http*` repositories, because `oci://` and `file://`
  dependencies need no repo entry.
- Pass `--force-update`, which makes the command idempotent, repoints a
  same-named repo to the URL in `Chart.yaml`, and matches the pipeline.
- Dependencies with `repository: "@<alias>"` are skipped by this filter but
  still need that repo registered; document the matching `helm repo add` for
  them.

Workbench flow (include it when the workbench flow applies), where `helm` and
`yq` run directly:

```sh
 yq 'explode(.) | .dependencies[] | select(.repository == "http*") | .name + " " + .repository' Chart.yaml |
   while read -r name repo; do helm repo add --force-update "$name" "$repo"; done
 helm dependency build .
```

Containerized flow: `alpine/helm` ships `yq`, so run both steps in one
container by overriding the entrypoint:

```sh
 docker run \
   -e HOME=/tmp \
   --entrypoint sh \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   alpine/helm -c '
     yq "explode(.) | .dependencies[] | select(.repository == \"http*\") | .name + \" \" + .repository" Chart.yaml |
       while read -r name repo; do helm repo add --force-update "$name" "$repo"; done &&
     helm dependency build .
   '
```

### Commit Message

As the final step, draft a commit message for the README change with the
`commit-messages` skill. Detect the project convention first from
repository guidance (for example `.github/copilot-instructions.md`) and
`git log --oneline -20`.

## Deliverable expectations

When done, report:

- whether `README.md` was created or updated
- which repository inputs were reviewed (for example chart files, scripts, docs)
- which sections were added, removed, or reorganized
- notable command examples included (workbench vs containerized)
- which files were changed
- which validation command(s) were run, with final pass/fail counts
- the result of each documented shell snippet, including those not executed
- confirmation that every `alpine/helm` invocation in the README sets `-e HOME=/tmp`
- the output of the line-length check, including table rows
- remaining documentation gaps, if any
- drafted commit message text, how commit style was detected, and
  subject/body conformance checks

## Validation workflow

Validate `README.md` with markdownlint, using image
`ghcr.io/igorshubovych/markdownlint-cli:v0.49.1`. The version is pinned because
`"default": true` enables new rules automatically; when bumping it, check the
new rules and update `references/markdownlint.json` in the same change.

If the target repository has its own markdownlint config (for example
`.markdownlint.json`, `.markdownlint.yaml`, or `.markdownlint-cli2.*`), lint
with that config so the result matches the repository's CI, for example by
passing `-c .markdownlint.json` to the same image.

Otherwise, inline the skill config through a heredoc instead of mounting
`references/markdownlint.json`: that file lives in this skill repository, not
in the target repository, so it is not available under `/apps`.
`references/markdownlint.json` is the source of truth; keep the inline JSON
identical to it. Run from the target repository root:

```sh
 docker run \
   --entrypoint sh \
   --rm \
   -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   ghcr.io/igorshubovych/markdownlint-cli:v0.49.1 -c '
    cat > /tmp/markdownlint.json <<'"'"'JSON'"'"'
{
  "default": true,
  "MD013": {
    "line_length": 120,
    "code_blocks": false,
    "tables": false
  },
  "MD060": false
}
JSON
    markdownlint -c /tmp/markdownlint.json README.md
   '
```

A passing markdownlint run only proves the markdown is valid. Before writing the
report, also execute the shell snippets documented in the README from the
repository root and record the result of each.

- Execute only commands that change nothing outside the working tree and
  fetch only from chart or image registries: for example
  `helm dependency build` and `update`, `helm template`, helm-unittest, render
  loops, and markdownlint.
- Do not execute commands that reach a cluster or cloud provider (for example
  `kubectl apply`, `kubectl delete`, `hetzner-k3s create`, or `helm install`)
  unless the user explicitly approves it. Report them as "not executed".
- If a command changes tracked files (for example `helm dependency update`
  rewriting `Chart.lock`), restore them afterwards with `git checkout -- <file>`.
  Check `git status` first and restore only files that were unmodified before
  the run, so local edits are never discarded.
- Remove untracked files that the run created (for example new archives under
  `charts/` from `helm dependency build`). Record what existed before the run,
  and keep those files.
- Run workbench-flow commands against an isolated Helm home so the user's repo
  list is neither used nor modified. Keep the installed plugins (for example
  helm-unittest) visible, because `HELM_PLUGINS` defaults to a path below
  `HELM_DATA_HOME`, and remove the temporary directory afterwards. The isolated
  config home also has no registry login, so report dependencies from private
  OCI registries as "not executed" instead of logging in:

```sh
 helm_home="$(mktemp -d)"
 export HELM_CACHE_HOME="$helm_home/cache"
 export HELM_PLUGINS="$(helm env HELM_PLUGINS)"
 export \
   HELM_CONFIG_HOME="$helm_home/config" \
   HELM_DATA_HOME="$helm_home/data"
 # run the documented workbench-flow commands here
 rm -rf "$helm_home"
 unset HELM_CACHE_HOME HELM_CONFIG_HOME HELM_DATA_HOME HELM_PLUGINS
```
