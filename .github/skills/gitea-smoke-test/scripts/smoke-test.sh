#!/usr/bin/env bash
# Smoke test of a Gitea instance with a dedicated NON-ADMIN local user, for use after Gitea upgrades, promotions, runner
# changes, and database changes. See ../SKILL.md for the rules this script implements.
#
# Usage: smoke-test.sh setup    <label> [--confirm "create smoke-test user on <label>"]   once per instance (dry run without --confirm)
#        smoke-test.sh run      <label> [--expect-version X.Y.Z] [--keep]                  the smoke test (reads only the token file)
#        smoke-test.sh status   <label>                                                     what is set up (no secrets)
#        smoke-test.sh teardown <label> [--confirm "delete smoke-test user on <label>"]   deletes the user with its repositories
#   <label> names the instance (for example dev or prod); it only appears in messages and in the state file names.
#
# Environment (nothing that is specific to your instance has a default):
#   GITEA_URL           base URL, for example https://gitea.example.org (required)
#   GITEA_NAMESPACE     namespace of the Gitea Deployment (required for setup and teardown)
#   GITEA_DEPLOYMENT    name of the Gitea Deployment (required for setup and teardown)
#   KUBECONFIG          cluster to use (or the current kubectl context)
#   GITEA_CONTAINER     container that runs the gitea binary (default: gitea)
#   GITEA_HOSTS         host names whose health endpoint is checked (default: the host of GITEA_URL)
#   GITEA_SSH_PORT      SSH port to test (default: 22)
#   SMOKE_EMAIL_DOMAIN  domain of the test user's e-mail address (required for setup). Choose one WITHOUT real mailboxes:
#                       with account linking by e-mail a login through the identity provider with the same address would
#                       take the user over, and notification mail goes there.
#   SMOKE_RUNNER_LABEL  runs-on label of the test workflow (default: ubuntu-latest)
#   SMOKE_STATE_DIR     where the user name and the token file live (default: $XDG_STATE_HOME/gitea-smoke), mode 700
#   SMOKE_HOLD          seconds the workflow job sleeps (default 0): for tools that must see a RUNNING job
#   SMOKE_CHECKOUT      1 adds an actions/checkout step to the workflow (default 0): tests how the runner downloads and runs a real action
#
# The user is created with `gitea admin user create --random-password --restricted --must-change-password=false` (no admin
# rights; the generated password is not shown or stored: the test uses a token) and gets a token with the scopes
# write:repository and write:user. The token goes straight into a file (mode 600) and is never printed or put on a command
# line (curl reads its header from a file descriptor, git gets it through GIT_CONFIG_* environment variables).
# NOT covered: login through the identity provider, browser POSTs through external domains, SSH key login.
set -euo pipefail

usage() { echo "usage: $0 setup|run|status|teardown <label> [--confirm ...] [--expect-version X] [--keep]" >&2; exit 2; }
mode="${1:-}"; label="${2:-}"; [ -n "$mode" ] && [ -n "$label" ] || usage; shift 2
confirm=""; expect=""; keep=0
while [ $# -gt 0 ]; do case "$1" in --confirm) confirm="${2:-}"; shift 2;; --expect-version) expect="${2:-}"; shift 2;; --keep) keep=1; shift;; *) usage;; esac; done

base="${GITEA_URL:?set GITEA_URL, for example https://gitea.example.org}"; base="${base%/}"
scheme="${base%%://*}"; authority="${base#*://}"; authority="${authority%%/*}"
# the web authority may carry a port (host:8443); the SSH check needs the bare host name
case "$authority" in \[*) host="${authority%%]*}]";; *) host="${authority%%:*}";; esac
hosts="${GITEA_HOSTS:-$authority}"; ssh_port="${GITEA_SSH_PORT:-22}"
ns="${GITEA_NAMESPACE:-}"; dep="${GITEA_DEPLOYMENT:-}"; ctr="${GITEA_CONTAINER:-gitea}"; domain="${SMOKE_EMAIL_DOMAIN:-}"; runs_on="${SMOKE_RUNNER_LABEL:-ubuntu-latest}"
sdir="${SMOKE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/gitea-smoke}"; envf="$sdir/$label.env"; tokf="$sdir/$label.token"; repo=smoke-test

