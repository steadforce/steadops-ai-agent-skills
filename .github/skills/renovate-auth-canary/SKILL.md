---
name: renovate-auth-canary
description: >-
  Use when a Renovate stage must exercise the same git authentication as production: set up a private test repository
  with a dedicated owner on the stage's Gitea, and verify it from the job log.
version: 1.0.0
category: Operations Workflow
license: MIT
compatibility: opencode
metadata:
  audience: platform-engineers
  workflow: renovate
---

# Private canary repository for Renovate

A Renovate regression in how git gets its token (a release that dropped the token embedded in the URL) passed the
development stage and broke every private repository on production, because development only discovered public
repositories. A private repository that the bot can access makes development fail first.

## Role

- Act as a senior platform engineer who tests the authentication path that production uses, without reading the bot's
  token or using an admin token.

## When to use

- Renovate updates, git or libcurl changes, or a stage whose Renovate user sees no private repository.

## Constraints

- Do not read the Renovate token from its secret and do not use an admin token. Find the bot user through the public
  user search (the full name names it) and create everything with a normal user.
- Give the owner no admin rights, a random e-mail suffix (account linking by e-mail must not match a real mailbox), a
  discarded random password, and a token with the repository scope only. Such a token gets `403` on `GET /user`; that is
  expected.
- Keep the pull request that Renovate opens: the repository is cloned again on every run.

## Workflow

1. Read the stage's Renovate configuration (config map, autodiscover filters) and the job schedule.
2. Create a dedicated owner with `gitea admin user create --random-password --restricted --must-change-password=false`
   and a repository-scoped token in a mode 600 file. Do not use the smoke-test user: deleting it would delete the
   repository.
3. As the owner create a private repository with an initial commit, add the bot as collaborator with write permission
   (it must push branches), and add a `renovate.json` and a file with a deliberately outdated dependency (for example
   a Dockerfile with an old base image tag).
4. If the repository was created by another user, transfer it: the current owner calls
   `POST /repos/<owner>/<repo>/transfer`, and the new owner accepts with `POST /repos/<owner>/<repo>/transfer/accept`.
   While the transfer is pending the path still names the CURRENT owner. Re-add collaborators if they disappeared.
5. Wait for the next Renovate job and read its log for the repository: `Repository started`, `Dependency extraction
   complete`, `Branch created`, `PR created`, `Repository finished`, and no ERROR or WARN lines.
6. Watch that job on every Renovate update: an error that names this repository is the early warning.

## Report

The repository, the owner, the collaborator, the log lines of the first run, and where the token file is.
