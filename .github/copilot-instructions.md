# Commit message instructions

Apply these instructions when writing commit messages or preparing a `git commit`.

## Detect project convention first

- Check for repository-specific commit rules and follow them if present.
- Inspect recent history with `git log --oneline -20` and match the established style.
- Project convention takes precedence over the defaults below.
- If repository guidance is missing or history is too thin to infer a style,
  apply the defaults below.

## Default commit message format

- Write the subject so it completes: `If applied, this commit will ...`
- Capitalize the first word.
- Use imperative mood, for example `Add`, `Fix`, `Remove`, `Refactor`.
- Keep the subject at 72 characters or fewer.
- Do not end the subject with a period.
- Do not introduce a new scope prefix such as `auth:` unless the project
  already follows Conventional Commits or consistently uses scoped subjects.
- Make the subject meaningful on its own. Avoid vague subjects such as
  `Update stuff`, `Fix bug`, or `WIP`.

## Commit body rules

- Add a blank line between subject and body when a body is present.
- Use the body to explain why the change is needed, not only what changed.
- A body is optional for trivial commits when the subject is fully clear and no
  extra rationale is needed.
- Wrap body lines at 72 characters when practical.
- Do not force-wrap long tokens such as URLs, commands, or hashes.
- Put long URLs on their own line if they cannot be wrapped cleanly.
- Add issue references only if the project uses them.
- Put issue references on their own line at the end of the body, for example
  `Fixes #123`.

## Atomic commit rules

- Keep each commit focused on one logical change.
- If the subject contains `and`, consider splitting the work into multiple
  commits.
- Separate refactoring from functional changes whenever possible.
- Do not bundle unrelated fixes, features, or dependency updates into one
  commit.

## Conventional Commits

- Use Conventional Commits only when the repository already follows that
  convention.
- If used, keep the rest of these rules, including imperative mood and the
  72-character subject limit.

## Workspace search strategy

- In large multi-repository workspaces, prefer repository-scoped terminal
  search (`grep -R`, `find`, `ls`) over workspace-wide search tool calls.
- Scope searches to the target repository path first.
- Use workspace-wide search only for narrow queries when repository-scoped
  search is insufficient.