stop() { echo "STOP: $*" >&2; exit 1; }
pj() { python3 -I -c "import sys,json; d=json.load(sys.stdin); print($1)"; }
code() { curl -s -o /dev/null -m 20 -w '%{http_code}' "$@" || true; }
need_cluster() { [ -n "$ns" ] && [ -n "$dep" ] || stop "set GITEA_NAMESPACE and GITEA_DEPLOYMENT for '$mode'"; }
gexec() { kubectl exec -n "$ns" "deploy/$dep" -c "$ctr" -- "$@"; }
# authenticated API call: the header comes from a file descriptor, the token is never an argument
# like api, but returns only the HTTP status code
api_code() { curl -s -o /dev/null -m 60 -w '%{http_code}' -X "$1" -K <(printf 'header = "Authorization: token %s"\n' "$(cat "$tokf")") "$base/api/v1$2" || true; }
api() { local m="$1" p="$2" d="${3:-}"; if [ -n "$d" ]; then curl -s -m 60 -X "$m" -K <(printf 'header = "Authorization: token %s"\n' "$(cat "$tokf")") -H 'Content-Type: application/json' -d "$d" "$base/api/v1$p"; else curl -s -m 60 -X "$m" -K <(printf 'header = "Authorization: token %s"\n' "$(cat "$tokf")") "$base/api/v1$p"; fi; }
# the state file is read as data (key=value lines), never executed
read_state() { SMOKE_USER=""; SMOKE_EMAIL=""; SMOKE_CREATED=""; local k v; while IFS='=' read -r k v; do case "$k" in SMOKE_USER) SMOKE_USER="$v";; SMOKE_EMAIL) SMOKE_EMAIL="$v";; SMOKE_CREATED) SMOKE_CREATED="$v";; esac; done < "$envf"; }
load() { [ -f "$envf" ] && [ -f "$tokf" ] || stop "no smoke-test user set up for $label: run '$0 setup $label' first"; read_state; [ -n "$SMOKE_USER" ] || stop "$envf is incomplete"; }
echo "gitea smoke test '$mode' on $label at $(date '+%a %Y-%m-%d %H:%M %Z')"
case "$mode" in
status)
  if [ -f "$envf" ]; then read_state; echo "  user $SMOKE_USER, e-mail $SMOKE_EMAIL, created $SMOKE_CREATED; token file: $([ -f "$tokf" ] && echo present || echo MISSING)"; echo "  user exists on $label: HTTP $(code "$base/api/v1/users/$SMOKE_USER") (200 = yes)"; else echo "  not set up (no $envf)"; fi;;
