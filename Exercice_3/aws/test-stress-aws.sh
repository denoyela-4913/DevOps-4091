#!/usr/bin/env bash
# Test de stress sur AWS : pannes consécutives de webserver1 sous charge continue.
# Même scénario et mêmes métriques que docker/tests/test-stress.sh (réutilise loadgen_async.py et
# stress_metrics.py de docker/tests), mais :
#   - HAProxy et les webservers sont les VM EC2 déployées par Terraform (cette config : haproxy.cfg.tpl) ;
#   - la charge part de CETTE machine vers l'IP publique de HAProxy (latence Internet incluse) ;
#   - la panne = `docker stop` du conteneur nginx de webserver1, par SSH ;
#   - les horaires DOWN/UP viennent de /var/log/haproxy.log, recalés sur l'horloge locale
#     (décalage mesuré par SSH) ; stats HAProxy (smax, qmax, 5xx) lues sur la socket admin.
#
# Appel (depuis Exercice_3/aws/, après `terraform apply`) :
#   [VARIABLES=valeur ...] ./test-stress-aws.sh <dossier_resultats>
# Variables (défaut) : RATE (100) · CYCLES (3) · DOWN_S (3) · UP_S (8) · WARMUP (3) · COOLDOWN (5) · CFG (aws) · CAP (3000)
#   DIAG (1)     contrôle interne : classe les erreurs du générateur (phase, exception), mesure ses blocages, compare
#                avec les compteurs/logs de HAProxy -> champ "diag" du JSON (voir diag-report.py)
#   CONTROL (1)  avec DIAG : lance aussi un générateur témoin SUR la VM HAProxy (127.0.0.1, même débit CONTROL_RATE=RATE).
#                Attention : la charge sur HAProxy double -> à utiliser avec CFG=<autre nom> (résultats non comparables)
set -u
OUT=${1:?usage: test-stress-aws.sh <dossier_resultats>}
RATE=${RATE:-100}; CYCLES=${CYCLES:-3}; DOWN_S=${DOWN_S:-3}; UP_S=${UP_S:-8}
WARMUP=${WARMUP:-3}; COOLDOWN=${COOLDOWN:-5}; CFG=${CFG:-aws}; CAP=${CAP:-3000}
DIAG=${DIAG:-1}; CONTROL=${CONTROL:-1}; CONTROL_RATE=${CONTROL_RATE:-$RATE}
AWS_DIR=$(cd "$(dirname "$0")" && pwd); T="$AWS_DIR/../docker/tests"
mkdir -p "$OUT"; OUT=$(realpath "$OUT"); cd "$AWS_DIR" || exit 1
TMP=$(mktemp -d); STAMP=$(date +%Y%m%d-%H%M%S); LG=""

HAP=$(terraform output -raw haproxy_public_ip) || exit 1
W1=$(terraform output -json webserver_public_ips | jq -r '.[0]')
KEY=~/.ssh/aws_openclassrooms_edo_p5.pem
SSHO=(-i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
      -o ControlMaster=auto -o ControlPath="$TMP/cm-%h" -o ControlPersist=120)
sh_hap() { ssh "${SSHO[@]}" "ubuntu@$HAP" "$@"; }
sh_w1()  { ssh "${SSHO[@]}" "ubuntu@$W1" "$@"; }
admin()  { sh_hap "echo '$1' | sudo socat stdio /run/haproxy/admin.sock"; }
cleanup() { [ -n "$LG" ] && kill "$LG" 2>/dev/null; [ "$CONTROL" = 1 ] && sh_hap 'pkill -f loadgen_async.py' >/dev/null 2>&1; sh_w1 'sudo docker start $(sudo docker ps -aq)' >/dev/null 2>&1
            ssh -O exit -o ControlPath="$TMP/cm-$HAP" "ubuntu@$HAP" >/dev/null 2>&1; rm -rf "$TMP"; }
trap cleanup EXIT

echo "== Stress AWS ($CFG) : $CYCLES pannes de ${DOWN_S}s, ${UP_S}s entre deux, ~$RATE req/s vers $HAP"
sh_hap 'command -v socat >/dev/null || sudo apt-get install -y socat >/dev/null 2>&1; sudo haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1' \
  || { echo "   syntaxe/accès SSH : échec"; exit 1; }
