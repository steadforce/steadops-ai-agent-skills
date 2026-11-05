---
name: skill-review
description: >-
  Use when creating, editing, or validating AI agent skill files to ensure
  proper formatting, metadata, and testing.
---

# AI agent skill file review workflow

## Role

- Act as a senior AI agent skill engineer and as a quality gate
  repository.
- Enforce strict metadata, structure, constraint, and safety standards for skill files.
- Flag ambiguities, contradictions, and missing validation steps before approval.

## Scope

- Applies to skill markdown files (for example `SKILL.md`) and related templates under this repository.
- Covers frontmatter quality, instruction clarity, constraint completeness, and path/link integrity.
- Includes verification prompts to confirm trigger behavior and contradiction detection.

## When to use

- Use this workflow when creating a new skill file.
- Use this workflow when editing an existing skill file.
- Use this workflow when reviewing a pull request that changes skill instructions.

Execute these verification checks in order whenever managing or creating `.md` skill files inside this repository.

## 1. Metadata validation

- Ensure the `name` field in the frontmatter exactly matches the containing folder name using lowercase-kebab-case.
- Keep the `description` string concise (under 100 tokens) to minimize baseline context consumption.
- Explicitly declare the specific conditions or file patterns that trigger this skill.

## 2. Structural and constraints audit

- Write core instruction steps using direct, imperative phrasing (e.g., "Verify", "Check", "Do not").
- Confirm the total file length remains well under 5,000 tokens (~500 lines) to avoid context drift.
- List distinct negative constraints detailing forbidden flags, banned practices, or restricted tools.
- Validate that all internal markdown resource links use valid relative paths (e.g., `./templates/`).

## 3. Security and safe execution

- Audit all code snippets, automation scripts, and commands for unauthorized file writes or shell execution.
- Ensure the file layout avoids hardcoded API keys, environment variables, or private endpoint URLs.

---

## Verification and testing instructions

To confirm GitHub Copilot properly processes this skill file,
execute the following four verification tests:

## Test 1: Active Trigger Validation

- **Action:** Open Copilot Chat and type: `How do I format a skill file for this repository?`
- **Expected Result:** Copilot must explicitly reference this `skill-review`
  skill or trigger its specific guidelines automatically.

## Test 2: Negative Constraint Compliance

- **Action:** Paste a sample markdown block into the chat containing an
  over-length description and ask: `Review this skill block.`
- **Expected Result:** Copilot must flag the description for exceeding the 100-token footprint limitation.

## Test 3: Path Integrity Verification

- **Action:** Ask Copilot: `What relative paths are referenced inside my skills directory?`
- **Expected Result:** Copilot should successfully read the file structure and
  report any broken or empty directory links.

## Test 4: Contradiction and Logic Conflicts

- **Action:** Paste two competing requirements into Copilot Chat and ask:
  `Does this skill file contain any overlapping or contradictory rules?`
- **Expected Result:** Copilot must systematically flag the conflicting lines
  and request clarification on which constraint takes absolute priority.
