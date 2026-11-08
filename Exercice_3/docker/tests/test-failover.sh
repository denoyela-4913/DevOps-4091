#!/usr/bin/env bash
# Test reproductible de bascule : mesure ce que voit un utilisateur quand webserver1 tombe,
# et quand HAProxy s'en aperçoit réellement.
#
# Usage : tests/test-failover.sh <fichier_haproxy.cfg> <dossier_resultats>
# Variables facultatives :
#   HAPROXY_VERSION  tag de l'image haproxy (défaut 2.3)
#   PORT (18080) · DURATION (15 s) · RECOVERY_MAX (30 s) · SKIP_SYNTAX=1
#
# Le test démarre un HAProxy temporaire avec la config testée, sur un port à part.
# Le HAProxy principal (port 8080) n'est pas touché. En revanche webserver1 est
# arrêté puis redémarré, ce qui peut perturber brièvement la stack principale.
#
# Sortie : <dossier_resultats>/run-<date>.json

set -u
CFG_IN=${1:?usage: test-failover.sh <haproxy.cfg> <dossier_resultats>}
OUT=${2:?usage: test-failover.sh <haproxy.cfg> <dossier_resultats>}
export HAPROXY_VERSION=${HAPROXY_VERSION:-2.3}
PORT=${PORT:-18080}
DURATION=${DURATION:-15}
RECOVERY_MAX=${RECOVERY_MAX:-30}
SKIP_SYNTAX=${SKIP_SYNTAX:-0}

DOCKER_DIR=$(cd "$(dirname "$0")/.." && pwd)
CFG=$(realpath "$CFG_IN")
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
cd "$DOCKER_DIR" || exit 1

NAME="hatest-$$"
TMP=$(mktemp)
STAMP=$(date +%Y%m%d-%H%M%S)
URL="http://localhost:$PORT"
MNT="$CFG:/usr/local/etc/haproxy/haproxy.cfg"
HAP_EXACT="$HAPROXY_VERSION"

now() { date +%s.%N; }
server_name() { curl -s --max-time 3 "$URL" | grep -o 'Server&nbsp;name:</span> <span>[a-z0-9]*' | sed 's/.*<span>//'; }

# Premier message "webserver1 is <ETAT>" de HAProxy dont l'heure est >= $2 (epoch). Affiche l'écart en secondes, ou -1.
log_delay() {
  local state=$1 ref=$2 ts ep
  while read -r ts; do
    ep=$(date -d "$ts" +%s.%N 2>/dev/null) || continue
    if awk -v a="$ep" -v b="$ref" 'BEGIN{exit !(a>=b)}'; then awk -v a="$ep" -v b="$ref" 'BEGIN{printf "%.2f", a-b}'; return; fi
  done < <(docker logs --timestamps "$NAME" 2>&1 | grep "webserver1 is $state" | awk '{print $1}')
  echo -1
}

cleanup() {
  docker stop "$NAME" >/dev/null 2>&1
  docker container rm "$NAME" >/dev/null 2>&1
  docker compose start webserver1 webserver2 >/dev/null 2>&1
  rm -f "$TMP" "$TMP.req"
}
trap cleanup EXIT

write_result() { # $1=syntaxe
  jq -n \
    --arg config "$CFG_IN" --arg date "$STAMP" --arg syntax "$1" \
    --arg tag "$HAPROXY_VERSION" --arg exact "$HAP_EXACT" \
    --argjson base_servers "${BASE_SERVERS:-0}" --argjson requests "${REQUESTS:-0}" \
    --argjson ok "${OK:-0}" --argjson errors "${ERRORS:-0}" \
    --argjson last_error_s "${LAST_ERROR:-0}" --argjson max_latency_s "${MAX_LAT:-0}" \
    --argjson avg_latency_s "${AVG_LAT:-0}" --argjson recovery_s "${RECOVERY:--1}" \
    --argjson detection_s "${DETECTION:--1}" --argjson up_s "${UP:--1}" \
    --argjson duration_s "$DURATION" \
    '{config:$config,date:$date,haproxy_tag:$tag,haproxy_version:$exact,syntax:$syntax,
      base_servers:$base_servers,duration_s:$duration_s,
      requests:$requests,ok:$ok,errors:$errors,last_error_s:$last_error_s,
      max_latency_s:$max_latency_s,avg_latency_s:$avg_latency_s,
      detection_s:$detection_s,recovery_s:$recovery_s,up_s:$up_s}' \
    > "$OUT/run-$STAMP.json"
}

