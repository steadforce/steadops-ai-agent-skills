#!/usr/bin/env bash
# Maintenance mode for an application that Argo CD manages: scales its Deployment (and optionally a StatefulSet of
# runners or workers) to zero while Argo CD auto-sync is paused, so Argo CD does not scale it back up. Nothing in the
# application data is changed. See ../SKILL.md for the rules this script implements.
#
# Usage: maintenance.sh on     <label> [--with-runners] [--force] [--pause-root]
#        maintenance.sh off    <label> [--defaults]
#        maintenance.sh status <label>
#   <label> names the stage (for example dev or prod); it only appears in messages and in the state file name.
#   on      records the state, pauses the parent (root) application and the application, waits until no sync is
#           pending or running, scales to zero, and checks for 45 s that nothing brings the application back.
#   off     scales back to the recorded replicas, waits for health, hard-refreshes Argo CD, waits for a comparison that
#           is newer than the refresh, and only then restores the recorded sync policies.
#   status  shows the marker, the sync policy, the replicas, the health, and the running jobs.
#
# Environment (the script has no default for anything that is specific to your cluster):
#   KUBECONFIG                  cluster to use (or the current kubectl context)
#   MAINT_APP                   name of the Argo CD Application (required)
#   MAINT_NAMESPACE             namespace of the workloads (required)
#   MAINT_HEALTH_URL            URL that answers 200 while the application is up (required)
#   MAINT_DEPLOYMENT            Deployment to scale (default: the Application name)
#   MAINT_RUNNERS_STS           StatefulSet of runners or workers, scaled with --with-runners and checked for running jobs
#   MAINT_RUNNER_CONTAINER      container of the runner pods (default: runner)
#   MAINT_JOB_CONTAINER_FILTER  name filter of job containers in the runner's docker (default: GITEA-ACTIONS-TASK)
#   MAINT_JOB_START_PATTERN     regular expression of a job start line in the runner log (default: task [0-9]+ repo is)
#   MAINT_ARGOCD_NS             namespace of Argo CD (default: argocd)
#   MAINT_ROOT_APP              parent app-of-apps Application (default: applications-root)
#   MAINT_STATE_DIR             where state files are written (default: $XDG_STATE_HOME/argocd-maintenance)
#
# --pause-root: the parent is paused whenever it has auto-sync on (with selfHeal it re-applies the child within seconds,
#   without it any new root revision does); `on` refuses to start without the flag in that case.
# --force: go on although the runners show job activity (a job started in the last 10 minutes, or a job container that
#   is running now): running jobs fail when the application goes away.
# --defaults: `off` without a marker assumes one replica and auto-sync with prune and self-heal.
# While the mode is on the application does not sync: a tag move does NOT deploy.
set -euo pipefail