setup)
  need_cluster; [ -n "$domain" ] || stop "set SMOKE_EMAIL_DOMAIN to a domain without real mailboxes"
  echo "== checks"
  [ "$(kubectl get deploy -n "$ns" "$dep" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}')" = 1/1 ] || stop "Gitea is not 1/1"
  [ "$(code "$base/api/healthz")" = 200 ] || stop "$base/api/healthz does not answer 200"
  echo "  ok: Gitea 1/1, healthz 200, version $(curl -s -m 15 "$base/api/v1/version" | pj 'd["version"]')"
  h="$(gexec gitea admin user create --help 2>&1)"; for f in --random-password --restricted --must-change-password; do grep -q -- "$f" <<<"$h" || stop "this Gitea has no '$f' flag on 'admin user create'"; done
  h="$(gexec gitea admin user generate-access-token --help 2>&1)"; for f in --scopes --raw --token-name; do grep -q -- "$f" <<<"$h" || stop "this Gitea has no '$f' flag on 'admin user generate-access-token'"; done
  echo "  ok: the CLI has --random-password --restricted --must-change-password and --scopes --raw --token-name"
  if [ -f "$envf" ]; then read_state; c="$(code "$base/api/v1/users/$SMOKE_USER")"; [ "$c" = 200 ] && { echo "ALREADY SET UP: user $SMOKE_USER exists, nothing to do"; exit 0; }; stop "$envf lists user $SMOKE_USER but the API answers $c: look at it by hand before creating another one"; fi
  want="create smoke-test user on $label"
  echo "== plan"; echo "  user name smoke-test-<8 random hex characters>, e-mail smoke-test-<same>@$domain"
  echo "  1. gitea admin user create ... --random-password --restricted --must-change-password=false   (output discarded: it contains the random password)"
  echo "  2. gitea admin user generate-access-token --scopes write:repository,write:user --raw   -> $tokf (mode 600, never printed)"
  [ "$confirm" = "$want" ] || { echo; echo "DRY RUN: nothing was changed. To create the user run again with:  --confirm \"$want\""; exit 0; }
  echo "== create"
  u="smoke-test-$(python3 -I -c 'import uuid; print(uuid.uuid4().hex[:8])')"; e="$u@$domain"
  [ "$(code "$base/api/v1/users/$u")" = 404 ] || stop "unexpected: user $u is not a 404 before creation"
  mkdir -p "$sdir"; chmod 700 "$sdir"; umask 077; err="$(mktemp)"; trap 'rm -f "$err"' EXIT
  gexec gitea admin user create --username "$u" --email "$e" --random-password --restricted --must-change-password=false >/dev/null 2>"$err" || { sed -E 's/(password[^:]*: *).*/\1<hidden>/I' "$err" | tail -3; stop "user creation failed (see above); nothing is stored"; }
  echo "  ok: user $u created (the generated password was discarded)"
  gexec gitea admin user generate-access-token --username "$u" --token-name "smoke-$(date +%Y%m%d)" --scopes "write:repository,write:user" --raw >"$tokf" 2>"$err" || { rm -f "$tokf"; tail -3 "$err"; stop "token creation failed: the user $u exists without a token; remove it with '$0 teardown' after writing $envf by hand, or delete it in the admin UI"; }
  [ "$(wc -c < "$tokf")" -ge 30 ] || { rm -f "$tokf"; stop "the token output looks wrong (too short): token file removed, user $u exists"; }
  chmod 600 "$tokf"; printf 'SMOKE_USER=%s\nSMOKE_EMAIL=%s\nSMOKE_CREATED=%s\n' "$u" "$e" "$(date +%FT%T%z)" > "$envf"; chmod 600 "$envf"
  echo "  ok: token stored in $tokf (mode 600), state in $envf"
  r="$(api GET /user)"; [ "$(echo "$r" | pj 'd.get("login")')" = "$u" ] || stop "the token does not authenticate as $u"
  echo "  ok: the token authenticates as $u; is_admin=$(echo "$r" | pj 'd.get("is_admin")') restricted=$(echo "$r" | pj 'd.get("restricted")')"
  [ "$(echo "$r" | pj 'd.get("is_admin")')" = False ] || stop "the user is an ADMIN: delete it now"
  echo; echo "DONE: smoke-test user ready on $label. Next: $0 run $label";;
