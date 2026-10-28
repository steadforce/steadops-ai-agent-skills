---
name: gitea-smoke-test
description: >-
  Use when verifying a Gitea instance after an upgrade, promotion, or database change with a dedicated non-admin
  local user: setup, token handling, and the checks to run.
version: 1.1.1
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: gitea
---

# Smoke test of a Gitea stage with a dedicated user

Checks the paths a user needs (API, git over HTTPS, Actions, SSH port) with a restricted local account instead of the
admin account. Run it after every Gitea promotion, runner change, and database upgrade.

## Role

- Act as a senior platform engineer who proves that the service works for a normal user and reads a failure down to
  its cause before calling it a product bug.

## When to use

- After a Gitea chart or application promotion, a PostgreSQL upgrade, a runner or ingress change, or a restore.

## Constraints

- Do not use the admin account or its password for routine tests. A leaked admin token can delete repositories and
  users, and the audit trail would show admin activity. Use the admin only to create the test user.
- Do not print the token, put it on a command line, or store it in Git or chat. Give curl its header through a file
  descriptor (`-K <(printf 'header = "Authorization: token %s"\n' "$(cat file)")`), give git the header through
  `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_0`, and `GIT_CONFIG_VALUE_0`, and keep the token file at mode 600.
- Do not accept SSH host keys on your own and do not test SSH key login automatically. Check that the SSH port is open.
- Choose an e-mail address that no real mailbox has. With account linking by e-mail (`ACCOUNT_LINKING: auto`) a Dex
  login with the same address would take the test user over. Notification mail goes to that address too.
- Use one test user per stage. Create it on production only with the user's approval.

## Workflow

### 1. Set up once per stage

1. Check that the CLI has the flags you need (`gitea admin user create --help`).
2. Create the user with a readable random name such as `smoke-test-<8 hex>`, `--random-password`, `--restricted`, and
   `--must-change-password=false`. Discard the output: it contains the generated password. The account never needs it.
3. Generate a token with `gitea admin user generate-access-token --raw` and the scopes `write:repository` and
   `write:user`. Creating a repository under the user needs `write:user`, and a token cannot be widened later.
   Write the token straight into the file.
4. Check that `GET /api/v1/user` with the token returns the user, `is_admin` false, and `restricted` true.

A restricted user cannot create organizations, so the test repository `smoke-test` lives in the user's own namespace.

### 2. Run

1. Health endpoint on every host the stage serves, and the version (compare with the expected one).
2. The token authenticates and the user is not an admin. Stop at once if it is an admin: do not run the mutating
   tests with an admin token.
3. The repository exists (create it once, private).
4. A commit through the API on a short-lived branch.
5. `git clone` and `git push` over HTTPS of a branch that carries a workflow file that only prints a line.
6. The workflow run of that commit (`GET /repos/<user>/<repo>/actions/runs?head_sha=<sha>`) reaches success within a
   few minutes on a runner.
7. The SSH port accepts a connection (use the bare host name: the web URL may carry another port).
8. Delete the branches and check the result of each delete. A failed delete is a test failure, not a success. The run
   history stays until the retention removes it.

### 3. Read a failure

Read the job before you judge: `GET /repos/<user>/<repo>/actions/runs/<id>/jobs`, then
`/actions/jobs/<job id>/logs`. A failed run is often infrastructure: `no space left on device` on a runner node, an
image pull that fails, or no runner at all. Report the cause and the node or pod it points to. Then look at the runner
pods and their init containers (see `gitea-helm-upgrade`).

### 4. Remove

`gitea admin user delete --username <name> --purge` removes the user, its repositories, and its tokens. Delete the local
token and state files afterwards. Keep the user between runs: creating it needs an admin action in the pod every time.

## Script

`./scripts/smoke-test.sh` implements setup, run, status, and teardown. Nothing that is specific to your instance is
hard-coded; it comes from the environment:

```sh
export GITEA_URL=https://gitea.example.org GITEA_NAMESPACE=gitea GITEA_DEPLOYMENT=gitea
export SMOKE_EMAIL_DOMAIN=example.org   # a domain without real mailboxes
./scripts/smoke-test.sh setup prod      # dry run; creates the user with --confirm "create smoke-test user on prod"
./scripts/smoke-test.sh run prod --expect-version 1.26.1
```

Optional settings: `KUBECONFIG`, `GITEA_CONTAINER`, `GITEA_HOSTS` (several health hosts), `GITEA_SSH_PORT`,
`SMOKE_RUNNER_LABEL` (the `runs-on` label), `SMOKE_STATE_DIR` (default `~/.local/state/gitea-smoke`, mode 700), and
`SMOKE_HOLD` (seconds the workflow job sleeps, to test tools that must see a running job). The first argument is a
label for the instance. Setup and teardown run `gitea admin` in the Gitea pod with `kubectl exec`; run needs only the
token file. The script writes only to its state directory and to the test repository, and it reads the state file as
data without executing it.

## Not covered

Login through the identity provider, browser POSTs through the external domains (cross-origin protection), and SSH key
login. Test those by hand after a promotion.

## Report

Per stage: the checks with ok or FAIL, the version, the time, the cause of a failure, and what is not covered.
