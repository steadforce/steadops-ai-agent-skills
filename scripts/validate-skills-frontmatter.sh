#!/bin/sh

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." >/dev/null 2>&1 && pwd -P)"
SKILLS_DIR="$ROOT_DIR/.github/skills"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "ERROR: Skills directory not found: $SKILLS_DIR" >&2
  exit 1
fi

status=0

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  if [ ! -f "$skill_file" ]; then
    continue
  fi

  skill_dir_name="$(basename "$(dirname "$skill_file")")"

  parsed="$(
    awk '
      function trim(s) {
        gsub(/^[[:space:]]+/, "", s)
        gsub(/[[:space:]]+$/, "", s)
        return s
      }
      BEGIN {
        in_frontmatter = 0
        have_frontmatter_start = 0
        have_frontmatter_end = 0
        line_count = 0
      }
      NR == 1 {
        if ($0 == "---") {
          in_frontmatter = 1
          have_frontmatter_start = 1
          next
        }
      }
      {
        if (in_frontmatter && $0 == "---") {
          in_frontmatter = 0
          have_frontmatter_end = 1
          next
        }

        if (in_frontmatter) {
          line_count++
          fm[line_count] = $0
        }
      }
      END {
        if (!have_frontmatter_start || !have_frontmatter_end) {
          print "ERROR|Missing or malformed YAML frontmatter"
          exit
        }

        name = ""
        description = ""

        for (i = 1; i <= line_count; i++) {
          line = fm[i]

          if (line ~ /^name:[[:space:]]*/) {
            sub(/^name:[[:space:]]*/, "", line)
            name = trim(line)
            continue
          }

          if (line ~ /^description:[[:space:]]*/) {
            sub(/^description:[[:space:]]*/, "", line)
            line = trim(line)

            if (line == ">" || line == ">-" || line == "|" || line == "|-") {
              for (j = i + 1; j <= line_count; j++) {
                if (fm[j] !~ /^[[:space:]]+/) {
                  break
                }
                description = description " " trim(fm[j])
              }
              i = j - 1
            } else {
              description = line
            }
          }
        }

        if (name == "") {
          print "ERROR|Missing frontmatter field: name"
          exit
        }

        if (description == "") {
          print "ERROR|Missing frontmatter field: description"
          exit
        }

        token_count = split(description, words, /[[:space:]]+/)

        if (token_count > 100) {
          print "ERROR|description exceeds 100 tokens (" token_count ")"
          exit
        }

        print "OK|" name "|" token_count
      }
    ' "$skill_file"
  )"

  result="$(printf '%s' "$parsed" | cut -d'|' -f1)"
  message="$(printf '%s' "$parsed" | cut -d'|' -f2-)"

  if [ "$result" = "ERROR" ]; then
    echo "FAIL: $skill_file -> $message" >&2
    status=1
    continue
  fi

  name_field="$(printf '%s' "$parsed" | cut -d'|' -f2)"
  desc_tokens="$(printf '%s' "$parsed" | cut -d'|' -f3)"

  if [ "$name_field" != "$skill_dir_name" ]; then
    echo "FAIL: $skill_file -> name '$name_field' must match folder '$skill_dir_name'" >&2
    status=1
    continue
  fi

  echo "OK:   $skill_file -> name=$name_field description_tokens=$desc_tokens"
done

exit "$status"
