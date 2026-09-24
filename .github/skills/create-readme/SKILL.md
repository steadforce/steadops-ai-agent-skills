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
   This also applies to table rows: the markdownlint config disables MD013 for
   tables, so shorten table cells instead of relying on that exemption. Check
   with `awk 'length>120{print FNR": "length}' README.md`.
8. In shell snippets, indent each command line with a single leading space for
   consistent formatting.
9. In shell snippets, place each command option on its own line (for example,
   `helm template \\` then one flag per line).
10. In shell snippets, sort command options alphabetically where that does not
    change command behavior. Sort by option name, ignoring leading dashes, and
    keep the image name and its arguments last (for example `-e`,
    `--entrypoint`, `--rm`, `-u`, `-v`, `-w`). Keep repeated options, such as
    several `-e` flags, together in their original relative order.
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
21. For any alpine/helm Docker command (dependency update, template, etc.), set
   `-e HOME=/tmp` so Helm can write its cache when running as a non-root uid
   (rule 15). Without it, Helm fails with `Error: mkdir /.cache: permission
   denied`, or, for `dependency update`/`build`, with
   `open /.cache/helm/repository/helm-manager-…-index.yaml…: no such file or directory`.
   This applies to every `alpine/helm` invocation, including one-liners such as
   `alpine/helm dependency update .`.
22. For `yq`, `kubectl`, or `hetzner-k3s` examples outside the workbench flow,
   use `ghcr.io/steadforce/steadops/workbenches/k8s:main` by default, even if
   local binaries are available. Exception: when `yq` only feeds a Helm command
   in the same container (for example deriving repositories for
   `helm dependency build`, rule 35), use `alpine/helm`, which ships `yq`;
   rule 17 takes precedence.
23. When commands are documented to run inside the
   `SteadOps-Steadies-K8s-Workplace` workbench, document the available tools
   for that flow (for example `helm`, `yq`, `kubectl`, `hetzner-k3s`, and
   `act`) and show commands using those tools directly from the workbench shell.
24. In workbench flow snippets, run `kubectl`, `yq`, and `hetzner-k3s`
   directly (no `docker run` wrapper around those commands).
25. Ensure generated files end with exactly one trailing newline.
26. For charts that package and configure dependencies, use the term
   `umbrella chart` and avoid `wrapper chart`.
27. As the final step, draft a commit message that matches repository commit
   conventions and summarizes the README change.
28. Use the `commit-messages` skill when drafting that message.
29. Detect project convention before drafting:
   - check repository-specific guidance (for example `.github/copilot-instructions.md`)
   - inspect recent history with `git log --oneline -20`
30. Commit message style requirements:
   - subject is imperative, capitalized, and <= 72 characters
   - subject does not end with a period
   - add a blank line, then a body that explains why
   - wrap body lines at about 72 characters when practical
   - keep the commit atomic; if subject naturally needs "and", split changes
31. In large multi-repository workspaces, use terminal discovery commands only
    within the target repository (for example `grep -R`, `find`, `ls`).
    Do not use workspace-wide search tools unless explicitly requested.
32. Use a human-readable main title (`# ...`) in Title Case for `README.md`
    (for example `# External Secrets Deployment`) instead of a raw repository
    slug such as `# external-secrets-deployment`.
33. Use Title Case for README section headings (`##`, `###`) unless the target
    repository already enforces a different heading style.
34. For Helm charts with a committed `Chart.lock` (for example charts hydrated by
    the `helm-hydration.yaml` reusable workflow in `steadforce/steadops-workflows`
    v4+, which runs `helm dependency build` when `Chart.lock` exists and falls
    back to `helm dependency update` with a warning otherwise):
    - Do not describe `Chart.lock` as generated or gitignored; only `charts/` is
      gitignored.
    - Document `helm dependency build` for setting up after cloning and after any
      pull that changes `Chart.lock`.
    - Document `helm dependency update` separately, only for regenerating
      `Chart.lock` after a dependency change in `Chart.yaml`, and state that the
      new lock must be committed together with `Chart.yaml`.
    - List `Chart.lock` in the repository layout table.
35. Before `helm dependency build`, register the HTTP(S) dependency repositories,
    because `build` resolves them by registered name and fails on a fresh Helm
    home with `Error: no repository definition for https://…/. Please add the
    missing repos via 'helm repo add'`. Do not hardcode `helm repo add` per
    dependency; derive the repositories from `Chart.yaml` the way the pipeline does:
    - use `explode(.)`, because `Chart.yaml` often sets dependency names through
      YAML anchors;
    - include only `http*` repositories, because `oci://` and `file://`
      dependencies need no repo entry;
    - pass `--force-update`, which makes the command idempotent, repoints a
      same-named repo to the URL in `Chart.yaml`, and matches the pipeline.

    Workbench flow, where `helm` and `yq` run directly:

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

36. Verify every behavioral claim against the file that controls it, not against
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
    - **Values defaults:** list every key that `values.yaml` actually sets.

## Deliverable expectations

When done, report:
- whether `README.md` was created or updated
- which repository inputs were reviewed (for example chart files, scripts, docs)
- which sections were added, removed, or reorganized
- notable command examples included (local vs containerized)
- which files were changed
- which validation command(s) were run
- the result of executing each documented shell snippet (see validation workflow)
- confirmation that every `alpine/helm` invocation in the README sets `-e HOME=/tmp`
- the output of the line-length check from rule 7, including table rows
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
 docker run \
   --entrypoint sh \
   --rm \
   -u $(id -u) \
   -v /path/to/project:/apps \
   -w /apps \
   ghcr.io/igorshubovych/markdownlint-cli:latest -lc '
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
report, also execute every shell snippet documented in the README from the
repository root (for example dependency build and update, helm-unittest, and
render loops) and record the result of each.

- If a command changes tracked files (for example `helm dependency update`
  rewriting `Chart.lock`), restore them afterwards with `git checkout -- <file>`.
  Check `git status` first and restore only files that were unmodified before
  the run, so local edits are never discarded.
- Run workbench-flow commands against an isolated Helm home so the user's repo
  list is neither used nor modified:

```sh
 helm_home="$(mktemp -d)"
 export \
   HELM_CACHE_HOME="$helm_home/cache" \
   HELM_CONFIG_HOME="$helm_home/config" \
   HELM_DATA_HOME="$helm_home/data"
```
