#!/usr/bin/env bash
# Petit run pour alimenter Kibana : charge modérée sur la stack principale (port 8080) avec une panne de webserver1.
#
# Ce que fait le script : envoie ~RATE requêtes/s à http://localhost:8080 pendant DURATION secondes ;
# arrête webserver1 à DOWN_AT s et le redémarre à UP_AT s. Les logs de HAProxy et des webservers partent vers
# Elasticsearch si la stack tourne avec docker-compose.elk.yml (index exo3-logs-AAAA.MM.JJ).
#
# Appel (depuis Exercice_3/docker/) :
#   tests/elk-demo.sh
#   RATE=50 DURATION=60 tests/elk-demo.sh
# Variables (défaut) : RATE (20) req/s · DURATION (40) s · DOWN_AT (10) s · UP_AT (25) s · WORKERS (20)
#
# Sortie : l'heure de début et de fin (UTC, à utiliser dans Kibana) et le résumé du générateur.

set -u
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1
RATE=${RATE:-20}; DURATION=${DURATION:-40}; DOWN_AT=${DOWN_AT:-10}; UP_AT=${UP_AT:-25}; WORKERS=${WORKERS:-20}
OUT=$(mktemp)
# Le serveur doit être relancé même en cas d'interruption
trap 'docker compose start webserver1 >/dev/null 2>&1; rm -f "$OUT"' EXIT

echo "Début  (UTC) : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
python3 tests/loadgen.py localhost 8080 "$RATE" "$WORKERS" "$OUT" "$DURATION" &
LG=$!
sleep "$DOWN_AT"; echo "webserver1 arrêté à $(date -u +%H:%M:%S)"; docker compose stop -t 0 webserver1 >/dev/null 2>&1
sleep $((UP_AT - DOWN_AT)); echo "webserver1 relancé à $(date -u +%H:%M:%S)"; docker compose start webserver1 >/dev/null 2>&1
wait "$LG"
echo "Fin    (UTC) : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Résumé : requêtes par code HTTP (code 0 = erreur réseau ou délai)
awk -F'\t' '{n[$2]++} END {for (c in n) printf "  code %s : %d requêtes\n", c, n[c]}' "$OUT" | sort