echo "== Test : $CFG_IN (haproxy:$HAPROXY_VERSION)"

# 1. Syntaxe
if [ "$SKIP_SYNTAX" != 1 ]; then
  if ! docker compose run --rm --no-deps -T -v "$MNT" haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg >"$TMP" 2>&1; then
    echo "   syntaxe : INVALIDE"; sed 's/^/   /' "$TMP" | tail -5
    write_result invalid; exit 1
  fi
  echo "   syntaxe : ok"
fi

# 2. HAProxy de test (serveurs démarrés au besoin)
docker compose up -d webserver1 webserver2 >/dev/null 2>&1
docker compose run -d --name "$NAME" -p "$PORT:80" -v "$MNT" haproxy >/dev/null 2>&1 \
  || { echo "   impossible de démarrer le HAProxy de test (port $PORT occupé ?)"; exit 1; }
for _ in $(seq 1 20); do [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 1 "$URL")" = 200 ] && break; sleep 0.5; done
v=$(docker exec "$NAME" haproxy -v 2>/dev/null | head -1 | sed -n 's/^HA-\?Proxy version \([^ ]*\).*/\1/p'); [ -n "$v" ] && HAP_EXACT=$v

# 3. Répartition de base : combien de serveurs distincts répondent
BASE_SERVERS=$(for _ in $(seq 1 10); do server_name; done | sort -u | grep -c .)
echo "   répartition initiale : $BASE_SERVERS serveur(s) distinct(s) sur 10 requêtes"

# 4. Panne de webserver1 pendant DURATION secondes, requêtes en continu
: > "$TMP.req"
t0=$(now)
docker compose stop -t 0 webserver1 >/dev/null 2>&1 &
while :; do
  t=$(now); el=$(awk -v a="$t" -v b="$t0" 'BEGIN{printf "%.2f", a-b}')
  awk -v e="$el" -v d="$DURATION" 'BEGIN{exit !(e>=d)}' && break
  curl -s -o /dev/null -w "$el %{http_code} %{time_total}\n" --max-time 3 "$URL" >> "$TMP.req"
  sleep 0.2
done
wait
read -r REQUESTS OK ERRORS LAST_ERROR MAX_LAT AVG_LAT < <(awk '
  { n++; if ($2==200) { ok++; s+=$3 } else { err++; last=$1 } if ($3>m) m=$3 }
  END { printf "%d %d %d %.2f %.3f %.3f\n", n, ok, err, last, m, (ok? s/ok : 0) }' "$TMP.req")
rm -f "$TMP.req"
DETECTION=$(log_delay DOWN "$t0")
echo "   panne : $OK/$REQUESTS requêtes réussies, $ERRORS erreur(s), dernière erreur à ${LAST_ERROR}s, latence max ${MAX_LAT}s"
if [ "$DETECTION" = -1 ]; then echo "   détection : serveur jamais déclaré HS pendant le test"; else echo "   détection : déclaré HS après ${DETECTION}s"; fi

# 5. Retour : temps avant que les deux serveurs répondent à nouveau
docker compose start webserver1 >/dev/null 2>&1
t1=$(now); RECOVERY=-1; seen=""
while :; do
  el=$(awk -v a="$(now)" -v b="$t1" 'BEGIN{printf "%.1f", a-b}')
  awk -v e="$el" -v m="$RECOVERY_MAX" 'BEGIN{exit !(e>=m)}' && break
  seen=$(printf '%s\n%s' "$seen" "$(server_name)" | tail -6)
  if [ "$(echo "$seen" | sort -u | grep -c .)" -ge 2 ]; then RECOVERY=$el; break; fi
  sleep 0.5
done
UP=$(log_delay UP "$t1")
if [ "$RECOVERY" = -1 ]; then echo "   retour : non revenu après ${RECOVERY_MAX}s"; else echo "   retour : deux serveurs de nouveau actifs après ${RECOVERY}s (déclaré UP après ${UP}s)"; fi

write_result ok
echo "   résultat : $OUT/run-$STAMP.json"
