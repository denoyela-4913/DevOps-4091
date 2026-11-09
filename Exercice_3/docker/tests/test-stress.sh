#!/usr/bin/env bash
# Test de stress : pannes consécutives de webserver1 sous forte charge continue.
#
# Ce que fait le script : démarre un HAProxy temporaire (port 18080) avec la config testée,
# lance un ou plusieurs générateurs de charge (~RATE req/s), arrête/redémarre webserver1
# CYCLES fois, puis calcule erreurs, latences, détection des pannes (tests/stress_metrics.py)
# et, si MONITOR=1, les indicateurs de saturation (tests/monitor.py).
# Le HAProxy principal (port 8080) n'est pas touché, mais webserver1 est arrêté et redémarré.
#
# Appel (depuis Exercice_3/docker/) :
#   [VARIABLES=valeur ...] tests/test-stress.sh <fichier_haproxy.cfg> <dossier_resultats>
#   ex. : RATE=3000 LOADGEN=async GEN=container MONITOR=1 tests/test-stress.sh configs/v006/haproxy.cfg results/essai
# (d'ordinaire appelé par run-all-tests.sh)
#
# Arguments : 1 = config à tester (obligatoire) ; 2 = dossier des résultats (obligatoire)
# Variables d'environnement (valeur par défaut entre parenthèses) :
#   HAPROXY_VERSION (2.3)  tag de l'image haproxy
#   PORT (18080)           port publié du HAProxy de test
#   SKIP_SYNTAX (0)        1 = ne pas vérifier la syntaxe de la config
#   CYCLES (10)            nombre de pannes à la suite
#   DOWN_S (3)             secondes pendant lesquelles webserver1 reste arrêté
#   UP_S (5)               secondes entre le redémarrage et la panne suivante
#   RATE (250)             requêtes par seconde visées (le test simple en envoie ~5)
#   WORKERS (150)          connexions concurrentes du générateur (avec LOADGEN=async : plafond de requêtes
#                          en vol, remplacé par CAP, défaut 30000)
#   WARMUP (3) · COOLDOWN (5)  secondes de charge avant la 1re panne / après la dernière
#   LOADGEN (threads)      async = tests/loadgen_async.py (boucle ouverte, ~10x moins de CPU, un processus
#                          par 1500 req/s) ; sinon tests/loadgen.py (un processus par 250 req/s)
#   GEN (host)             container = générateurs dans des conteneurs python:3-slim sur le réseau Docker
#                          (évite docker-proxy, qui perd des connexions dès ~500 req/s) ; sinon processus de l'hôte
#   MONITOR (0)            1 = supervision (HAProxy, files réseau, CPU, mémoire) : ajoute le champ "mon" au JSON
#                          et écrit run-<date>.mon.tsv à côté
#   STATS_PORT (19999)     port publié pour la socket stats de HAProxy (MONITOR=1)
#   KEEP_RAW (vide)        dossier où garder requêtes brutes et logs HAProxy, pour diagnostic
#
# Sortie : <dossier_resultats>/run-<date>.json (+ .mon.tsv si MONITOR=1). Code retour 1 si la config
# est invalide ou si HAProxy ne démarre pas.

set -u   # une variable non définie est une erreur
# --- Arguments et paramètres (${VAR:-x} = valeur de VAR, sinon x ; ${1:?msg} = obligatoire) ---
CFG_IN=${1:?usage: test-stress.sh <haproxy.cfg> <dossier_resultats>}
OUT=${2:?usage: test-stress.sh <haproxy.cfg> <dossier_resultats>}
export HAPROXY_VERSION=${HAPROXY_VERSION:-2.3}
PORT=${PORT:-18080}; SKIP_SYNTAX=${SKIP_SYNTAX:-0}
CYCLES=${CYCLES:-10}; DOWN_S=${DOWN_S:-3}; UP_S=${UP_S:-5}
RATE=${RATE:-250}; WORKERS=${WORKERS:-150}; WARMUP=${WARMUP:-3}; COOLDOWN=${COOLDOWN:-5}

# Chemins : tout est ramené en absolu, puis on travaille depuis docker/ (là où est docker-compose.yml)
DOCKER_DIR=$(cd "$(dirname "$0")/.." && pwd)
CFG=$(realpath "$CFG_IN")
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
cd "$DOCKER_DIR" || exit 1

NAME="hastress-$$"            # nom du conteneur de test ($$ = PID de ce script : unique par run)
TMP=$(mktemp -d)
STAMP=$(date +%Y%m%d-%H%M%S)
MNT="$CFG:/usr/local/etc/haproxy/haproxy.cfg"   # montage -v : la config testée remplace celle du conteneur
HAP_EXACT="$HAPROXY_VERSION"
LG=""
MON=""
GENS=()
MONITOR=${MONITOR:-0}; STATS_PORT=${STATS_PORT:-19999}