usage() { echo "usage: $0 on|off|status <label> [--with-runners] [--force] [--pause-root] [--defaults]" >&2; exit 2; }
action="${1:-}"; label="${2:-}"; [ -n "$action" ] && [ -n "$label" ] || usage; shift 2
with_runners=0; force=0; defaults=0; pause_root=0
while [ $# -gt 0 ]; do case "$1" in --with-runners) with_runners=1;; --force) force=1;; --defaults) defaults=1;; --pause-root) pause_root=1;; *) usage;; esac; shift; done

app="${MAINT_APP:?set MAINT_APP to the Argo CD Application name}"
ns="${MAINT_NAMESPACE:?set MAINT_NAMESPACE to the namespace of the workloads}"
health_url="${MAINT_HEALTH_URL:?set MAINT_HEALTH_URL to a URL that answers 200 while the application is up}"
dep="${MAINT_DEPLOYMENT:-$app}"; runners="${MAINT_RUNNERS_STS:-}"; runner_ctr="${MAINT_RUNNER_CONTAINER:-runner}"
job_filter="${MAINT_JOB_CONTAINER_FILTER:-GITEA-ACTIONS-TASK}"; start_pat="${MAINT_JOB_START_PATTERN:-task [0-9]+ repo is}"
argo_ns="${MAINT_ARGOCD_NS:-argocd}"; root_app="${MAINT_ROOT_APP:-applications-root}"
state_dir="${MAINT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/argocd-maintenance}"; key='maintenance-mode/state'
[ $with_runners = 0 ] || [ -n "$runners" ] || { echo "--with-runners needs MAINT_RUNNERS_STS" >&2; exit 2; }

stop() { echo "STOP: $*" >&2; exit 1; }
hz() { curl -s -o /dev/null -m 8 -w '%{http_code}' "$health_url" || true; }
selector() { kubectl get deploy -n "$ns" "$dep" -o json | python3 -I -c 'import sys,json; print(",".join("%s=%s" % kv for kv in json.load(sys.stdin)["spec"]["selector"]["matchLabels"].items()))'; }
# every inspection below FAILS (returns non-zero) when kubectl fails: an inspection that could not run is never read as "nothing there"
app_pods() { local out; out="$(kubectl get pods -n "$ns" -l "$(selector)" --no-headers)" || return 1; printf '%s' "$out" | grep -c . || true; }
runner_pods_all() { local out; out="$(kubectl get pods -n "$ns" --no-headers)" || return 1; printf '%s\n' "$out" | awk -v r="$runners" '$1 ~ "^" r "-[0-9]+$" {print $1}'; }
runner_pods_running() { local out; out="$(kubectl get pods -n "$ns" --no-headers)" || return 1; printf '%s\n' "$out" | awk -v r="$runners" '$1 ~ "^" r "-[0-9]+$" && $3 == "Running" {print $1}'; }
# jobs that are running RIGHT NOW: the job containers in the docker of each running runner pod (a pod that is not running cannot run a job).
# The log check in `on` only sees jobs that STARTED in the last 10 minutes; a long job that started earlier would be missed.
active_jobs() { local n=0 c p pods; pods="$(runner_pods_running)" || return 1; for p in $pods; do c="$(kubectl exec -n "$ns" "$p" -c "$runner_ctr" -- docker ps -q --filter "name=$job_filter")" || return 1; n=$((n + $(printf '%s' "$c" | grep -c . || true))); done; echo "$n"; }
jp() { kubectl get application -n "$argo_ns" "$1" -o jsonpath="$2"; }
marker() { kubectl get application -n "$argo_ns" "$app" -o json | python3 -I -c 'import sys,json; print(json.load(sys.stdin)["metadata"].get("annotations",{}).get(sys.argv[1],""))' "$key"; }
pj() { python3 -I -c "import sys,json; d=json.loads(sys.argv[1]); print($2)" "$1"; }

echo "maintenance '$action' for $app ($label) at $(date '+%a %Y-%m-%d %H:%M %Z')"
case "$action" in
status)
  m="$(marker)"; echo "  marker: ${m:-none (not in maintenance mode)}"
  echo "  app: $(jp "$app" '{.status.sync.status}/{.status.health.status}') | autoSync: $(jp "$app" '{.spec.syncPolicy.automated}')"
  echo "  deployment replicas: $(kubectl get deploy -n "$ns" "$dep" -o jsonpath='spec={.spec.replicas} ready={.status.readyReplicas}')"
  [ -z "$runners" ] || echo "  runners: $(kubectl get sts -n "$ns" "$runners" -o jsonpath='spec={.spec.replicas} ready={.status.readyReplicas}')"
  echo "  health: $(hz)"; if [ -n "$runners" ]; then act="$(active_jobs)" && echo "  job containers running on the runners now: $act" || echo "  job containers running on the runners now: UNKNOWN (the inspection failed)"; fi;;
on)
  [ -z "$(marker)" ] || stop "already in maintenance mode (see status)"
  [ "$(jp "$app" '{.status.sync.status}/{.status.health.status}')" = Synced/Healthy ] || stop "application $app is not Synced/Healthy"
  [ "$(jp "$app" '{.status.operationState.phase}')" != Running ] || stop "an Argo CD sync is running"
  if [ -n "$runners" ]; then
    pods="$(runner_pods_running)" || stop "could not list the runner pods: runner activity is unknown, nothing was changed"
    busy=0; for p in $pods; do l="$(kubectl logs -n "$ns" "$p" -c "$runner_ctr" --since=10m)" || stop "could not read the log of $p: runner activity is unknown, nothing was changed"; b="$(printf '%s\n' "$l" | grep -ciE "$start_pat" || true)"; busy=$((busy + b)); done
    if [ "$busy" != 0 ]; then [ $force = 1 ] && echo "  note: $busy job start line(s) in the last 10 minutes, going on because of --force" || stop "the runners started $busy job(s) in the last 10 minutes: wait until they are done or use --force"; else echo "  ok: no job started in the last 10 minutes"; fi
    act="$(active_jobs)" || stop "could not inspect the running jobs on the runners (listing or exec failed): runner activity is unknown, nothing was changed"
    if [ "$act" != 0 ]; then [ $force = 1 ] && echo "  note: $act job container(s) are running now, going on because of --force" || stop "$act job container(s) are running on the runners right now (a long job that started earlier is not seen by the 10-minute check, and it fails when the application goes away): wait until they finish or use --force"; else echo "  ok: no job container is running on the runners"; fi
  fi
  rsp="$(jp "$root_app" '{.spec.syncPolicy}')"; rheal="$(jp "$root_app" '{.spec.syncPolicy.automated.selfHeal}')"; rauto="$(jp "$root_app" '{.spec.syncPolicy.automated}')"
  if [ -n "$rauto" ] && [ $pause_root = 0 ]; then stop "$root_app has auto-sync on (selfHeal: ${rheal:-off}): with selfHeal it re-applies the sync policy of $app within seconds, without it any new root revision syncs and restores the pause. Run again with --pause-root (the root's auto-sync is paused and restored by off)"; fi
  g="$(kubectl get deploy -n "$ns" "$dep" -o jsonpath='{.spec.replicas}')"; r=-1; [ -z "$runners" ] || r="$(kubectl get sts -n "$ns" "$runners" -o jsonpath='{.spec.replicas}')"; sp="$(jp "$app" '{.spec.syncPolicy}')"
  [ -n "$sp" ] || stop "the application has no syncPolicy to record"
  [ -n "$rsp" ] || rsp='{}'
  state="$(python3 -I -c 'import sys,json; d={"since":sys.argv[1],"replicas":int(sys.argv[2]),"runners":int(sys.argv[3]),"withRunners":bool(int(sys.argv[4])),"syncPolicy":json.loads(sys.argv[5])}
