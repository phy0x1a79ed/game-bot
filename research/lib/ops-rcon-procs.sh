#!/usr/bin/env bash
# Usage: ops-rcon-procs.sh. Lists every shell that reaches the game (rlm.sh, act.sh, walkers, polls),
# with its parent Claude session pid, or DETACHED when reparented to init. DETACHED is NOT proof of an orphan:
# background jobs of live sessions detach too. Judge an orphan by age against the seat owner's live task.
ps -eo pid=,ppid=,etimes=,args= | grep -E 'rlm\.sh|act\.sh|walk\.sh|safe-walk|exec-lua|alerts\.sh|upkeep|checkpoint-loop|progress-row' \
  | grep -vE 'grep|ops-rcon-procs|curl ' | while read -r pid ppid age args; do
  owner=$ppid
  while [ "$owner" -gt 1 ]; do
    a=$(tr '\0' ' ' < /proc/$owner/cmdline 2>/dev/null)
    case "$a" in *claude*|/init*) break;; esac
    owner=$(awk '{print $4}' /proc/$owner/stat 2>/dev/null || echo 1)
  done
  a=$(tr '\0' ' ' < /proc/$owner/cmdline 2>/dev/null)
  case "$a" in /init*|"") who=DETACHED;; *) who="session:$owner";; esac
  every=$(grep -oE 'sleep [0-9]+' <<<"$args" | head -1)
  printf '%s\t%s\tage=%ss\t%s\t%s\n' "$pid" "$who" "$age" "${every:-sleep ?}" "$(cut -c1-160 <<<"$args")"
done