# Nettoyage garanti à la sortie (même sur erreur ou Ctrl-C, grâce à `trap ... EXIT`) :
# arrête générateurs, moniteur et HAProxy de test, relance les webservers.
cleanup() {
  [ -n "$LG" ] && kill $LG >/dev/null 2>&1
  [ -n "$MON" ] && kill "$MON" >/dev/null 2>&1
  [ ${#GENS[@]} -gt 0 ] && { docker stop -t 1 "${GENS[@]}" >/dev/null 2>&1; docker rm "${GENS[@]}" >/dev/null 2>&1; }
  docker stop "$NAME" >/dev/null 2>&1
  docker container rm "$NAME" >/dev/null 2>&1
  docker compose start webserver1 webserver2 >/dev/null 2>&1
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== Stress : $CFG_IN (haproxy:$HAPROXY_VERSION) · $CYCLES pannes de ${DOWN_S}s, ${UP_S}s entre deux, ~${RATE} req/s"

# 1. Syntaxe : `haproxy -c` dans un conteneur jetable (run --rm) avec la config montée
if [ "$SKIP_SYNTAX" != 1 ]; then
  if ! docker compose run --rm --no-deps -T -v "$MNT" haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >"$TMP/syntax" 2>&1; then
    echo "   syntaxe : INVALIDE"; tail -5 "$TMP/syntax" | sed 's/^/   /'
    jq -n --arg c "$CFG_IN" --arg d "$STAMP" --arg t "$HAPROXY_VERSION" \
      '{scenario:"stress",config:$c,date:$d,haproxy_tag:$t,syntax:"invalid"}' > "$OUT/run-$STAMP.json"
    exit 1
  fi
  echo "   syntaxe : ok"
fi

# 2. HAProxy de test. RUN est un tableau (la commande est choisie selon MONITOR, puis lancée plus bas)
docker compose up -d webserver1 webserver2 >/dev/null 2>&1
if [ "$MONITOR" = 1 ]; then
  # Config supplémentaire : ajoute une socket "stats" TCP au bloc global, sans toucher à la config testée
  printf 'global\n  stats socket ipv4@*:9999 level operator\n' > "$TMP/extra.cfg"
  RUN=(docker compose run -d --name "$NAME" -p "$PORT:80" -p "$STATS_PORT:9999" -v "$MNT" -v "$TMP/extra.cfg:/usr/local/etc/haproxy/extra.cfg" haproxy haproxy -f /usr/local/etc/haproxy/haproxy.cfg -f /usr/local/etc/haproxy/extra.cfg)
else
  RUN=(docker compose run -d --name "$NAME" -p "$PORT:80" -v "$MNT" haproxy)
fi
# "${RUN[@]}" : chaque élément du tableau reste un argument distinct
"${RUN[@]}" >/dev/null 2>&1 \
  || { echo "   impossible de démarrer le HAProxy de test (port $PORT occupé ?)"; exit 1; }
# Attend (10 s max) que HAProxy réponde 200 ; curl -w '%{http_code}' n'affiche que le code HTTP
for _ in $(seq 1 20); do [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "http://localhost:$PORT")" = 200 ] && break; sleep 0.5; done
# Version exacte (ex. 3.4.7) lue dans la sortie de `haproxy -v` ; sed -n 's/…/\1/p' extrait le 1er groupe
v=$(docker exec "$NAME" haproxy -v 2>/dev/null | head -1 | sed -n 's/^HA-\?Proxy version \([^ ]*\).*/\1/p'); [ -n "$v" ] && HAP_EXACT=$v

# 3. Charge continue en arrière-plan (générateurs : loadgen.py ou loadgen_async.py)
# Un générateur Python sature un cœur vers 300 req/s : un processus par tranche de 250 req/s
if [ "${LOADGEN:-threads}" = async ]; then
  LGS=loadgen_async.py; NP=$(( (RATE + 1499) / 1500 )); WORKERS=${CAP:-30000}
else
  LGS=loadgen.py; NP=$(( (RATE + 249) / 250 ))
fi
LG=""
GENS=()
# Mode conteneur : on retrouve le réseau Docker du HAProxy de test (go-template de docker inspect)
# et on lance un conteneur python par générateur, qui vise HAProxy par son nom (port 80 interne).
# Arguments du générateur : cible, port, req/s, workers, fichier de sortie, durée max (s).
if [ "${GEN:-host}" = container ]; then
  NET=$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$NAME")
  for k in $(seq 1 "$NP"); do
    docker run -d --name "$NAME-g$k" --network "$NET" -v "$DOCKER_DIR/tests/$LGS:/loadgen.py:ro" -v "$TMP:/out" \
      python:3-slim python /loadgen.py "$NAME" 80 "$(( RATE / NP ))" "$(( WORKERS / NP ))" "/out/req$k.tsv" 900 >/dev/null
    GENS+=("$NAME-g$k")
  done
  LG="0"   # valeur factice : le pilotage se fait par les conteneurs, pas par des PID
else
  for k in $(seq 1 "$NP"); do
    python3 "tests/$LGS" localhost "$PORT" "$(( RATE / NP ))" "$(( WORKERS / NP ))" "$TMP/req$k.tsv" 900 &
    LG="$LG $!"   # $! = PID du dernier processus lancé en arrière-plan (&)
  done
fi
# Moniteur : arguments = sortie, conteneur HAProxy, PID(s) du générateur (séparés par des virgules), port stats, pas (s)
if [ "$MONITOR" = 1 ]; then MON_GENS="${GENS[*]:-}" python3 tests/monitor.py sample "$TMP/mon.tsv" "$NAME" "$(echo $LG | tr ' ' ,)" "$STATS_PORT" 0.5 & MON=$!; fi
sleep "$WARMUP"

# 4. Les pannes : chaque cycle arrête webserver1 DOWN_S secondes, le redémarre, puis attend UP_S.
# cycles.txt garde "heure_arrêt heure_redémarrage" (epoch) pour calculer les métriques.
: > "$TMP/cycles.txt"
for i in $(seq 1 "$CYCLES"); do
  t_stop=$(date +%s.%N)
  docker compose stop -t 0 webserver1 >/dev/null 2>&1
  sleep "$DOWN_S"
  t_start=$(date +%s.%N)
  docker compose start webserver1 >/dev/null 2>&1
  echo "$t_stop $t_start" >> "$TMP/cycles.txt"
  sleep "$UP_S"
done
sleep "$COOLDOWN"
# 5. Arrêt de la charge (docker stop -t 20 laisse le temps d'écrire le fichier de sortie), puis regroupement des requêtes
if [ ${#GENS[@]} -gt 0 ]; then docker stop -t 20 "${GENS[@]}" >/dev/null 2>&1; docker rm "${GENS[@]}" >/dev/null 2>&1; GENS=(); LG=""
else kill -TERM $LG; wait $LG 2>/dev/null; LG=""; fi
cat "$TMP"/req[0-9]*.tsv > "$TMP/req.tsv"
[ -n "$MON" ] && { kill -TERM "$MON"; wait "$MON" 2>/dev/null; MON=""; }

# 6. Logs de HAProxy (pour dater les passages DOWN/UP) et calcul des métriques
docker logs --timestamps "$NAME" > "$TMP/hap.log" 2>&1
# Diagnostic : KEEP_RAW=<dossier> conserve les requêtes brutes et les logs de HAProxy
[ -n "${KEEP_RAW:-}" ] && { mkdir -p "$KEEP_RAW"; cp "$TMP/req.tsv" "$TMP/hap.log" "$TMP/cycles.txt" "$KEEP_RAW/"; }
METRICS=$(python3 tests/stress_metrics.py "$TMP/req.tsv" "$TMP/cycles.txt" "$TMP/hap.log") \
  || { echo "   calcul des métriques impossible"; exit 1; }

# Résumé de la supervision (JSON) ; `null` si MONITOR=0
MONJ=null
if [ "$MONITOR" = 1 ] && [ -s "$TMP/mon.tsv" ]; then
  MONJ=$(python3 tests/monitor.py summary "$TMP/mon.tsv") || MONJ=null
  cp "$TMP/mon.tsv" "$OUT/run-$STAMP.mon.tsv"
fi

# 7. Fichier résultat : jq fusionne les métriques ($m) avec les paramètres du run ; --arg = texte, --argjson = JSON
jq -n --argjson mon "$MONJ" --argjson m "$METRICS" --arg c "$CFG_IN" --arg d "$STAMP" --arg t "$HAPROXY_VERSION" --arg x "$HAP_EXACT" \
  --argjson down "$DOWN_S" --argjson up "$UP_S" --argjson rate "$RATE" --argjson workers "$WORKERS" \
  '$m + {mon:$mon,scenario:"stress",config:$c,date:$d,haproxy_tag:$t,haproxy_version:$x,syntax:"ok",
         down_s:$down,up_s_between:$up,rate_target:$rate,workers:$workers}' > "$OUT/run-$STAMP.json"

# Résumé affiché à l'écran (\(.champ) = interpolation jq)
jq -r '"   \(.requests) requêtes (\(.rps_actual)/s), \(.errors) erreur(s) = \(.error_rate_pct) %, p99 \(.p99_latency_s)s, max \(.max_latency_s)s\n   pannes détectées : \(.detected_cycles)/\(.cycles) (délai moyen \(.detection_mean_s)s), passages UP : \(.up_events), pannes avec erreurs : \(.cycles_with_errors)/\(.cycles)"' "$OUT/run-$STAMP.json"
echo "   résultat : $OUT/run-$STAMP.json"
