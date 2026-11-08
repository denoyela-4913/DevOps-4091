#!/usr/bin/env python3
"""Générateur de charge HTTP : envoie ~RATE requêtes/s sur une URL jusqu'à SIGTERM.

Usage : loadgen.py <host> <port> <rate> <workers> <fichier_sortie> [max_secondes]

Chaque worker envoie une requête (nouvelle connexion, délai de 3 s) à intervalle régulier.
Sortie : une ligne par requête, "epoch_debut<TAB>code_http<TAB>latence_s" (code 0 = erreur
réseau ou délai dépassé). Si un worker est bloqué par un délai, il ne rattrape pas son retard.
"""
import http.client
import signal
import sys
import threading
import time

host, port, rate, workers, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
max_s = float(sys.argv[6]) if len(sys.argv) > 6 else 900.0

stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *_: stop.set())
signal.signal(signal.SIGINT, lambda *_: stop.set())

records = []
interval = workers / rate
t0 = time.time()
t_end = t0 + max_s


def worker(i):
    nxt = t0 + i * interval / workers  # départs étalés
    while not stop.is_set() and time.time() < t_end:
        now = time.time()
        if nxt > now:
            if stop.wait(nxt - now):
                break
        else:
            nxt = now  # pas de rafale de rattrapage
        s = time.time()
        try:
            c = http.client.HTTPConnection(host, port, timeout=3)
            c.request("GET", "/")
            r = c.getresponse()
            r.read()
            code = r.status
            c.close()
        except Exception:
            code = 0
        records.append((s, code, time.time() - s))
        nxt += interval


threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(workers)]
for t in threads:
    t.start()
for t in threads:
    t.join()

with open(out, "w") as f:
    for s, code, lat in records:
        f.write(f"{s:.3f}\t{code}\t{lat:.4f}\n")
