#!/usr/bin/env python3
"""Générateur de charge HTTP asynchrone (boucle ouverte) : ~RATE requêtes/s jusqu'à SIGTERM.

Appel :
  python3 loadgen_async.py <host> <port> <rate> <max_en_vol> <fichier_sortie> [max_secondes]
    host, port       cible HTTP
    rate             requêtes/s visées
    max_en_vol       garde-fou : nombre maximal de requêtes simultanées (test-stress.sh : CAP, défaut 30000, réparti entre processus)
    fichier_sortie   résultat (écrit à l'arrêt)
    max_secondes     durée maximale (défaut 900) ; arrêt aussi sur SIGTERM/SIGINT
Un processus tient environ 1500 req/s (tests/test-stress.sh en lance un par tranche de 1500).

Différences avec loadgen.py (threads) :
  - boucle ouverte : le débit visé est tenu même si des requêtes sont bloquées (pas de limite
    de « workers » qui ralentirait l'envoi) ; <max_en_vol> est seulement un garde-fou
  - environ 10 fois moins de CPU par requête (un seul thread, asyncio)
Chaque requête : nouvelle connexion, GET /, lecture complète, délai total de 3 s.
Sortie : "epoch_debut<TAB>code_http<TAB>latence_s" par requête (code 0 = erreur réseau ou délai ;
code -1 = requête non envoyée car trop de requêtes en vol : le générateur est saturé).
"""
import asyncio
import signal
import sys
import time

# Arguments (voir l'en-tête)
host, port, rate, cap, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
max_s = float(sys.argv[6]) if len(sys.argv) > 6 else 900.0
REQ = f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode()
records = []
inflight = 0


# fetch : une requête complète sur une nouvelle connexion ; renvoie le code HTTP (octets 9 à 12 de "HTTP/1.1 200 ...")
async def fetch():
    r, w = await asyncio.open_connection(host, port)
    try:
        w.write(REQ)
        data = await r.read()
        return int(data[9:12]) if data.startswith(b"HTTP/") else 0
    finally:
        w.close()


# one : lance fetch avec un délai total de 3 s ; code 0 en cas d'erreur ou de délai ; enregistre le résultat
async def one(s):
    global inflight
    try:
        code = await asyncio.wait_for(fetch(), 3.0)
    except Exception:
        code = 0
    inflight -= 1
    records.append((s, code, time.time() - s))


# main : boucle d'émission. À chaque tour (5 ms) on calcule combien de requêtes auraient dû partir
# depuis le début (due = temps écoulé x débit) et on envoie le retard : le débit visé est tenu en moyenne.
async def main():
    global inflight
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    # Arrêt propre sur SIGTERM/SIGINT
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    t0 = time.time()
    sent = 0
    tasks = set()
    while not stop.is_set() and time.time() - t0 < max_s:
        due = int((time.time() - t0) * rate)  # nombre de requêtes qui auraient dû partir
        while sent < due:
            sent += 1
            now = time.time()
            if inflight >= cap:   # trop de requêtes en vol : on n'envoie pas, code -1 (générateur saturé)
                records.append((now, -1, 0.0))
                continue
            inflight += 1
            t = asyncio.ensure_future(one(now))
            tasks.add(t)
            t.add_done_callback(tasks.discard)
        await asyncio.sleep(0.005)
    # Laisse 4 s aux dernières requêtes pour se terminer
    if tasks:
        await asyncio.wait(tasks, timeout=4)


# Exécution puis écriture du fichier : "epoch_début<TAB>code<TAB>latence"
asyncio.run(main())
with open(out, "w") as f:
    for s, code, lat in records:
        f.write(f"{s:.3f}\t{code}\t{lat:.4f}\n")