run)
  load; fail=0; tmp="$(mktemp -d)"; ts="$(date +%Y%m%d-%H%M%S)"; b1="smoke/api-$ts"; b2="smoke/git-$ts"
  trap 'rm -rf "$tmp"' EXIT
  ok() { echo "  ok: $*"; }; bad() { echo "  FAIL: $*"; fail=1; }
  echo "== 1/7 health and version"
  for h in $hosts; do c="$(code "$scheme://$h/api/healthz")"; [ "$c" = 200 ] && ok "200 $scheme://$h/api/healthz" || bad "$c $scheme://$h/api/healthz"; done
  v="$(curl -s -m 15 "$base/api/v1/version" | pj 'd.get("version")')"; if [ -n "$expect" ]; then [ "$v" = "$expect" ] && ok "version $v" || bad "version $v, expected $expect"; else ok "version $v"; fi
  echo "== 2/7 token and rights"
  r="$(api GET /user)"; [ "$(echo "$r" | pj 'd.get("login")')" = "$SMOKE_USER" ] && ok "the token authenticates as $SMOKE_USER" || { bad "the token does not authenticate (answer: $(echo "$r" | cut -c1-120))"; echo "FAIL: cannot go on without a working token"; exit 1; }
  [ "$(echo "$r" | pj 'd.get("is_admin")')" = False ] || { echo "FAIL: the smoke-test user is an ADMIN: refusing to run mutating tests with it (delete the user and set it up again)"; exit 1; }
  ok "the user is not an admin"
  echo "== 3/7 repository $SMOKE_USER/$repo"
  if [ "$(api GET "/repos/$SMOKE_USER/$repo" | pj 'd.get("name","")')" != "$repo" ]; then api POST /user/repos "{\"name\":\"$repo\",\"private\":true,\"auto_init\":true,\"default_branch\":\"main\",\"description\":\"smoke test repository, may be deleted\"}" >/dev/null; sleep 3; fi
  [ "$(api GET "/repos/$SMOKE_USER/$repo" | pj 'd.get("name","")')" = "$repo" ] && ok "repository exists" || { bad "repository missing and not creatable"; exit 1; }
  echo "== 4/7 commit through the API"
  api POST "/repos/$SMOKE_USER/$repo/branches" "{\"new_branch_name\":\"$b1\",\"old_branch_name\":\"main\"}" >/dev/null
  csha="$(api POST "/repos/$SMOKE_USER/$repo/contents/smoke/$ts.txt" "{\"branch\":\"$b1\",\"message\":\"Smoke test $ts\",\"content\":\"$(printf 'smoke %s on %s\n' "$ts" "$v" | base64 -w0)\"}" | pj 'd.get("commit",{}).get("sha","")')"
  [ "${#csha}" = 40 ] && ok "commit ${csha:0:7} created through the API on $b1" || bad "the API commit failed"
  echo "== 5/7 git push over HTTPS (with a workflow)"
  auth="$(printf '%s:%s' "$SMOKE_USER" "$(cat "$tokf")" | base64 -w0)"
  g() { GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader GIT_CONFIG_VALUE_0="Authorization: Basic $auth" GIT_TERMINAL_PROMPT=0 git -C "$tmp/w" -c user.name=smoke-test -c user.email="$SMOKE_EMAIL" "$@"; }
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraheader GIT_CONFIG_VALUE_0="Authorization: Basic $auth" GIT_TERMINAL_PROMPT=0 git clone -q --depth 1 "$base/$SMOKE_USER/$repo.git" "$tmp/w" 2>"$tmp/e" || { tail -2 "$tmp/e"; bad "git clone over HTTPS failed"; exit 1; }
  ok "git clone over HTTPS"
  g checkout -q -b "$b2"; mkdir -p "$tmp/w/.gitea/workflows"
  # SMOKE_CHECKOUT=1 adds a step that downloads and runs a real action (actions/checkout): a test of how the runner fetches actions and of the node and git in the job image
  checkout_steps=""; [ "${SMOKE_CHECKOUT:-0}" = 1 ] && checkout_steps='      - uses: actions/checkout@v4\n      - run: git log -1 --oneline\n'
  printf 'name: smoke\non:\n  push:\n    branches: ["smoke/**"]\njobs:\n  smoke:\n    runs-on: %s\n    steps:\n%b      - run: echo "smoke ok on $(uname -s)"; sleep %s\n' "$runs_on" "$checkout_steps" "${SMOKE_HOLD:-0}" > "$tmp/w/.gitea/workflows/smoke.yaml"
  printf 'smoke %s\n' "$ts" > "$tmp/w/smoke.txt"; g add -A; g commit -q -m "Smoke test $ts"
  g push -q origin "$b2" 2>"$tmp/e" && ok "git push over HTTPS to $b2" || { tail -2 "$tmp/e"; bad "git push over HTTPS failed"; }
  psha="$(g rev-parse HEAD)"
  [ "$(api GET "/repos/$SMOKE_USER/$repo/branches/$b2" | pj 'd.get("commit",{}).get("id","")')" = "$psha" ] && ok "the pushed commit ${psha:0:7} is visible through the API" || bad "the pushed commit is not visible through the API"
  echo "== 6/7 Actions run of the push (up to 6 min)"
  res=""; for i in $(seq 1 72); do res="$(api GET "/repos/$SMOKE_USER/$repo/actions/runs?head_sha=$psha" | python3 -I -c '
