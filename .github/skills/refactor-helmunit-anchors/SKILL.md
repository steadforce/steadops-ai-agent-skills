---
name: refactor-helmunit-anchors
description: Use when refactoring Helm unittest suites to reduce duplication with YAML anchors.
version: 1.0.0
category: Development Workflow
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: helm
---

# Refactor Helm unittest suites with YAML anchors

Use this skill when asked to reduce duplication in Helm unittest files while keeping tests readable and stable.

## Role

- Act as a senior Helm unittest refactoring engineer focused on safe
  deduplication, and as a quality gate.
- Improve maintainability by introducing anchors only where they reduce meaningful repetition.
- Preserve test intent and behavior while raising suite readability.

## Scope

- Applies to Helm unittest suite files such as `tests/*_test.yaml`.
- Covers anchor extraction for templates, values, selectors, assert blocks, and path expressions.
- Includes cleanup of unused anchors and alias correctness checks within the same file.

## When to use

Use this skill for requests like:

- "Refactor Helm unittest tests"
- "Deduplicate test suites with YAML anchors"
- "Make anchors consistent across *_test.yaml"
- "Clean up repeated values/templates/selectors/assert paths"

## Goals

- Reduce repeated YAML in Helm unittest suites.
- Keep suites readable; do not over-engineer anchors.
- Preserve test behavior.
- Keep anchor naming consistent.
- Validate all affected suites after edits.

## Large workspace search strategy

In large multi-repository workspaces, prefer terminal searches scoped to the
target repository to avoid task queue limit errors.

- Use `grep -R`, `find`, and `ls` from the target chart root.
- Avoid workspace-wide search calls when looking for anchors or test files.
- Keep include paths narrow (for example `tests/*_test.yaml`).

## Constraints and known behavior

- YAML anchors only work inside the same YAML document.
- YAML anchors do not deduplicate content across files.
- Keep name-based selectors in Helm unittest assertions.
- Prefer regex assertions for resource/content checks when appropriate.
- Do not use list merge tricks that reduce clarity.
- Do not add or remove asserts unless required to preserve unchanged behavior.
- Never commit `tests/__snapshot__/` files to git.

## Refactoring strategy

1. Inspect all `tests/*_test.yaml` files.
   - in large workspaces, use repository-scoped terminal commands for discovery
2. Find repeated high-value fragments:
   - `templates` lists used in multiple tests in one file
   - repeated values file entries like `../values-subchart-overrides.yaml`
   - repeated `documentSelector`
   - repeated assertion paths (for example annotation paths)
   - repeated assert blocks reused across environments
3. Anchor only meaningful repeated elements:
   - shared template lists
   - shared values lists or repeated values file scalars
   - shared selectors
   - shared assert blocks
   - shared path expressions
4. Keep one-off values inline.
5. Keep comments and indentation clear.

## Anchor naming conventions

Use readable camelCase names with consistent suffixes:

- Templates: `...Template`
  - Example: `&deploymentTemplate`, `&serviceTemplate`
- Values lists by environment: `...Values`
  - Example: `&localValues`, `&developmentValues`, `&productionValues`
- Shared values file scalar: `...ValuesFile`
  - Example: `&subchartOverrideValuesFile`
- Selectors: `...Selector`
  - Example: `&deploymentSelector`
- Assertion blocks: `...Assert` (singular)
  - Example: `&serviceTypeAssert`, `&gatewayResourcesAssert`
- Path expressions: `...Path` or `...PathExpression`
  - Example: `&proxyProtocolAnnotationPath`, `&secretDataPathExpression`

## Suite and test-case naming rules

When refactoring a Helm unittest file, keep suite and `it` names readable and behavior-focused.

Prefer these patterns:

- Suite names: concise, searchable, and centered on the component or behavior.
  - Good: `istiod deployment image per cluster`
  - Avoid: `test if the istio pilot image used in clusters is correct`
- Snapshot cases: use `matches the <scope> snapshot`.
  - Good: `matches the production cluster snapshot`
  - Good: `matches the subchart snapshot`
- Behavior cases: use an action/result verb that matches the assertion.
  - Examples: `renders`, `uses`, `enables`, `disables`, `sets`, `omits`, `keeps`
- Avoid vague or redundant phrasing.
  - Avoid: `check if`, `still rendered as before`, `is correct`, `hook settings`
