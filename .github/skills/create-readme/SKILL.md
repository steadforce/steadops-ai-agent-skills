---
name: create-readme
description: 'Create a README.md file for the project'
triggers:
  - Requests to create or rewrite a repository README.md
  - Requests to improve README structure, clarity, or onboarding flow
  - Requests to validate README formatting or markdown quality
---

# Create README

## Role

Act as a senior software engineer with strong open-source documentation
experience, and as a quality gate.
Write README files that are appealing, informative, and easy to read.

## Scope

Work only within the target repository.
Do not perform workspace-wide analysis unless explicitly requested.

## When to use

Use this skill when the request asks to:
- Create or rewrite a repository `README.md`.
- Improve README structure, clarity, or onboarding flow.
- Validate README formatting and markdown quality.

## Task

1. Review the target repository only, then create a comprehensive and well-structured README.md file for that project.
2. Take inspiration from these README files for structure, tone, and content:
   - https://raw.githubusercontent.com/Azure-Samples/serverless-chat-langchainjs/refs/heads/main/README.md
   - https://raw.githubusercontent.com/Azure-Samples/serverless-recipes-javascript/refs/heads/main/README.md
   - https://raw.githubusercontent.com/sinedied/run-on-output/refs/heads/main/README.md
   - https://raw.githubusercontent.com/sinedied/smoke/refs/heads/main/README.md
3. Do not overuse emojis, and keep the README concise and to the point.
4. Do not include sections like "LICENSE", "CONTRIBUTING", "CHANGELOG", etc.
   There are dedicated files for those sections.
5. Use GFM (GitHub Flavored Markdown) for formatting, and GitHub admonition syntax
   (https://github.com/orgs/community/discussions/16925) where appropriate.
6. If you find a logo or icon for the project, use it in the README header.
7. Ensure that lines in README.md are not longer than 120 chars if possible.
8. In shell snippets, indent each command line with a single leading space for
   consistent formatting.
9. In shell snippets, place each command option on its own line (for example,
   `helm template \\` then one flag per line).
10. In shell snippets, sort command options alphabetically where that does not
    change command behavior.
11. Lint `README.md` with markdownlint settings by inlining the JSON content shown in this
   skill (it mirrors `references/markdownlint.json`) via a heredoc into a temporary file
   inside the container, then pass that file to `markdownlint` with `-c`. Use image
   `ghcr.io/igorshubovych/markdownlint-cli:latest`. Do not reference the config file
   directly from the host path. Use this same pattern in every README-validation example.
12. Validate `README.md` by running the markdownlint workflow in this skill;
   treat a passing markdownlint run as the baseline markdown-validity check.
13. Prefer local tooling examples only when the required binary is known to be
   installed and no rule below requires a specific container image.
14. If a required tool is missing, provide containerized commands using `docker run`.
15. When using `docker run`, include `-u $(id -u)`.
16. Do not use `--pull=always` in Docker commands unless explicitly requested.
17. For Helm commands in README examples, use `alpine/helm` as container image.
18. For Helm `template` examples in README files, include `--include-crds` by default.
19. For helm-unittest examples, use `helmunittest/helm-unittest` as container image.
20. For helm-unittest Docker commands, set a writable cache path with
   `-e HELM_CACHE_HOME=/tmp/helm/.config`.
21. For `yq`, `kubectl`, or `hetzner-k3s` examples outside the workbench flow,
   use `ghcr.io/steadforce/steadops/workbenches/k8s:main` by default, even if
   local binaries are available.
22. When commands are documented to run inside the
   `SteadOps-Steadies-K8s-Workplace` workbench, document the available tools
   for that flow (for example `helm`, `yq`, `kubectl`, `hetzner-k3s`, and
   `act`) and show commands using those tools directly from the workbench shell.
23. In workbench flow snippets, run `kubectl`, `yq`, and `hetzner-k3s`
   directly (no `docker run` wrapper around those commands).
24. Ensure generated files end with exactly one trailing newline.
25. For charts that package and configure dependencies, use the term
   `umbrella chart` and avoid `wrapper chart`.
26. As the final step, draft a commit message that matches repository commit
   conventions and summarizes the README change.
27. Use the `commit-messages` skill when drafting that message.
28. Detect project convention before drafting:
   - check repository-specific guidance (for example `.github/copilot-instructions.md`)
   - inspect recent history with `git log --oneline -20`
29. Commit message style requirements:
   - subject is imperative, capitalized, and <= 72 characters
   - subject does not end with a period
   - add a blank line, then a body that explains why
   - wrap body lines at about 72 characters when practical
   - keep the commit atomic; if subject naturally needs "and", split changes
30. In large multi-repository workspaces, use terminal discovery commands only
    within the target repository (for example `grep -R`, `find`, `ls`).
    Do not use workspace-wide search tools unless explicitly requested.
31. Use a human-readable main title (`# ...`) in Title Case for `README.md`
    (for example `# External Secrets Deployment`) instead of a raw repository
    slug such as `# external-secrets-deployment`.
32. Use Title Case for README section headings (`##`, `###`) unless the target
    repository already enforces a different heading style.

## Deliverable expectations

When done, report:
- whether `README.md` was created or updated
- which repository inputs were reviewed (for example chart files, scripts, docs)
- which sections were added, removed, or reorganized
- notable command examples included (local vs containerized)
- which files were changed
- which validation command(s) were run
- final pass/fail counts
- remaining documentation gaps, if any
- drafted commit message text
- how commit style was detected (repository guidance and/or `git log`)
- commit message subject/body conformance checks

## Validation workflow

Always validate `README.md` with an inline heredoc config that mirrors the JSON block
shown in this skill (equivalent to `references/markdownlint.json`) instead of
referencing a host file path directly.
Use the same pattern in every validation example in this skill.
The canonical command is:

```sh
docker run --rm -u $(id -u) --entrypoint sh \
  -v /path/to/project:/apps -w /apps ghcr.io/igorshubovych/markdownlint-cli:latest -lc '
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
