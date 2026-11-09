#!/usr/bin/env bash
# Moyenne les runs du scénario stress, version de HAProxy par version de HAProxy.
#
# Appel (depuis Exercice_3/docker/) :
#   tests/aggregate-stress.sh [--last N] [--dir <sous-dossier>] [version ...]
#   --last N       ne garde que les N derniers runs de chaque config   (défaut : tous)
#   --dir <nom>    sous-dossier de results/<version>/ à traiter        (défaut : stress ; ex. stress-r500)
#   version        ex. 3.4                                             (défaut : toutes celles qui ont ce sous-dossier)
#   ex. : tests/aggregate-stress.sh --dir stress-r3000 3.4
#
# Lit    : results/<version>/<sous-dossier>/<config>/run-*.json
# Écrit  : results/<version>/<sous-dossier>/SYNTHESE.md et SYNTHESE.json (avec --last N : SYNTHESE-lastN.*)

set -u
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

# --- Arguments : --last N (défaut 0 = tous), --dir <sous-dossier> (défaut stress), le reste = versions ---
LAST=0; TAGS=(); SUF=""; SD=stress
while [ $# -gt 0 ]; do
  case $1 in --last) LAST=${2:?--last N}; shift 2 ;; --dir) SD=${2:?--dir stress-r500}; shift 2 ;; *) TAGS+=("$1"); shift ;; esac
done
[ "$LAST" -gt 0 ] && SUF="-last$LAST"
if [ ${#TAGS[@]} -eq 0 ]; then for d in results/[0-9]*/$SD/; do [ -d "$d" ] && TAGS+=("$(basename "$(dirname "$d")")"); done; fi
[ ${#TAGS[@]} -gt 0 ] || { echo "Aucun résultat stress dans results/<version>/stress/"; exit 1; }

# desc_of <config> : 1re ligne de configs/<config>/DESCRIPTION.txt (texte du tableau)
desc_of() { if [ "$1" = main ]; then echo "Config principale (haproxy.cfg)"; else head -n1 "configs/$1/DESCRIPTION.txt" 2>/dev/null; fi; }

# Programme jq appliqué aux runs d'une config : moyenne (mean), écart-type (sd), arrondi à 3 décimales (r)
SUMMARY='
def mean: if length==0 then null else (add/length) end;
def sd: if length<2 then 0 else (mean as $m | ((map((.-$m)*(.-$m))|add)/(length-1))|sqrt) end;
def r: if .==null then null else (.*1000|round)/1000 end;
(map(select(.syntax=="ok"))) as $v
| ($v|map(.error_rate_pct)) as $rate
| ($v|map(select(.detection_mean_s>=0)|.detection_mean_s)) as $det
| {cfg:$cfg,desc:$desc,runs:($v|length),invalid:(length-($v|length)),
   exact:($v|map(.haproxy_version)|unique|join(",")),
   cycles:($v|map(.cycles)|max),rate:($v|map(.rate_target)|max),
   rate_mean:($rate|mean|r),rate_sd:($rate|sd|r),rate_max:($rate|max|r),rate_min:($rate|min|r),
   errors_mean:($v|map(.errors)|mean|r),requests_mean:($v|map(.requests)|mean|r),
   rps_mean:($v|map(.rps_actual)|mean|r),
   p99_mean:($v|map(.p99_latency_s)|mean|r),max_latency_worst:($v|map(.max_latency_s)|max),
   detected_mean:($v|map(.detected_cycles)|mean|r),
   detection_mean:($det|mean|r),
   cycles_err_mean:($v|map(.cycles_with_errors)|mean|r),
   up_events_mean:($v|map(.up_events)|mean|r)}'

# f : affiche n/a pour une valeur absente. Boucle : une synthèse JSON puis Markdown par version.
FMT='def f: if .==null then "n/a" else tostring end;'
for tag in "${TAGS[@]}"; do
  base="results/$tag/$SD"; [ -d "$base" ] || { echo "Absent : $base"; continue; }
  ALL=$(mktemp)
  for cdir in "$base"/*/; do
    [ -d "$cdir" ] || continue; cfg=$(basename "$cdir")
    files=$(ls "$cdir"run-*.json 2>/dev/null | sort); [ -n "$files" ] || continue
    [ "$LAST" -gt 0 ] && files=$(echo "$files" | tail -n "$LAST")
    # (jq -s lit tous les fichiers comme un seul tableau ; $files volontairement sans guillemets)
    # shellcheck disable=SC2086
    jq -s --arg cfg "$cfg" --arg desc "$(desc_of "$cfg")" "$SUMMARY" $files >> "$ALL"
  done
  jq -s 'sort_by(.cfg)' "$ALL" > "$base/SYNTHESE$SUF.json"; rm -f "$ALL"
  {
    echo "# Synthèse stress HAProxy $tag ($SD)"
    echo
    echo "Généré le $(date '+%Y-%m-%d %H:%M:%S') par tests/aggregate-stress.sh$([ "$LAST" -gt 0 ] && echo " (--last $LAST)"). Version(s) exacte(s) : $(jq -r '[.[].exact]|unique|join(", ")' "$base/SYNTHESE$SUF.json")."
    echo
    echo "Scénario : webserver1 est arrêté puis redémarré $(jq -r '[.[].cycles]|max' "$base/SYNTHESE$SUF.json") fois de suite, sous une charge continue d'environ $(jq -r '[.[].rate]|max' "$base/SYNTHESE$SUF.json") requêtes/s. Valeurs : moyenne sur les runs."
    echo
    echo "| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    jq -r "$FMT"'.[] |
      "| \(.cfg) | \(.desc) | \(.runs)\(if .invalid>0 then " (+\(.invalid) invalide)" else "" end) | \(.rate_mean|f) | \(.rate_min|f) – \(.rate_max|f) | \(.rate_sd|f) | \(.requests_mean|f) | \(.rps_mean|f) | \(.p99_mean|f) | \(.max_latency_worst|f) | \(.detected_mean|f)/\(.cycles) | \(.detection_mean|f) | \(.cycles_err_mean|f)/\(.cycles) |"' "$base/SYNTHESE$SUF.json"
    echo
    echo "Lecture : \"Pannes détectées\" = nombre moyen de pannes (sur $(jq -r '[.[].cycles]|max' "$base/SYNTHESE$SUF.json")) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. \"Pannes avec erreurs\" = pannes pendant lesquelles au moins une requête a échoué."
  } > "$base/SYNTHESE$SUF.md"
  echo "Synthèse : $base/SYNTHESE$SUF.md"
done
