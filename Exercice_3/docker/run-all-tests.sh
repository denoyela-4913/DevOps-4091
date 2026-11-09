#!/usr/bin/env bash
# Super-script : lance un scénario de test (bascule ou stress) sur la config principale et/ou sur
# des configs versionnées (configs/vNNN), en plusieurs runs, puis calcule les moyennes.
#
# Appel (depuis Exercice_3/docker/) :
#   ./run-all-tests.sh [--runs N] [--version TAG] [--scenario failover|stress] [--rate N] [--report] [config ...]
#
# Paramètres                                                   défaut
#   --runs N       nombre de runs par config                    1
#   --version TAG  tag de l'image haproxy testée                $HAPROXY_VERSION, sinon 2.3
#   --scenario S   failover : une panne, charge légère          failover
#                  stress   : 10 pannes sous charge
#   --rate N       stress seulement : requêtes/s visées         250 (résultats dans results/<version>/stress/)
#                  Si N est donné : résultats dans results/<version>/stress-rN/, workers = 0,6 x N,
#                  supervision (MONITOR=1) et générateur en conteneur (GEN=container) ;
#                  dès N >= 1000, générateur asynchrone (LOADGEN=async)
#   --report       ne lance aucun test, recalcule seulement les synthèses
#   config         main, v001, v002... (un ou plusieurs)        main + toutes les versions
#
# Exemples :
#   ./run-all-tests.sh --runs 5 --version 2.3 v001 v002
#   ./run-all-tests.sh --scenario stress --rate 3000 --runs 6 --version 3.4 v006 v013
#   ./run-all-tests.sh --report --version 3.4
#
# Une config peut contenir un fichier REQUIRES (ex. "3.1") : elle est ignorée avec une
# version de HAProxy plus ancienne.
#
# Résultats : results/<version haproxy>/<config>/run-<date>.json            (failover)
#             results/<version haproxy>/stress[-rN]/<config>/run-<date>.json (stress)
#             results/<version haproxy>/SYNTHESE.md ou stress[-rN]/SYNTHESE.md (moyennes)
#             results/COMPARATIF-VERSIONS.md          (versions côte à côte, failover)
#
# Les runs sont entrelacés (run 1 de toutes les configs, puis run 2...) pour que les
# variations de la machine pèsent de la même façon sur chaque config.

set -u
cd "$(cd "$(dirname "$0")" && pwd)" || exit 1

# --- Paramètres (valeurs par défaut) puis lecture de la ligne de commande ---
RUNS=1; VER=${HAPROXY_VERSION:-2.3}; ONLY_REPORT=0; SC=failover; TARGETS=(); RATE_OPT=
while [ $# -gt 0 ]; do   # $# = nombre d'arguments restants ; shift N les consomme
  case $1 in
    # ${2:?msg} : arrête le script avec "msg" si l'argument est absent
    --runs) RUNS=${2:?--runs N}; shift 2 ;;
    --version) VER=${2:?--version TAG}; shift 2 ;;
    --scenario) SC=${2:?--scenario failover|stress}; shift 2 ;;
    --rate) RATE_OPT=${2:?--rate N}; shift 2 ;;
    --report) ONLY_REPORT=1; shift ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done
export HAPROXY_VERSION=$VER   # lu par docker-compose.yml (image haproxy:<tag>) et par les scripts de test

# Sans config indiquée : main + chaque dossier configs/v*/ qui contient un haproxy.cfg
if [ ${#TARGETS[@]} -eq 0 ]; then   # ${#TARGETS[@]} = taille du tableau
  TARGETS=(main); for d in configs/v*/; do [ -f "$d/haproxy.cfg" ] && TARGETS+=("$(basename "$d")"); done
fi

# cfg_of <nom> : chemin du fichier de config (main = haproxy.cfg à la racine)
cfg_of() { [ "$1" = main ] && echo haproxy.cfg || echo "configs/$1/haproxy.cfg"; }
# Choix du scénario : script de test, script d'agrégation, dossier de résultats, fichier de synthèse,
# et SECS = durée approximative d'un run (sert seulement à afficher l'estimation de durée).
# Avec --rate : charge N, workers = 60 % de N (entier : N*6/10), supervision + générateur en conteneur,
# et générateur asynchrone dès 1000 req/s. Ces variables sont lues par tests/test-stress.sh.
case "$SC" in
  failover) TEST=tests/test-failover.sh; AGG=tests/aggregate.sh; RDIR="results/$VER"; SYN="results/$VER/SYNTHESE.md"; SECS=35 ;;
  stress)   SD=stress; [ -n "$RATE_OPT" ] && { SD="stress-r$RATE_OPT"; export RATE=$RATE_OPT WORKERS=$(( RATE_OPT * 6 / 10 )) MONITOR=1 GEN=container; [ "$RATE_OPT" -ge 1000 ] && export LOADGEN=async; }
            TEST=tests/test-stress.sh;   AGG="tests/aggregate-stress.sh --dir $SD"; RDIR="results/$VER/$SD"; SYN="results/$VER/$SD/SYNTHESE.md"; SECS=105 ;;
  *) echo "Scénario inconnu : $SC (failover ou stress)"; exit 1 ;;
esac

# Garde les configs compatibles avec la version testée (fichier REQUIRES = version minimale).
# `sort -V` trie par numéro de version : si la plus petite des deux n'est pas $req, alors $VER < $req.
KEEP=()
for t in "${TARGETS[@]}"; do
  [ -f "$(cfg_of "$t")" ] || { echo "Ignorée (introuvable) : $t"; continue; }
  req=$(cat "configs/$t/REQUIRES" 2>/dev/null | head -n1)
  if [ -n "$req" ] && [[ "$VER" =~ ^[0-9] ]] && [ "$(printf '%s\n%s\n' "$req" "$VER" | sort -V | head -n1)" != "$req" ]; then
    echo "Ignorée : $t demande HAProxy >= $req (testé : $VER)"; continue
  fi
  KEEP+=("$t")
done

# Boucle principale : runs entrelacés. SKIP = configs invalides, écartées pour les runs suivants.
# La syntaxe n'est vérifiée qu'au 1er run (SKIP_SYNTAX=1 ensuite).
if [ "$ONLY_REPORT" -eq 0 ]; then
  [ ${#KEEP[@]} -gt 0 ] || { echo "Aucune config à tester."; exit 1; }
  echo "HAProxy $VER : ${#KEEP[@]} config(s) x $RUNS run(s), scénario $SC, environ $(( ${#KEEP[@]} * RUNS * SECS / 60 )) min : ${KEEP[*]}"
  docker compose up -d webserver1 webserver2 >/dev/null 2>&1
  SKIP=" "
  for run in $(seq 1 "$RUNS"); do
    echo; echo "######## Run $run / $RUNS ########"
    for t in "${KEEP[@]}"; do
      case "$SKIP" in *" $t "*) continue ;; esac   # motif *" nom "* : nom présent dans la liste
      if [ "$run" -gt 1 ]; then export SKIP_SYNTAX=1; else export SKIP_SYNTAX=0; fi
      "$TEST" "$(cfg_of "$t")" "$RDIR/$t" || { echo "   -> $t écartée pour la suite"; SKIP="$SKIP$t "; }
      sleep 2
    done
  done
fi

# Synthèse finale (sans guillemets autour de $AGG : il peut contenir des options, ex. --dir stress-r500)
echo; $AGG "$VER"
echo; cat "$SYN"