if int(sys.argv[6]): d["rootSyncPolicy"]=json.loads(sys.argv[7])
print(json.dumps(d,separators=(",",":")))' "$(date +%FT%T%z)" "$g" "$r" "$with_runners" "$sp" "$pause_root" "$rsp")"
  mkdir -p "$state_dir"; sf="$state_dir/$app-$label-$(date +%Y%m%d-%H%M%S).json"; ( umask 077; printf '%s\n' "$state" > "$sf" ); echo "  state written to $sf (for a manual restore if the script dies)"
  if [ $pause_root = 1 ]; then
    # pause the parent FIRST and wait until it is quiet: a sync decided before the pause would re-apply the child within seconds
    kubectl patch application -n "$argo_ns" "$root_app" --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null; echo "  auto-sync of $root_app paused, waiting 25 s until its controller is quiet"; sleep 25
    ra="$(jp "$root_app" '{.spec.syncPolicy.automated}')"; ro="$(jp "$root_app" '{.operation}{.status.operationState.phase}')"
    case "$ro" in *Running*) stop "the root still runs a sync after the pause: wait and run off, then try again";; esac
    [ -z "$ra" ] || stop "the root's auto-sync came back ('$ra'): something else manages it. State is in $sf; restore with off --defaults if needed"
  fi
  kubectl annotate application -n "$argo_ns" "$app" "$key=$state" >/dev/null; echo "  recorded: $state"
  kubectl patch application -n "$argo_ns" "$app" --type=merge -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null
  [ -z "$(jp "$app" '{.spec.syncPolicy.automated}')" ] || stop "could not pause auto-sync (state recorded in the annotation, run off to undo)"
  echo "  auto-sync paused"
  # pausing auto-sync does not cancel a sync that is pending or running: wait until the child (and the root) are idle, and do NOT scale down on a timeout
  watch_apps="$app"; [ $pause_root = 0 ] || watch_apps="$app $root_app"
  for a in $watch_apps; do
    idle=0; for _ in $(seq 1 24); do op="$(jp "$a" '{.operation}')"; ph="$(jp "$a" '{.status.operationState.phase}')"; if [ -z "$op" ] && [ "$ph" != Running ]; then idle=1; break; fi; sleep 5; done
    [ $idle = 1 ] || stop "application $a still has a pending or running sync after 2 minutes: nothing was scaled down. The state is recorded, run off to restore the sync policy and try again later"
  done
  echo "  ok: no pending or running sync on $watch_apps"
  kubectl scale deploy -n "$ns" "$dep" --replicas=0 >/dev/null; [ $with_runners = 0 ] || kubectl scale sts -n "$ns" "$runners" --replicas=0 >/dev/null
  n=1; r_left=0; for _ in $(seq 1 60); do n="$(app_pods)" || stop "could not list the application pods (the scale-down was requested, check by hand)"; r_left=0; [ $with_runners = 0 ] || { r_left="$(runner_pods_all | wc -l)" || stop "could not list the runner pods"; }; [ "$n" = 0 ] && [ "$r_left" = 0 ] && break; sleep 5; done
  echo "  application pods left: $n$([ $with_runners = 1 ] && echo ", runner pods left: $r_left")"
  { [ "$n" = 0 ] && [ "$r_left" = 0 ]; } || stop "pods are still there after 5 minutes (application $n, runners $r_left): maintenance is NOT confirmed. Wait for them to go, or run off to undo"
  c="$(hz)"; echo "  health now: $c (expected not 200)"; [ "$c" != 200 ] || stop "the application still answers 200 (run off to undo)"
  echo "  checking for 45 s that nothing brings the application back"; sleep 45
  a="$(jp "$app" '{.spec.syncPolicy.automated}')"; n="$(app_pods)" || stop "could not list the application pods"; r_left=0; [ $with_runners = 0 ] || { r_left="$(runner_pods_all | wc -l)" || stop "could not list the runner pods"; }
  if [ -n "$a" ] || [ "$n" != 0 ] || [ "$r_left" != 0 ]; then stop "the pause did not hold (auto-sync '$a', application pods $n, runner pods $r_left): something re-applied the application or scaled it up. Run off to restore the recorded state"; fi
  echo "  ok: auto-sync still paused, the application is still at 0"
  echo "MAINTENANCE MODE ON. Auto-sync is paused: undo with: $0 off $label";;
