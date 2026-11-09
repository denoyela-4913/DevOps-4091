#!/usr/bin/env bash
# Moyenne les runs du scénario « bascule » de chaque config, version de HAProxy par version de HAProxy.
#
# Appel (depuis Exercice_3/docker/) :
#   tests/aggregate.sh [--last N] [version ...]
#   --last N   ne garde que les N derniers runs de chaque config        (défaut : tous)
#   version    dossier(s) results/<version> à traiter, ex. 2.3 3.4      (défaut : toutes, dossiers commençant par un chiffre)
#   ex. : tests/aggregate.sh --last 3 2.3
#
# Lit    : results/<version>/<config>/run-*.json
# Écrit  : results/<version>/SYNTHESE.md et SYNTHESE.json (avec --last N : SYNTHESE-lastN.*)
#          results/COMPARATIF-VERSIONS[-lastN].md (même config, versions côte à côte)

set -u
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

# --- Arguments : --last N (défaut 0 = tous les runs) ; le reste = versions de HAProxy à traiter ---
LAST=0; TAGS=()
SUF=""
while [ $# -gt 0 ]; do
  case $1 in --last) LAST=${2:?--last N}; shift 2 ;; *) TAGS+=("$1"); shift ;; esac
done
[ "$LAST" -gt 0 ] && SUF="-last$LAST"
if [ ${#TAGS[@]} -eq 0 ]; then for d in results/[0-9]*/; do [ -d "$d" ] && TAGS+=("$(basename "$d")"); done; fi
[ ${#TAGS[@]} -gt 0 ] || { echo "Aucun résultat dans results/<version>/"; exit 1; }

# desc_of <config> : 1re ligne de configs/<config>/DESCRIPTION.txt (texte du tableau)
desc_of() { if [ "$1" = main ]; then echo "Config principale (haproxy.cfg)"; else head -n1 "configs/$1/DESCRIPTION.txt" 2>/dev/null; fi; }

# Programme jq appliqué à tous les runs d'une config : moyenne (mean), écart-type (sd), arrondi à 3 décimales (r).
# Les runs à syntaxe invalide sont comptés à part (invalid) ; -1 = valeur « jamais » exclue des moyennes.
SUMMARY='
def mean: if length==0 then null else (add/length) end;
def sd: if length<2 then 0 else (mean as $m | ((map((.-$m)*(.-$m))|add)/(length-1))|sqrt) end;
def r: if .==null then null else (.*1000|round)/1000 end;
(map(select(.syntax=="ok"))) as $v
| ($v|map(select(.requests>0)|.errors*100/.requests)) as $rate
| ($v|map(select(.detection_s>=0)|.detection_s)) as $det
| ($v|map(select(.recovery_s>=0)|.recovery_s)) as $rec
| ($v|map(select(.up_s>=0)|.up_s)) as $up
| {tag:$tag,cfg:$cfg,desc:$desc,runs:($v|length),invalid:(length-($v|length)),
   exact:($v|map(.haproxy_version)|unique|join(",")),
   rate_mean:($rate|mean|r),rate_sd:($rate|sd|r),rate_max:($rate|max|r),
   err_mean:($v|map(.errors)|mean|r),
   lat_max_mean:($v|map(.max_latency_s)|mean|r),lat_max_worst:($v|map(.max_latency_s)|max),
   lat_avg_mean:($v|map(.avg_latency_s)|mean|r),
   det_mean:($det|mean|r),det_sd:($det|sd|r),det_missed:(($v|length)-($det|length)),
   rec_mean:($rec|mean|r),rec_missed:(($v|length)-($rec|length)),
   up_mean:($up|mean|r)}'

# 1. Une synthèse JSON par (version, config), accumulée dans un fichier temporaire
ALL=$(mktemp); trap 'rm -f "$ALL"' EXIT
for tag in "${TAGS[@]}"; do
  [ -d "results/$tag" ] || { echo "Version absente : results/$tag"; continue; }
  for cdir in results/"$tag"/*/; do
    [ -d "$cdir" ] || continue; cfg=$(basename "$cdir")
    files=$(ls "$cdir"run-*.json 2>/dev/null | sort); [ -n "$files" ] || continue
    [ "$LAST" -gt 0 ] && files=$(echo "$files" | tail -n "$LAST")
    # (jq -s lit tous les fichiers comme un seul tableau ; $files volontairement sans guillemets)
    # shellcheck disable=SC2086
    jq -s --arg tag "$tag" --arg cfg "$cfg" --arg desc "$(desc_of "$cfg")" "$SUMMARY" $files >> "$ALL"
  done
done

# 2. Une synthèse Markdown par version (f : affiche n/a pour une valeur absente)
FMT='def f: if .==null then "n/a" else tostring end;'
for tag in "${TAGS[@]}"; do
  [ -d "results/$tag" ] || continue
  jq -s --arg tag "$tag" '[.[]|select(.tag==$tag)]|sort_by(.cfg)' "$ALL" > "results/$tag/SYNTHESE$SUF.json"
  {
    echo "# Synthèse HAProxy $tag"
    echo
    echo "Généré le $(date '+%Y-%m-%d %H:%M:%S') par tests/aggregate.sh$([ "$LAST" -gt 0 ] && echo " (--last $LAST)"). Version(s) exacte(s) : $(jq -r '[.[].exact]|unique|join(", ")' "results/$tag/SYNTHESE$SUF.json")."
    echo
    echo "Test : arrêt de webserver1 pendant 15 s avec des requêtes en continu, puis redémarrage. Valeurs : moyenne sur les runs (± écart-type pour le taux d'erreur et la détection)."
    echo
    echo "| Config | Description | Runs | Taux d'erreur moyen (%) | Pire run (%) | Erreurs moy. | Latence max moy. (s) | Latence max pire (s) | Détection HAProxy (s) | Retour à 2 serveurs (s) | Déclaré UP (s) |"
    echo "|---|---|---|---|---|---|---|---|---|---|---|"
    jq -r "$FMT"'.[] |
      "| \(.cfg) | \(.desc) | \(.runs)\(if .invalid>0 then " (+\(.invalid) invalide)" else "" end) | \(.rate_mean|f) ± \(.rate_sd|f) | \(.rate_max|f) | \(.err_mean|f) | \(.lat_max_mean|f) | \(.lat_max_worst|f) | \(.det_mean|f) ± \(.det_sd|f)\(if .det_missed>0 then " (jamais HS : \(.det_missed))" else "" end) | \(.rec_mean|f)\(if .rec_missed>0 then " (non revenu : \(.rec_missed))" else "" end) | \(.up_mean|f) |"' "results/$tag/SYNTHESE$SUF.json"
    echo
    echo "Lecture : \"Détection HAProxy\" est le délai entre l'arrêt du serveur et son passage HS dans les logs de HAProxy. Un serveur \"jamais HS\" est resté en service pendant tout le test. Le taux d'erreur est ce que voit l'utilisateur."
  } > "results/$tag/SYNTHESE$SUF.md"
  echo "Synthèse : results/$tag/SYNTHESE$SUF.md"
done

# 3. Comparatif entre versions (même config, versions côte à côte) ; group_by(.cfg) regroupe par config
jq -s '.' "$ALL" > "$ALL.json"
VERS=$(jq -r '[.[].tag]|unique|sort|.[]' "$ALL.json" | paste -sd' ')
{
  echo "# Comparatif entre versions de HAProxy"
  echo
  echo "Généré le $(date '+%Y-%m-%d %H:%M:%S'). Chaque case : taux d'erreur moyen (%) / détection moyenne (s) / nombre de runs."
  echo
  printf '| Config |'; for v in $VERS; do printf ' HAProxy %s |' "$v"; done; echo
  printf -- '|---|'; for v in $VERS; do printf -- '---|'; done; echo
  jq -r --arg vers "$VERS" "$FMT"'
    ($vers|split(" ")) as $vs
    | group_by(.cfg)[] as $g
    | "| \($g[0].cfg) |" + ($vs|map(. as $t | ($g|map(select(.tag==$t))|first) as $x
        | if $x==null then " - |" else " \($x.rate_mean|f) % / \($x.det_mean|f) s / \($x.runs) runs |" end)|join(""))' "$ALL.json"
} > results/COMPARATIF-VERSIONS$SUF.md
rm -f "$ALL.json"
echo "Comparatif entre versions : results/COMPARATIF-VERSIONS$SUF.md"
