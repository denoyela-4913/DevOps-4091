#!/usr/bin/env python3
"""Calcule les métriques d'un run de stress et les affiche en JSON.

Appel (par tests/test-stress.sh) :
  python3 stress_metrics.py <requetes.tsv> <cycles.txt> <logs_haproxy.txt>
  requetes.tsv  : "epoch<TAB>code<TAB>latence" (sortie de loadgen.py)
  cycles.txt    : une ligne par panne, "epoch_arret epoch_redemarrage"
  logs_haproxy  : sortie de `docker logs --timestamps` (lignes contenant "webserver1 is DOWN/UP")
"""
import json
import re
import sys
from datetime import datetime

# 1. Lecture des requêtes (triées par heure de début)
reqs = []
for line in open(sys.argv[1]):
    s, code, lat = line.split("\t")
    reqs.append((float(s), int(code), float(lat)))
reqs.sort()
# Pannes : (heure d'arrêt, heure de redémarrage) de webserver1
cycles = [tuple(map(float, l.split())) for l in open(sys.argv[2]) if l.strip()]

# 2. Événements "webserver1 is DOWN/UP" des logs de HAProxy, convertis en epoch
events = []  # (epoch, "DOWN"|"UP")
for line in open(sys.argv[3]):
    m = re.search(r"webserver1 is (DOWN|UP)", line)
    if not m:
        continue
    ts = line.split()[0].rstrip("Z")   # horodatage Docker, ex. 2026-11-09T10:00:00.123456789Z
    if "." in ts:
        a, b = ts.split(".")
        ts = f"{a}.{b[:6]}"   # fromisoformat n'accepte que 6 décimales (microsecondes)
    events.append((datetime.fromisoformat(ts + "+00:00").timestamp(), m.group(1)))

# 3. Statistiques globales : succès = code 200 ; débit réel = requêtes / durée entre première et dernière
n = len(reqs)
ok = sum(1 for r in reqs if r[1] == 200)
lats = sorted(r[2] for r in reqs)
span = (reqs[-1][0] - reqs[0][0]) if n > 1 else 0


# pct(0.99) : latence au 99e centile (1 requête sur 100 est plus lente)
def pct(p):
    return lats[min(n - 1, int(p * n))] if n else 0


# 4. Par panne : erreurs dans la fenêtre « panne + 5 s » et délai avant le premier DOWN dans les logs
detections, errors_per_cycle = [], []
for i, (stop, start) in enumerate(cycles):
    nxt = cycles[i + 1][0] if i + 1 < len(cycles) else stop + 1e9
    end_win = min(nxt, start + 5.0 + (start - stop))  # fenêtre : panne + 5 s de retour
    errors_per_cycle.append(sum(1 for r in reqs if stop <= r[0] < end_win and r[1] != 200))
    d = [e[0] - stop for e in events if e[1] == "DOWN" and stop <= e[0] < nxt]
    if d:
        detections.append(d[0])

# Passages UP après la première panne
first_stop = cycles[0][0] if cycles else 0
ups = sum(1 for e in events if e[1] == "UP" and e[0] >= first_stop)

# 5. Résultat en JSON (une seule ligne)
print(json.dumps({
    "cycles": len(cycles),
    "requests": n,
    "ok": ok,
    "errors": n - ok,
    "error_rate_pct": round((n - ok) * 100 / n, 3) if n else 0,
    "max_latency_s": round(lats[-1], 3) if n else 0,
    "avg_latency_s": round(sum(lats) / n, 4) if n else 0,
    "p99_latency_s": round(pct(0.99), 3),
    "rps_actual": round(n / span, 1) if span else 0,
    "detected_cycles": len(detections),
    "detection_mean_s": round(sum(detections) / len(detections), 2) if detections else -1,
    "detection_max_s": round(max(detections), 2) if detections else -1,
    "up_events": ups,
    "errors_per_cycle": errors_per_cycle,
    "cycles_with_errors": sum(1 for e in errors_per_cycle if e > 0),
}))