import sys,json
d=json.load(sys.stdin); r=(d.get("workflow_runs") or [])
print("none" if not r else (r[0].get("conclusion") or r[0].get("status") or "?"))' 2>/dev/null || echo none)"
    case "$res" in success|failure|cancelled|skipped) break;; esac; [ $((i % 6)) = 0 ] && echo "  ... $(date +%H:%M:%S) run state: $res"; sleep 5; done
  case "$res" in success) ok "the workflow run reached success on a runner";; none) bad "no workflow run appeared for ${psha:0:7} (Actions disabled for the repository, or no runner)";; *) bad "the workflow run ended as '$res' (read its job log: actions/runs/<id>/jobs and actions/jobs/<id>/logs)";; esac
  echo "== 7/7 SSH port"
  timeout 5 bash -c "</dev/tcp/$host/$ssh_port" && ok "SSH port $ssh_port open on $host" || bad "SSH port $ssh_port closed on $host"
  if [ $keep = 0 ]; then
    cleaned=1; for b in "$b1" "$b2"; do c="$(api_code DELETE "/repos/$SMOKE_USER/$repo/branches/$b")"; case "$c" in 204|200|404) ;; *) bad "deleting branch $b answered HTTP $c: it was NOT deleted"; cleaned=0;; esac; done
    [ $cleaned = 1 ] && echo "  cleanup: branches $b1 and $b2 deleted (the Actions run stays until the retention removes it)"
  fi
  echo "  NOT covered, test by hand: login through the identity provider, browser POSTs through external domains, SSH key login"
  echo; [ $fail = 0 ] && echo "SMOKE TEST PASSED on $label ($v, $(date +%H:%M))" || echo "SMOKE TEST FAILED on $label: see the FAIL lines"; exit $fail;;
teardown)
  need_cluster; [ -f "$envf" ] || stop "nothing to tear down: no $envf"; read_state
  c="$(code "$base/api/v1/users/$SMOKE_USER")"; echo "  user $SMOKE_USER on $label: HTTP $c (200 = exists)"
  h="$(gexec gitea admin user delete --help 2>&1)"; for f in --username --purge; do grep -q -- "$f" <<<"$h" || stop "this Gitea has no '$f' flag on 'admin user delete'"; done
  want="delete smoke-test user on $label"
  echo "== plan"; echo "  gitea admin user delete --username $SMOKE_USER --purge   (removes the user, its repositories, tokens and keys), then $envf and $tokf are removed"
  [ "$confirm" = "$want" ] || { echo; echo "DRY RUN: nothing was changed. To delete run again with:  --confirm \"$want\""; exit 0; }
  case "$SMOKE_USER" in smoke-test-????????) ;; *) stop "the user name '$SMOKE_USER' does not look like a smoke-test user: refusing to delete it";; esac
  err="$(mktemp)"; trap 'rm -f "$err"' EXIT
  if [ "$c" = 200 ]; then gexec gitea admin user delete --username "$SMOKE_USER" --purge >/dev/null 2>"$err" || { tail -3 "$err"; stop "the deletion failed (see above); the local files are kept"; }; fi
  [ "$(code "$base/api/v1/users/$SMOKE_USER")" = 404 ] || stop "the user still exists after the deletion"
  echo "  ok: user $SMOKE_USER is gone on $label"; shred -u "$tokf" "$envf" 2>/dev/null || rm -f "$tokf" "$envf"; echo "  ok: local token and state files removed"
  echo; echo "DONE: smoke-test user removed on $label. A new one: $0 setup $label";;
*) usage;;
esac
