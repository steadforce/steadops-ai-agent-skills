#!/bin/sh
# Validates the YAML frontmatter of every .github/skills/*/SKILL.md: it must parse as YAML, `name` and `description` must be
# non-empty strings, `name` must equal the folder name, and the description must stay under 100 words.
# Needs yq v4 (mikefarah); it is preinstalled on GitHub-hosted Ubuntu runners.

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd -P)"
SKILLS_DIR="$ROOT_DIR/.github/skills"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "ERROR: Skills directory not found: $SKILLS_DIR" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR: yq (https://github.com/mikefarah/yq) is required to parse the frontmatter" >&2
  exit 1
fi

status=0

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  if [ ! -f "$skill_file" ]; then
    continue
  fi

  skill_dir_name="$(basename "$(dirname "$skill_file")")"

  # frontmatter: the lines between the opening `---` on line 1 and the next `---`
  frontmatter="$(awk '
    NR == 1 { if ($0 == "---") { open = 1; next } else { exit } }
    open && $0 == "---" { closed = 1; exit }
    open { print }
    END { if (!closed) exit 1 }
  ' "$skill_file")" || {
    echo "FAIL: $skill_file -> Missing or malformed YAML frontmatter" >&2
    status=1
    continue
  }

  # yq fails on malformed YAML; the select() keeps only non-empty strings, and -e makes a missing value an error
  if ! name="$(printf '%s\n' "$frontmatter" | yq -e '.name | select(tag == "!!str" and length > 0)' 2>/dev/null)"; then
    echo "FAIL: $skill_file -> frontmatter is not valid YAML or field name is not a non-empty string" >&2
    status=1
    continue
  fi

  if ! description="$(printf '%s\n' "$frontmatter" | yq -e '.description | select(tag == "!!str" and length > 0)' 2>/dev/null)"; then
    echo "FAIL: $skill_file -> field description is not a non-empty string" >&2
    status=1
    continue
  fi

  if [ "$name" != "$skill_dir_name" ]; then
    echo "FAIL: $skill_file -> name '$name' must match folder '$skill_dir_name'" >&2
    status=1
    continue
  fi

  token_count="$(printf '%s\n' "$description" | wc -w | tr -d '[:space:]')"

  if [ "$token_count" -gt 100 ]; then
    echo "FAIL: $skill_file -> description exceeds 100 tokens ($token_count)" >&2
    status=1
    continue
  fi

  echo "OK:   $skill_file -> name=$name description_tokens=$token_count"
done

exit "$status"
