#!/usr/bin/env python3
"""Générateur de charge HTTP : envoie ~RATE requêtes/s sur une URL jusqu'à SIGTERM.

Appel :
  python3 loadgen.py <host> <port> <rate> <workers> <fichier_sortie> [max_secondes]
    host, port       cible HTTP
    rate             requêtes/s visées au total
    workers          nombre de threads (chacun envoie une requête toutes les workers/rate secondes)
    fichier_sortie   résultat (écrit à l'arrêt)
    max_secondes     durée maximale (défaut 900) ; le programme s'arrête aussi sur SIGTERM/SIGINT
Un thread Python sature un cœur vers 300 req/s : lancer un processus par tranche de 250 req/s
(c'est ce que fait tests/test-stress.sh). Boucle fermée : un worker bloqué n'envoie rien pendant ce temps.

Chaque worker envoie une requête (nouvelle connexion, délai de 3 s) à intervalle régulier.
Sortie : une ligne par requête, "epoch_debut<TAB>code_http<TAB>latence_s" (code 0 = erreur
réseau ou délai dépassé). Si un worker est bloqué par un délai, il ne rattrape pas son retard.
"""
import http.client
import signal
import sys
import threading
import time

# Arguments (voir l'en-tête)
host, port, rate, workers, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
max_s = float(sys.argv[6]) if len(sys.argv) > 6 else 900.0

# SIGTERM/SIGINT ne tuent pas le programme : ils déclenchent l'arrêt propre et l'écriture du fichier
stop = threading.Event()
signal.signal(signal.SIGTERM, lambda *_: stop.set())
signal.signal(signal.SIGINT, lambda *_: stop.set())

# interval = délai entre deux requêtes d'un même worker ; records = (début, code, latence)
records = []
interval = workers / rate
t0 = time.time()
t_end = t0 + max_s


# Un worker : envoie une requête toutes les "interval" secondes (nouvelle connexion à chaque fois)
def worker(i):
    nxt = t0 + i * interval / workers  # départs étalés : les workers ne partent pas tous en même temps
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


# Démarrage de tous les workers puis attente de leur arrêt
threads = [threading.Thread(target=worker, args=(i,), daemon=True) for i in range(workers)]
for t in threads:
    t.start()
for t in threads:
    t.join()

# Écriture : "epoch_début<TAB>code<TAB>latence" ; code 0 = erreur réseau ou délai de 3 s dépassé
with open(out, "w") as f:
    for s, code, lat in records:
        f.write(f"{s:.3f}\t{code}\t{lat:.4f}\n")
