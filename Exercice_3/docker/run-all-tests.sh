#!/usr/bin/env bash
# Super-script : lance le test de bascule sur la config principale et sur chaque config
# versionnée (configs/vNNN), en plusieurs runs, puis calcule les moyennes.
#
# Usage : ./run-all-tests.sh [--runs N] [--version TAG] [--scenario failover|stress] [--report] [config ...]
#   --runs N        nombre de runs par config (défaut 1)
#   --version TAG   tag de l'image haproxy testée (défaut : $HAPROXY_VERSION, sinon 2.3)
#   --scenario S    failover (défaut) : une panne, charge légère ; stress : 10 pannes, ~250 req/s
#   --rate N        stress : requêtes/s visées (défaut 250) ; résultats dans results/<version>/stress-rN/,
#                   (dès 1000 : générateur asynchrone LOADGEN=async) workers = 0,6 x N, supervision (MONITOR=1) et générateur dans un conteneur (GEN=container)
#   --report        ne lance aucun test, recalcule seulement les synthèses
#   config          main, v001, v002... (défaut : main + toutes les versions)
#
# Une config peut contenir un fichier REQUIRES (ex. "3.1") : elle est ignorée avec une
# version de HAProxy plus ancienne.
#
# Résultats : results/<version haproxy>/<config>/run-<date>.json            (failover)
#             results/<version haproxy>/stress/<config>/run-<date>.json     (stress)
#             results/<version haproxy>/SYNTHESE.md ou stress/SYNTHESE.md   (moyennes)
#             results/COMPARATIF-VERSIONS.md          (versions côte à côte)
#
# Les runs sont entrelacés (run 1 de toutes les configs, puis run 2...) pour que les
# variations de la machine pèsent de la même façon sur chaque config.

set -u
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1

RUNS=1; VER=${HAPROXY_VERSION:-2.3}; ONLY_REPORT=0; SC=failover; TARGETS=(); RATE_OPT=
while [ $# -gt 0 ]; do
  case $1 in
    --runs) RUNS=${2:?--runs N}; shift 2 ;;
    --version) VER=${2:?--version TAG}; shift 2 ;;
    --scenario) SC=${2:?--scenario failover|stress}; shift 2 ;;
    --rate) RATE_OPT=${2:?--rate N}; shift 2 ;;
    --report) ONLY_REPORT=1; shift ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done
export HAPROXY_VERSION=$VER

if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(main); for d in configs/v*/; do [ -f "$d/haproxy.cfg" ] && TARGETS+=("$(basename "$d")"); done
fi

cfg_of() { [ "$1" = main ] && echo haproxy.cfg || echo "configs/$1/haproxy.cfg"; }
case "$SC" in
  failover) TEST=tests/test-failover.sh; AGG=tests/aggregate.sh; RDIR="results/$VER"; SYN="results/$VER/SYNTHESE.md"; SECS=35 ;;
  stress)   SD=stress; [ -n "$RATE_OPT" ] && { SD="stress-r$RATE_OPT"; export RATE=$RATE_OPT WORKERS=$(( RATE_OPT * 6 / 10 )) MONITOR=1 GEN=container; [ "$RATE_OPT" -ge 1000 ] && export LOADGEN=async; }
            TEST=tests/test-stress.sh;   AGG="tests/aggregate-stress.sh --dir $SD"; RDIR="results/$VER/$SD"; SYN="results/$VER/$SD/SYNTHESE.md"; SECS=105 ;;
  *) echo "Scénario inconnu : $SC (failover ou stress)"; exit 1 ;;
esac

# Garde les configs compatibles avec la version testée
KEEP=()
for t in "${TARGETS[@]}"; do
  [ -f "$(cfg_of "$t")" ] || { echo "Ignorée (introuvable) : $t"; continue; }
  req=$(cat "configs/$t/REQUIRES" 2>/dev/null | head -n1)
  if [ -n "$req" ] && [[ "$VER" =~ ^[0-9] ]] && [ "$(printf '%s\n%s\n' "$req" "$VER" | sort -V | head -n1)" != "$req" ]; then
    echo "Ignorée : $t demande HAProxy >= $req (testé : $VER)"; continue
  fi
  KEEP+=("$t")
done

if [ "$ONLY_REPORT" -eq 0 ]; then
  [ ${#KEEP[@]} -gt 0 ] || { echo "Aucune config à tester."; exit 1; }
  echo "HAProxy $VER : ${#KEEP[@]} config(s) x $RUNS run(s), scénario $SC, environ $(( ${#KEEP[@]} * RUNS * SECS / 60 )) min : ${KEEP[*]}"
  docker compose up -d webserver1 webserver2 >/dev/null 2>&1
  SKIP=" "
  for run in $(seq 1 "$RUNS"); do
    echo; echo "######## Run $run / $RUNS ########"
    for t in "${KEEP[@]}"; do
      case "$SKIP" in *" $t "*) continue ;; esac
      if [ "$run" -gt 1 ]; then export SKIP_SYNTAX=1; else export SKIP_SYNTAX=0; fi
      "$TEST" "$(cfg_of "$t")" "$RDIR/$t" || { echo "   -> $t écartée pour la suite"; SKIP="$SKIP$t "; }
      sleep 2
    done
  done
fi

echo; $AGG "$VER"
echo; cat "$SYN"