- Keep terminology consistent within a file and across related suites.
  - Prefer one primary term for the same component.
  - Good examples: `istiod`, `discovery container`, `sidecar injector configmap`.

If a test only checks a snapshot, make that explicit in the name.
If a test checks a specific behavior, name that behavior directly instead of implying broader coverage.

## Practical heuristics

- Good anchor candidate: appears 3+ times in the same file.
- Good anchor candidate: long path strings or long assert blocks.
- Avoid anchors when they save only one short line.
- Prefer introducing anchors at first natural occurrence.

## Anchor cleanup rules

After refactoring, remove anchors that are defined but never referenced.

- Keep anchors only when they are used via alias in the same file.
- Remove unused anchor definitions (`&name`) and inline the value directly.
- If an alias (`*name`) exists without a matching definition, treat it as a correctness issue and fix it.
- Apply cleanup conservatively: do not change assertions, values, or templates beyond removing dead anchors.

Recommended check:

1. For each `tests/*_test.yaml` file, compare defined anchors (`&...`) with aliases (`*...`).
2. Remove `&...` names that never appear as `*...` in that file.
3. Re-run Helm unittest and confirm no behavior change.

Typical cleanup targets:

- one-off path anchors used only where defined
- one-off values-list anchors not reused in later cases
- nested anchors in `content:` blocks that are never aliased

Tiny reusable shell snippet:

```sh
python3 - <<'PY'
import re
from pathlib import Path

root = Path('tests')
anchor_re = re.compile(r'&([A-Za-z_][A-Za-z0-9_-]*)')
alias_re = re.compile(r'\*([A-Za-z_][A-Za-z0-9_-]*)')

for f in sorted(root.glob('*_test.yaml')):
    text = f.read_text(encoding='utf-8')
    defs = set(anchor_re.findall(text))
    uses = set(alias_re.findall(text))
    unused = sorted(defs - uses)
    unresolved = sorted(uses - defs)
    if unused or unresolved:
        print(f)
        if unused:
            print('  unreferenced anchors: ' + ', '.join(unused))
        if unresolved:
            print('  unresolved aliases: ' + ', '.join(unresolved))
PY
```

## Example patterns

### Reuse a common values file scalar

```yaml
values:
- &subchartOverrideValuesFile ../values-subchart-overrides.yaml
- ../values-local.yaml

# later
values:
- *subchartOverrideValuesFile
- ../values-development.yaml
```

### Reuse selector and assert path

```yaml
documentSelector: &deploymentSelector
  path: kind
  value: Deployment

asserts:
- notExists:
    path: &proxyProtocolAnnotationPath spec.template.metadata.annotations["proxy.istio.io/config"]

# later
documentSelector: *deploymentSelector
asserts:
- notExists:
    path: *proxyProtocolAnnotationPath
```

## Validation workflow

After refactoring, run full chart tests and confirm no behavior change:

```sh
docker run --rm -u $(id -u) -e HOME=/tmp \
  -v /path/to/chart:/apps \
  -w /apps \
  helmunittest/helm-unittest .
```

Success criteria:

- all suites pass
- snapshots pass after update or are intentionally updated locally
- no strict parse errors introduced by anchors
- snapshot files are not staged or committed
- draft a commit message that matches repository commit conventions and summarizes the refactor

## Commit message workflow

After tests pass and before final reporting:

1. Detect repository commit style first:
   - check repository guidance files (for example `.github/copilot-instructions.md`)
   - inspect recent commits with `git log --oneline -20`
2. Use the `commit-messages` skill to draft the final message.
3. Keep the subject imperative, capitalized, <= 72 characters, and without a trailing period.
4. Add a blank line and a body that explains why the anchor refactor was useful.
5. Wrap body lines at about 72 characters when practical.
6. Keep the commit atomic; avoid bundling behavior changes into anchor-only refactors.

## Anti-patterns to avoid

- Over-anchoring every short scalar value.
- Leaving unreferenced anchor definitions after refactoring.
- Introducing helper map keys that are not part of suite schema.
- Renaming anchors in ways that hide meaning.
- Adding or removing asserts when behavior can be preserved without assert changes.
- Refactoring without running Helm unittest afterwards.

## Deliverable expectations

When done, report:

- files changed
- notable anchor decisions
- test command used
- pass/fail counts
- snapshot handling (updated locally, not committed)
- drafted commit message text
- how commit convention was detected and applied
