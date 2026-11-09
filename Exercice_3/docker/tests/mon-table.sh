#!/usr/bin/env bash
# Tableau comparatif des runs de stress supervisés (MONITOR=1) : une ligne par charge et par config,
# avec erreurs, latence et indicateurs de saturation (connexions, files, CPU, TIME_WAIT).
#
# Appel (depuis Exercice_3/docker/) :
#   tests/mon-table.sh [version]      version de HAProxy, défaut 3.4
#   ex. : tests/mon-table.sh 3.4 > tableau.md
#
# Lit    : results/<version>/stress-r*/<config>/run-*.json   (champ "mon")
# Écrit  : le tableau Markdown sur la sortie standard
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1
V=${1:-3.4}   # version de HAProxy (défaut 3.4)
echo "| Charge | Config | Runs | Erreurs % (min–max) | Débit réel | p99 s | Conn. HAProxy max | Conn. serveur max | File qcur max | SYN_SENT max | CPU HAProxy max % | CPU générateur max % | CPU hôte max % | TIME_WAIT hôte max |"
echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
# Un dossier par charge (stress-r500, stress-r3000...) ; r = la charge, extraite du nom du dossier
for d in results/$V/stress-r*/; do
  r=${d#results/$V/stress-r}; r=${r%/}
  for c in "$d"v*/; do   # une config par sous-dossier ; on saute celles sans run
    [ -n "$(ls "$c"run-*.json 2>/dev/null)" ] || continue
    # jq : avg/min/max sur les runs valides ; les champs .mon.* viennent du résumé de tests/monitor.py
    jq -s -r --arg r "$r" --arg c "$(basename "$c")" '
      def avg: add/length; def mx: max;
      map(select(.syntax=="ok")) as $v
      | "| \($r) | \($c) | \($v|length) | \($v|map(.error_rate_pct)|avg*1000|round/1000) (\($v|map(.error_rate_pct)|min)–\($v|map(.error_rate_pct)|max)) | \($v|map(.rps_actual)|avg|round) | \($v|map(.p99_latency_s)|avg*1000|round/1000) | \($v|map(.mon.max_cur_conns)|max) | \($v|map([.mon.max_s1_scur,.mon.max_s2_scur]|max)|max) | \($v|map(.mon.max_be_qcur)|max) | \($v|map(.mon.max_syn_sent)|max) | \($v|map(.mon.max_haproxy_cpu_pct)|max|round) | \($v|map(.mon.max_loadgen_cpu_pct)|max|round) | \($v|map(.mon.max_host_cpu_pct)|max|round) | \($v|map(.mon.max_host_tcp_tw)|max) |"' "$c"run-*.json
  done
done
