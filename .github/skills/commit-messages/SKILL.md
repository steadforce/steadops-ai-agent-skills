---
name: commit-messages
description: >-
  Use when creating git commits, writing commit messages, or when about to run git commit --
  enforces structured commit message format with imperative mood, capitalized subjects,
  72-char wrapping, and atomic commits
category: Development Workflow
metadata:
  audience: developers
  workflow: git
---

# Writing commit messages

## Overview

Enforce a consistent commit format.

- Write the subject so it completes: **"If applied, this commit will _\<your subject line\>_"**.
- Explain **why** in the body when a body is needed.

## Role

- Act as a senior reviewer for commit quality and message clarity, and as a
  quality gate.
- Ensure every commit message is imperative, specific, and easy to scan.
- Push for atomic commits and reject vague or mixed-purpose messages.

## Scope

- Applies to drafting, reviewing, and rewriting commit messages.
- Applies before running `git commit` and when splitting changes into atomic commits.
- Covers subject/body formatting, rationale quality, and issue reference placement.

## When to use

Use this skill when the request asks to:

- Draft a commit message.
- Review or rewrite a commit message.
- Run `git commit` and prepare the message first.
- Split a broad change into smaller, atomic commits.

## Constraints

- Keep the subject imperative, capitalized, and 72 characters or fewer.
- Do not end the subject with a period.
- Add a blank line between subject and body.
- Wrap body lines near 72 characters when practical.
- Do not use vague subjects (for example `Update stuff`, `WIP`).
- Keep commits atomic; split unrelated changes.

## References

Consider the following references when creating new commit messages:

- **Subject line rules, body format, URLs, issue references**:
  [./references/COMMIT_FORMAT.md](./references/COMMIT_FORMAT.md)
- **Split strategies, anti-rationalizations, and refactoring patterns**:
  [./references/ATOMIC_COMMITS.md](./references/ATOMIC_COMMITS.md)
- **Complete red flags checklist and mistake patterns**:
  [./references/COMMON_MISTAKES.md](./references/COMMON_MISTAKES.md)

## Attribution

**Author:** Andrew Fontaine ([@afontaine](https://gitlab.com/afontaine))

This skill is based on widely accepted Git commit message conventions,
with inspiration from:

- [Commit Message Guidelines](https://gist.github.com/robertpainsi/b632364184e70900af4ab688decf6f53) by Robert Painsi
- [OpenStack GitCommitMessages](https://wiki.openstack.org/wiki/GitCommitMessages)
- [A Note About Git Commit Messages](http://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) by Tim Pope
- [How to Write a Git Commit Message](http://chris.beams.io/posts/git-commit/) by Chris Beams
