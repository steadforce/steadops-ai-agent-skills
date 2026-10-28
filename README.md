# SteadOps AI Agent Skills

A curated set of reusable Copilot skills for SteadOps repositories.
Each skill provides a task-specific workflow, constraints, and quality checks to make agent output consistent.

## What this repository contains

- Skill definitions in `.github/skills/*/SKILL.md`
- Shared commit message guidance in `.github/copilot-instructions.md`
- Documentation-first workflows for review, security checks, Helm unittest improvements, and README generation

## Included skills

| Skill | Purpose |
| --- | --- |
| `argocd-maintenance-mode` | Switch an application off for a maintenance window with Argo CD auto-sync paused on the app and on its root, and switch it on again safely. |
| `commit-messages` | Draft commit messages that follow repository conventions and atomic commit principles. |
| `create-readme` | Create or rewrite `README.md` files with structure, validation, and runnable examples. |
| `github-actions-efficiency` | Audit workflow execution and suggest changes that reduce CI minutes and cost. |
| `argo-cd-self-managed-rollout` | Upgrade Argo CD with itself, change the root application, and prune Applications without losing track of what keeps running. |
| `improve-helmunit-coverage` | Improve Helm unittest coverage for values, environments, and snapshots. |
| `gitea-helm-upgrade` | Promote a Gitea chart or application upgrade: irreversible migration, backup guard, removed routes, runner pods, and verification. |
| `gitea-smoke-test` | Verify a Gitea stage after a change with a dedicated restricted user: setup, token handling, and the checks. |
| `hydrated-deployment-status` | Find and promote pending changes of deployments that production loads from `environments/<cluster>` branches. |
| `istio-prod-promotion` | Promote an Istio version to production by moving the `prod` tag, step by step with checks. |
| `postgres-operator-major-upgrade` | Raise the major PostgreSQL version of a Zalando operator cluster in place: clone rehearsal, backup guards, maintenance window, and the Argo CD tag move. |
| `prod-tag-promotion` | Promote any deployment repository to production by moving the `prod` tag, with render diff, guarded dry run, and rollback. |
| `prometheus-alertmanager-teams` | Enable Alertmanager with one Teams channel per cluster, handle the webhooks as secrets, and test delivery. |
| `refactor-helmunit-anchors` | Refactor Helm unittest suites with YAML anchors to reduce duplication. |
| `security-review` | Run a structured security review workflow with dependency and exposure checks. |
| `skill-review` | Review skill files for metadata quality, constraints, and internal consistency. |
| `staged-cleanup-by-hand` | Remove retired or orphaned cluster resources in reviewable groups with export, dry run, and confirm string. |

## How to use a skill

1. Open a target repository in your workspace.
2. Trigger a skill by name in your prompt.
3. Provide the task scope (for example a specific chart, workflow, or file).

Example prompt:

```text
 /skill:improve-helmunit-coverage
 Add coverage for production values and environment-specific rendering.
```

> [!TIP]
> Keep prompts repository-scoped in large multi-repository workspaces.
> Most skills in this repository are designed to avoid workspace-wide scans.

## Repository layout

```text
 .
 ├── .github/
 │   ├── copilot-instructions.md
 │   └── skills/
 │       ├── argocd-maintenance-mode/
 │       ├── commit-messages/
 │       ├── create-readme/
 │       ├── gitea-helm-upgrade/
 │       ├── gitea-smoke-test/
 │       ├── github-actions-efficiency/
 │       ├── improve-helmunit-coverage/
│       ├── istio-prod-promotion/
 │       ├── refactor-helmunit-anchors/
 │       ├── postgres-operator-major-upgrade/
 │       ├── security-review/
 │       └── skill-review/
 └── README.md
```

## Validate markdown locally with Docker

```sh
 docker run --rm \
   -u $(id -u) \
   --entrypoint sh \
   -v "$(pwd):/apps" \
   -w /apps \
   ghcr.io/igorshubovych/markdownlint-cli:latest \
   -lc '
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

## Optional automated skill validation

This repository includes an optional validation workflow at
`.github/workflows/optional-skill-validation.yml`.

- Run it manually via **Actions** using `workflow_dispatch` whenever you
  want an automated check.

The workflow validates:

- Markdown formatting against `.markdownlint.json`
- Skill frontmatter in `.github/skills/*/SKILL.md`

Run the same checks locally:

```sh
 ./scripts/validate-skills-frontmatter.sh

 docker run --rm -u $(id -u) \
   -v "$(pwd):/apps" \
   -w /apps \
   ghcr.io/igorshubovych/markdownlint-cli:latest \
   "**/*.md" \
   --dot \
   --ignore node_modules \
   --config .markdownlint.json
```
