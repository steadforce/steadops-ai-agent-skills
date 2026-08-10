---
name: improve-helmunit-coverage
description: Use when improving Helm unittest coverage for root value files, environment rendering, or snapshots.
---

# Improve Helm unittest coverage

Use this skill when asked to improve Helm unittest coverage for a chart, especially when value file overrides,
environment-specific rendering, or snapshots are involved.

## Role

- Act as a senior Helm unittest coverage engineer for chart test quality,
  and as a quality gate.
- Convert fragile or implicit coverage into direct behavior assertions.
- Keep coverage focused on realistic regression risks in value-driven rendering.

## Scope

- Applies to Helm chart unittest suites and root-level `values*.yaml` override behavior.
- Covers hydration-scope analysis, environment rendering differences, and assertion quality.
- Includes snapshot handling, but treats snapshots as support checks rather than primary coverage.

## When to use

Use this skill for requests like:
- "Improve Helm unittest coverage"
- "Check Helm unittest coverage gaps"
- "Add tests for overridden values"
- "Cover environment-specific Helm values"
- "Make value file overrides explicitly tested"

## Goals

- Increase confidence in Helm chart behavior with focused tests.
- Prefer direct assertions for important value file overrides.
- Scope coverage to values configured in root-level `values*.yaml` files that are in hydration scope.
- Keep tests readable and maintainable.
- Treat snapshot assertions as supporting evidence only; snapshot-only tests do not count as override coverage.
- Finish with a clean passing Helm unittest run.

## Large workspace search strategy

When the workspace contains many repositories, avoid broad workspace-wide
search calls that can hit task queue limits.

- Prefer terminal commands scoped to the target chart directory.
- Use `grep -R`, `find`, and `ls` from the chart root for file discovery.
- Keep searches path-scoped (for example `tests/*.yaml`, `templates/*.yaml`).
- Use workspace search tools only for narrow, repository-scoped queries.

## Coverage mindset

Coverage should focus on behavior that can regress:

1. Which value files are actually in hydration scope?
2. Which keys in those files affect rendered manifests?
3. Which of those effects are explicitly asserted today?
4. Which are only covered by snapshot assertions and therefore not counted as coverage?
5. Which are not covered by direct assertions at all?

Do not assume every value in a values file must be tested. Only test values that:
- affect rendered manifests
- represent intentional platform or environment behavior
- protect against likely regressions

Coverage accounting rule:
- only direct behavior assertions count as coverage for override behavior
- snapshot-only checks are considered unscored support checks and must be paired with direct assertions

## Recommended workflow

1. Inspect chart structure:
   - `Chart.yaml`
   - `helm-config.yaml`
   - `values*.yaml`
   - `tests/*_test.yaml`
   - in large workspaces, run repository-scoped terminal search instead of global
     workspace search to avoid task queue limit errors
2. Run Helm unittest to establish baseline.
3. If snapshots fail due to intentional changes, update snapshots first to restore a clean baseline.
4. Determine hydration scope from `helm-config.yaml`:
   - identify all environments
   - identify which value files each environment uses
   - keep scope to root-level value files from the repository unless explicitly requested otherwise
   - compare discovered root environment value files (for example `values-<env>.yaml`) with configured environments
   - if a matching environment is missing in `helm-config.yaml`, add it with the correct `apis` and `valueFiles`
   - for every environment whose name encodes a stage (for example a `-dev` or `-prod` suffix), verify its
     `valueFiles` list actually references the correspondingly named stage file (`values-development.yaml` vs
     `values-production.yaml`) and not a mismatched one — see "Validating helm-config.yaml value file wiring" below
5. Map overridden values to rendered outputs:
   - inspect templates directly
   - inspect dependency chart templates if behavior comes from a subchart
   - render templates locally if merge behavior is unclear
6. Add or improve tests.
7. Re-run Helm unittest until all suites pass.
8. As the final step, use the `commit-messages` skill to draft and validate a message that matches repository
   conventions and summarizes the coverage changes.

## What to test directly

Prefer direct assertions for these kinds of overrides:

