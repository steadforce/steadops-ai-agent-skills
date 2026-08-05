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
| `commit-messages` | Draft commit messages that follow repository conventions and atomic commit principles. |
| `create-readme` | Create or rewrite `README.md` files with structure, validation, and runnable examples. |
| `github-actions-efficiency` | Audit workflow execution and suggest changes that reduce CI minutes and cost. |
| `improve-helmunit-coverage` | Improve Helm unittest coverage for values, environments, and snapshots. |
| `refactor-helmunit-anchors` | Refactor Helm unittest suites with YAML anchors to reduce duplication. |
| `security-review` | Run a structured security review workflow with dependency and exposure checks. |
| `skill-review` | Review skill files for metadata quality, constraints, and internal consistency. |

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
 │       ├── commit-messages/
 │       ├── create-readme/
 │       ├── github-actions-efficiency/
 │       ├── improve-helmunit-coverage/
 │       ├── refactor-helmunit-anchors/
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