sh_w1 'sudo docker start $(sudo docker ps -aq)' >/dev/null 2>&1
for _ in $(seq 1 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://$HAP")" = 200 ] && break; sleep 1; done
HAP_V=$(sh_hap "haproxy -v | head -1 | sed -n 's/^HA-\?Proxy version \([^ ]*\).*/\1/p'")
# Décalage horloge AWS - locale (milieu de l'aller-retour SSH) pour recaler les logs
t_a=$(date +%s.%N); r=$(sh_hap 'date +%s.%N'); t_b=$(date +%s.%N)
OFFSET=$(awk -v a="$t_a" -v b="$t_b" -v r="$r" 'BEGIN{printf "%.3f", r-(a+b)/2}')
admin 'clear counters all' >/dev/null
echo "   HAProxy $HAP_V · décalage d'horloge AWS-local : ${OFFSET}s"

RUN_START=$(sh_hap 'date -u +%Y-%m-%dT%H:%M:%S')   # heure AWS : filtre des logs HAProxy de ce run
if [ "$DIAG" = 1 ] && [ "$CONTROL" = 1 ]; then   # générateur témoin sur la VM HAProxy, vers 127.0.0.1
  scp "${SSHO[@]}" -q "$T/loadgen_async.py" "ubuntu@$HAP:/tmp/loadgen_async.py"
  sh_hap 'rm -f /tmp/ctl.tsv /tmp/ctl.tsv.diag.json; nohup env LOADGEN_DIAG=1 python3 /tmp/loadgen_async.py 127.0.0.1 80 '"$CONTROL_RATE $CAP"' /tmp/ctl.tsv 900 </dev/null >/tmp/ctl.log 2>&1 &'
fi
LOADGEN_DIAG=$DIAG python3 "$T/loadgen_async.py" "$HAP" 80 "$RATE" "$CAP" "$TMP/req.tsv" 900 & LG=$!
sleep "$WARMUP"
: > "$TMP/cycles.txt"
for i in $(seq 1 "$CYCLES"); do
  t_stop=$(date +%s.%N); sh_w1 'sudo docker stop -t 0 $(sudo docker ps -q)' >/dev/null 2>&1
  sleep "$DOWN_S"
  t_start=$(date +%s.%N); sh_w1 'sudo docker start $(sudo docker ps -aq)' >/dev/null 2>&1
  echo "$t_stop $t_start" >> "$TMP/cycles.txt"
  sleep "$UP_S"
done
sleep "$COOLDOWN"
kill -TERM "$LG"; wait "$LG" 2>/dev/null; LG=""
if [ "$DIAG" = 1 ] && [ "$CONTROL" = 1 ]; then
  sh_hap 'pkill -TERM -f loadgen_async.py; for i in $(seq 1 15); do [ -s /tmp/ctl.tsv.diag.json ] && break; sleep 1; done; true'
  sh_hap 'cat /tmp/ctl.tsv' | awk -F'\t' -v o="$OFFSET" 'BEGIN{OFS="\t"} {$1=sprintf("%.3f",$1-o); print}' > "$TMP/ctl.tsv"
  sh_hap 'cat /tmp/ctl.tsv.diag.json' > "$TMP/ctl.diag.json"
fi

# Logs HAProxy -> "<ISO UTC recalé sur l'horloge locale>Z <ligne>" (format attendu par stress_metrics.py)
# (HAProxy écrit chaque événement 3 fois : stderr "[WARNING]", local0, local1 -> on garde une ligne ; "is UP." = fin de slowstart, ignoré)
sh_hap "sudo grep -E 'webserver1 is (DOWN|UP),' /var/log/haproxy.log | grep -v WARNING | awk '{k=\$0; sub(/^[^ ]+ /,\"\",k); if (k!=p) print; p=k}'" | python3 -W ignore -c '
import sys, re
from datetime import datetime
off = float(sys.argv[1])
for l in sys.stdin:
    ts = l.split()[0]
    e = datetime.fromisoformat(ts).timestamp() - off
    print(datetime.utcfromtimestamp(e).strftime("%Y-%m-%dT%H:%M:%S.%f") + "Z " + l.strip())
' "$OFFSET" > "$TMP/hap.log"
# Stats HAProxy : saturation (smax = sessions max, qmax = file max) et 5xx vus par HAProxy
STATS=$(admin 'show stat' | python3 -c '
import sys, csv, json
rows = list(csv.reader(sys.stdin)); h = [c.lstrip("# ") for c in rows[0]]
d = {(r[0], r[1]): dict(zip(h, r)) for r in rows[1:] if len(r) == len(h)}
g = lambda k, f: int(d[k][f] or 0)
print(json.dumps({"frontend_smax": g(("http_in","FRONTEND"),"smax"), "backend_smax": g(("webservers","BACKEND"),"smax"),
  "backend_qmax": g(("webservers","BACKEND"),"qmax"), "backend_5xx": g(("webservers","BACKEND"),"hrsp_5xx"),
  "backend_econ": g(("webservers","BACKEND"),"econ"), "backend_eresp": g(("webservers","BACKEND"),"eresp"),
  "backend_wredis": g(("webservers","BACKEND"),"wredis"), "backend_wretr": g(("webservers","BACKEND"),"wretr"),
  "frontend_stot": g(("http_in","FRONTEND"),"stot"), "frontend_req_tot": g(("http_in","FRONTEND"),"req_tot"),
  "frontend_ereq": g(("http_in","FRONTEND"),"ereq"), "backend_cli_abrt": g(("webservers","BACKEND"),"cli_abrt"),
  "backend_srv_abrt": g(("webservers","BACKEND"),"srv_abrt")}))')
METRICS=$(python3 "$T/stress_metrics.py" "$TMP/req.tsv" "$TMP/cycles.txt" "$TMP/hap.log") || { echo "   métriques impossibles"; exit 1; }
# Contrôle interne : métriques du témoin + rapport de diagnostic (erreurs : phase, blocages, compteurs et logs HAProxy)
CTLJ=null; DIAGJ=null
if [ "$DIAG" = 1 ]; then
  [ -s "$TMP/ctl.tsv" ] && CTLJ=$(python3 "$T/stress_metrics.py" "$TMP/ctl.tsv" "$TMP/cycles.txt" "$TMP/hap.log" | jq -c --argjson r "$CONTROL_RATE" '{rate_target:$r,requests,errors,error_rate_pct,p99_latency_s,max_latency_s,errors_per_cycle}')
  sh_hap "sudo awk -v s='$RUN_START' '\$1 >= s' /var/log/haproxy.log | grep -E ' http_in ' | grep -v WARNING | awk '{k=\$0; sub(/^[^ ]+ /,\"\",k); if (k!=p) print; p=k}'" > "$TMP/httplog.txt"
  echo "${STATS:-null}" > "$TMP/stats.json"
  [ -s "$TMP/ctl.diag.json" ] && CTLD="$TMP/ctl.diag.json" || CTLD=-
  REPORT=$(python3 -W ignore "$AWS_DIR/diag-report.py" "$TMP/cycles.txt" "$TMP/req.tsv.diag.json" "$CTLD" "$TMP/stats.json" "$TMP/httplog.txt" "$OFFSET")
  DIAGJ=$(echo "$REPORT" | tail -1); echo "$REPORT" | sed '$d' > "$TMP/diag.txt"
fi
jq -n --argjson ctl "$CTLJ" --argjson diag "$DIAGJ" --argjson st "${STATS:-null}" --argjson m "$METRICS" --arg c "$CFG" --arg d "$STAMP" --arg x "$HAP_V" --argjson off "$OFFSET" \
  --argjson down "$DOWN_S" --argjson up "$UP_S" --argjson rate "$RATE" --argjson cap "$CAP" \
  '$m + {mon:$st,control:$ctl,diag:$diag,scenario:"stress",target:"aws",config:$c,date:$d,haproxy_tag:"aws",haproxy_version:$x,syntax:"ok",
         down_s:$down,up_s_between:$up,rate_target:$rate,workers:$cap,clock_offset_s:$off}' > "$OUT/run-$STAMP.json"
jq -r '"   \(.requests) requêtes (\(.rps_actual)/s), \(.errors) erreur(s) = \(.error_rate_pct) %, p99 \(.p99_latency_s)s, max \(.max_latency_s)s\n   pannes détectées : \(.detected_cycles)/\(.cycles) (délai moyen \(.detection_mean_s)s), passages UP : \(.up_events), pannes avec erreurs : \(.cycles_with_errors)/\(.cycles)\n   HAProxy : \(.mon|tostring)"' "$OUT/run-$STAMP.json"
[ -s "$TMP/diag.txt" ] && cat "$TMP/diag.txt"