- image hub, repository, or variant changes
- labels or annotations driven by override values
- configmap keys derived from override values
- platform-specific path or directory changes
- affinity, tolerations, node selectors, and security-sensitive scheduling changes
- environment-specific enable/disable behavior
- job/deployment image fields and related settings that are directly derived from root value files

Only add tests for resources that consume those values. If a template is static or only capability-gated and does not
consume root value file configuration, treat it as out of scope for value file-driven coverage requests.

Prefer exact assertions for:
- booleans rendered as strings in configmaps
- fixed labels or annotations
- fixed host paths
- presence or absence of named selectors

Prefer regex assertions for:
- resource presence or patterns
- image prefixes/suffixes
- content where exact formatting may vary

For image assertions, prefer checking registry/repository with regex and avoid exact tag pinning in tests unless a
specific tag value is the behavior under test.

Avoid exact tests for CPU and memory values when the intent is only local-vs-nonlocal or zero-vs-nonzero behavior.

## Snapshot guidance

Use snapshots to catch broad side effects, but do not rely on snapshots alone for important override behavior.

Snapshot-only cases are not considered coverage for this skill. If a value file override is part of the requested
coverage, add at least one direct assertion that verifies the concrete rendered behavior.

If a value file override is important, add a direct assertion alongside any snapshot assertion.

If snapshots are updated locally during validation, do not commit snapshot files (for example `tests/__snapshot__/`).

## Naming rules for suites and test cases

Use names that describe the behavior under test, not the fact that a test exists.

Prefer these patterns:

- Suite names: concise, behavior-focused, and searchable.
  - Good: `istiod deployment image per cluster`
  - Avoid: `test if the istio pilot image used in clusters is correct`
- Snapshot cases: `matches the <scope> snapshot`
  - Good: `matches the production cluster snapshot`
  - Good: `matches the subchart snapshot`
- Behavior cases: use an action/result verb that matches the assertion.
  - Examples: `renders`, `uses`, `enables`, `disables`, `sets`, `omits`, `keeps`
- Avoid vague or redundant phrasing.
  - Avoid: `check if`, `still rendered as before`, `is correct`, `hook settings`
- Keep terminology consistent across one file and across related suites.
  - Prefer one primary term for the same component, such as `istiod`, `discovery container`, or
    `sidecar injector configmap`.

When renaming tests, keep the name aligned with the strongest assertion in the case. If the test only checks a
snapshot, make that explicit in the name. If it checks a specific behavior, name that behavior directly instead of
implying broader coverage.

Examples of good direct assertions added in this session:
- configmap key `data.NATIVE_NFTABLES`
- owning-resource label derived from override values
- worker affinity selector key presence or absence
- k3s-specific CNI host paths derived from platform profile behavior

Also from this session:
- if a parent path is already asserted as absent, avoid adding redundant nested `notExists` assertions below that path
- remove assertions that do not verify value-driven behavior and do not protect a realistic regression risk

## Environment-specific coverage guidance

When an environment has its own value file, test that environment explicitly.

Examples:
- if `values-sf-k8s03-dev.yaml` is in hydration scope, add tests that use it directly
- if dev and prod share the same values file set, a shared test may be sufficient
- if a cluster-specific values file changes behavior, avoid hiding it inside a generic dev/prod test
- if a root value file implies an environment that is not present in `helm-config.yaml`, add that environment first
  so the value file is in hydration scope

## Handling merged values correctly

Be careful with Helm merge behavior.

Important lesson from this session:
- setting a nested map to `{}` may not remove inherited keys
- setting the parent value to `~` can null out inherited configuration completely

Example:

```yaml
cni:
  cni:
    affinity: ~
```

This is appropriate when the intent is to remove inherited affinity entirely.

## Capability-gated templates

Some templates are rendered only when specific API versions exist in Helm capabilities.

When writing unittest coverage for these templates:
- only add them for value file-driven coverage if the template consumes root value file settings
- add `capabilities.apiVersions` in the suite so the template is rendered in tests
- prefer direct assertions for core fields (apiVersion, kind, metadata.name, targetRef, update policy)

