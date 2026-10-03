#!/usr/bin/env bash
# Usage: ops-audit-coverage.sh [WINDOW_S]. Two coverage snapshots WINDOW_S apart (default 150);
# prints a TSV: class recipe items machines working per_min stock idle_status net_stock. class a = made now, b = stock only, c = none.
R=/home/tony/agentic_workspace/projects/game-bot/factorio/research
win=${1:-150}
# One sweep costs ~28 ms of engine script time, so it declares budget_ms=40 instead of tripping OVER_BUDGET.
snap() { "$R/lib/act.sh" exec_lua "${RLM_SEAT:-seat-03ce23d6}" path="$R/lib/ops-audit-coverage.lua" budget_ms=40 | jq -r .output; }
a=$(snap); sleep "$win"; b=$(snap)
awk -F'|' -v A="$a" -v B="$b" 'BEGIN {
  n = split(A, la, "\n"); for (i = 1; i <= n; i++) { if (la[i] ~ /^tick/) { split(la[i], t, " "); t0 = t[2] } else { split(la[i], f, "|"); c0[f[2]] = f[7] } }
  n = split(B, lb, "\n"); for (i = 1; i <= n; i++) {
    if (lb[i] ~ /^tick/) { split(lb[i], t, " "); t1 = t[2]; continue }
    split(lb[i], f, "|"); rows[++k] = lb[i]
  }
  min = (t1 - t0) / 3600; if (min <= 0) min = 1
  printf "class\trecipe\titems\tmachines\tworking\tper_min\tstock\tidle_status\tnet_stock\n"
  for (j = 1; j <= k; j++) {
    split(rows[j], f, "|"); split(f[4], am, ","); split(f[8], st, ",")
    rate = (f[7] - c0[f[2]]) * am[1] / min; tot = 0; for (s in st) tot += st[s]
    cls = (rate > 0) ? "a" : (tot > 0 ? "b" : "c")
    printf "%s\t%s\t%s\t%d\t%d\t%.1f\t%s\t%s\t%s\n", cls, f[2], f[3], f[5], f[6], rate, f[8], f[9], f[10]
  }
}' | sort