off)
  m="$(marker)"
  if [ -z "$m" ] && [ $defaults = 1 ]; then lf="$(ls -1t "$state_dir/$app-$label-"*.json 2>/dev/null | head -1 || true)"; if [ -n "$lf" ]; then m="$(cat "$lf")"; echo "  no marker on the Application: using the newest state file $lf"; fi; fi
  if [ -z "$m" ]; then [ $defaults = 1 ] || stop "no maintenance marker on $app: if you are sure, run with --defaults (1 replica, auto-sync with prune and self-heal)"; m='{"replicas":1,"runners":-1,"withRunners":false,"syncPolicy":{"automated":{"enabled":true,"prune":true,"selfHeal":true},"syncOptions":["ApplyOutOfSyncOnly=true","CreateNamespace=true"]}}'; echo "  WARNING: no marker, using the defaults"; fi
  g="$(pj "$m" 'd["replicas"]')"; r="$(pj "$m" 'd["runners"] if d["withRunners"] else -1')"; sp="$(pj "$m" 'json.dumps(d["syncPolicy"])')"
  [ "$r" = -1 ] || { kubectl scale sts -n "$ns" "$runners" --replicas="$r" >/dev/null; echo "  runners scaled to $r"; }
  kubectl scale deploy -n "$ns" "$dep" --replicas="$g" >/dev/null; echo "  deployment scaled to $g"
  kubectl rollout status deploy -n "$ns" "$dep" --timeout=300s >/dev/null || stop "the deployment did not become ready in 5 minutes (still in maintenance mode, auto-sync still paused): read the pod log"
  c=""; for _ in $(seq 1 24); do c="$(hz)"; [ "$c" = 200 ] && break; sleep 5; done; [ "$c" = 200 ] || stop "health answers $c after the scale-up (auto-sync still paused)"
  echo "  the application is back, health 200"
  # Argo CD compares with the revision it has CACHED (a moved tag is seen only after the next poll). With self-heal back on, a stale
  # revision would re-apply the OLD desired state over a change made by hand. So: hard refresh while still paused, wait for a newer comparison.
  # reconciledAt has a resolution of one second: take the reference, wait one second, refresh, and accept only a comparison that is STRICTLY later than the reference
  t_ref=$(date -u +%s); sleep 1; kubectl annotate application -n "$argo_ns" "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null
  fresh=0; rc=""; for _ in $(seq 1 36); do rc="$(jp "$app" '{.status.reconciledAt}')"; if [ -n "$rc" ] && [ "$(date -u -d "$rc" +%s)" -gt "$t_ref" ]; then fresh=1; break; fi; sleep 5; done
  [ $fresh = 1 ] || stop "Argo CD did not compare the application again within 3 minutes after a hard refresh: auto-sync is still paused and the application is back. Check the repo server, then run off again"
  echo "  Argo CD compared again at $rc (revision $(jp "$app" '{.status.sync.revision}' | cut -c1-7)); restoring auto-sync"
  kubectl patch application -n "$argo_ns" "$app" --type=merge -p "{\"spec\":{\"syncPolicy\":$sp}}" >/dev/null
  echo "  auto-sync restored: $(jp "$app" '{.spec.syncPolicy.automated}')"
  rsp="$(pj "$m" 'json.dumps(d["rootSyncPolicy"]) if "rootSyncPolicy" in d else ""')"
  if [ -n "$rsp" ]; then kubectl patch application -n "$argo_ns" "$root_app" --type=merge -p "{\"spec\":{\"syncPolicy\":$rsp}}" >/dev/null; echo "  auto-sync of $root_app restored: $(jp "$root_app" '{.spec.syncPolicy.automated}')"; fi
  s=""; for _ in $(seq 1 24); do s="$(jp "$app" '{.status.sync.status}/{.status.health.status}')"; [ "$s" = Synced/Healthy ] && break; sleep 5; done; echo "  application: $s"
  # the recovery state stays on the Application until both policies are restored AND the application is Synced and Healthy
  if [ "$s" != Synced/Healthy ]; then echo "STOP: the application is '$s', not Synced/Healthy: the maintenance marker is KEPT (run off again after you looked at it)" >&2; exit 1; fi
  kubectl annotate application -n "$argo_ns" "$app" "$key-" >/dev/null
  echo "MAINTENANCE MODE OFF";;
*) usage;;
esac