Example:

```yaml
capabilities:
  apiVersions:
  - autoscaling.k8s.io/v1/VerticalPodAutoscaler
```

## Assertion patterns

Prefer name-based selectors over numeric indices.

Examples:

```yaml
- equal:
    path: spec.template.spec.volumes[?(@.name == "cni-bin-dir")].hostPath.path
    value: /var/lib/rancher/k3s/data/cni
```

```yaml
- exists:
    path: >-
      spec.template.spec.affinity.nodeAffinity.
      requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[*].
      matchExpressions[?(@.key == "node.kubernetes.io/worker")]
```

```yaml
- notExists:
    path: >-
      spec.template.spec.affinity.nodeAffinity.
      requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[*].
      matchExpressions[?(@.key == "node-role.kubernetes.io/worker")]
```

```yaml
- equal:
    path: data.NATIVE_NFTABLES
    value: "true"
```

## Refactoring and organization guidance

When adding coverage:
- prefer extending an existing suite for the same resource
- avoid creating tiny one-off suite files if the tests belong naturally in an existing file
- reuse anchors where sensible for templates, values, selectors, and assertion paths
- keep anchor naming consistent:
  - `...Template`
  - `...Values`
  - `...ValuesFile`
  - `...Assert`
  - `...Path` or `...PathExpression`

## Validation commands

Run chart tests with Docker:

```sh
docker run --rm -u $(id -u) -e HOME=/tmp \
  -v /path/to/chart:/apps \
  -w /apps \
  helmunittest/helm-unittest .
```

Update snapshots when intentional manifest changes occurred:

```sh
docker run --rm -u $(id -u) -e HOME=/tmp \
  -v /path/to/chart:/apps \
  -w /apps \
  helmunittest/helm-unittest -u .
```

Render a specific template locally when investigating merge behavior:

```sh
docker run --rm -u $(id -u) -e HOME=/tmp \
  -v /path/to/chart:/apps \
  -w /apps \
  alpine/helm template release-name . \
  -f values-subchart-overrides.yaml \
  -f values-local.yaml \
  --show-only charts/subchart/templates/example.yaml
```

## Commit message workflow

When coverage changes are complete and tests are green:

1. Detect project-specific commit conventions first:
   - check repository guidance files (for example `.github/copilot-instructions.md`)
   - inspect recent history with `git log --oneline -20`
2. Draft the commit message using the `commit-messages` skill.
3. Keep the subject imperative, capitalized, <= 72 characters, and without a trailing period.
4. Add a blank line and a body that explains why the coverage change is needed.
5. Wrap body lines at about 72 characters when practical.
6. Keep the commit atomic; avoid subjects that join unrelated changes with "and".

## Deliverable expectations

When done, report:
- which value files were considered in scope
- which override keys are explicitly covered now
- which gaps remain, if any
- which previously snapshot-only checks were converted to direct coverage assertions
- which files were changed
- which test command was run
- final pass/fail counts
- snapshot handling (updated locally or unchanged, and not committed)
- drafted commit message text
- how commit convention was detected and applied

If a resource does not consume overridden values, state clearly that it is out of override-coverage scope
instead of reporting it as a gap.

## Anti-patterns to avoid

- treating snapshots as sufficient for all important overrides
- counting snapshot-only tests as override coverage
- using vague suite or case names that do not describe the asserted behavior
- adding exact CPU or memory assertions when only behavioral categories matter
- using numeric indices in selectors when name-based selectors are available
- forgetting to test environment-specific value files in hydration scope
- not adding a missing `helm-config.yaml` environment for an existing root environment-specific value file
- assuming `{}` removes inherited keys in Helm merges
- reporting resources as coverage gaps when they do not consume overridden values
- adding redundant nested `notExists` assertions when the parent path is already asserted as absent
- keeping assertions that are not value-driven and do not guard realistic regressions
- adding tests for static or capability-only resources when the request is value file-driven coverage
- asserting exact image tags when only registry/repository stability is required
- ending without a clean Helm unittest run
