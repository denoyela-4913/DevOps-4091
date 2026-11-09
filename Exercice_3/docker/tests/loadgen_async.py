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
Contrôle interne (variable d'environnement LOADGEN_DIAG=1) : écrit en plus <fichier_sortie>.diag.json avec,
pour chaque requête qui n'a pas reçu HTTP 200, la classe d'erreur (exception) et la phase où elle s'est arrêtée
(connecting = connexion TCP non établie, waiting_response = requête envoyée sans réponse, reading_body = réponse
interrompue), les délais de connexion et de 1er octet ; plus les blocages du générateur lui-même (boucle
asyncio bloquée > 50 ms) et le retard d'émission des requêtes. Permet de savoir si une erreur vient du générateur,
du réseau ou du serveur. Sans cette variable, le comportement est inchangé.
Sortie : "epoch_debut<TAB>code_http<TAB>latence_s" par requête (code 0 = erreur réseau ou délai ;
code -1 = requête non envoyée car trop de requêtes en vol : le générateur est saturé).
"""
import asyncio
import json
import os
import signal
import sys
import time

# Arguments (voir l'en-tête)
host, port, rate, cap, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
max_s = float(sys.argv[6]) if len(sys.argv) > 6 else 900.0
REQ = f"GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n".encode()
records = []
inflight = 0
DIAG = os.environ.get("LOADGEN_DIAG") == "1"
diag_errors = []    # une entrée par requête sans HTTP 200 (mode DIAG)
stalls = []         # (epoch, secondes) : la boucle asyncio du générateur a été bloquée (mode DIAG)
lags = []           # retard d'émission de chaque requête par rapport à l'heure prévue (mode DIAG)
connected = 0       # requêtes dont la connexion TCP a abouti (mode DIAG)


# fetch : une requête complète sur une nouvelle connexion ; renvoie le code HTTP (octets 9 à 12 de "HTTP/1.1 200 ...")
async def fetch():
    r, w = await asyncio.open_connection(host, port)
    try:
        w.write(REQ)
        data = await r.read()
        return int(data[9:12]) if data.startswith(b"HTTP/") else 0
    finally:
        w.close()


# fetch_diag : comme fetch, mais note dans info la phase atteinte et les délais (mode DIAG)
async def fetch_diag(info):
    global connected
    t = time.time()
    info["phase"] = "connecting"
    r, w = await asyncio.open_connection(host, port)
    connected += 1
    info["t_conn"] = round(time.time() - t, 4)
    try:
        info["phase"] = "waiting_response"
        w.write(REQ)
        first = await r.read(4096)
        info["t_first"] = round(time.time() - t, 4)
        info["phase"] = "reading_body"
        data = first + await r.read()
        info["phase"] = "done"
        return int(data[9:12]) if data.startswith(b"HTTP/") else 0
    finally:
        w.close()


# one : lance fetch avec un délai total de 3 s ; code 0 en cas d'erreur ou de délai ; enregistre le résultat
async def one(s, lag=0.0):
    global inflight
    info, cls = {}, None
    try:
        code = await asyncio.wait_for(fetch_diag(info) if DIAG else fetch(), 3.0)
        if code == 0:
            cls = "no_http_response"
    except Exception as e:
        code = 0
        cls = type(e).__name__ or repr(e)   # TimeoutError = délai de 3 s dépassé
    inflight -= 1
    lat = time.time() - s
    records.append((s, code, lat))
    if DIAG and code != 200:
        diag_errors.append({"t": round(s, 3), "code": code, "class": cls or f"http_{code}", "lat_s": round(lat, 3),
                            "send_lag_s": round(lag, 4), **info})


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
            lag = now - (t0 + (sent - 1) / rate)   # retard par rapport à l'heure théorique d'envoi
            if DIAG:
                lags.append(lag)
            t = asyncio.ensure_future(one(now, lag))
            tasks.add(t)
            t.add_done_callback(tasks.discard)
        t_sleep = time.time()
        await asyncio.sleep(0.005)
        if DIAG and time.time() - t_sleep > 0.05:   # attendu : 5 ms ; plus = le générateur a été bloqué
            stalls.append((round(t_sleep, 3), round(time.time() - t_sleep, 3)))
    # Laisse 4 s aux dernières requêtes pour se terminer
    if tasks:
        await asyncio.wait(tasks, timeout=4)


# Exécution puis écriture du fichier : "epoch_début<TAB>code<TAB>latence"
asyncio.run(main())
with open(out, "w") as f:
    for s, code, lat in records:
        f.write(f"{s:.3f}\t{code}\t{lat:.4f}\n")
if DIAG:
    ls = sorted(lags)
    n = len(records)
    with open(out + ".diag.json", "w") as f:
        json.dump({"sent": sum(1 for r in records if r[1] != -1), "completed": n, "connected": connected,
                   "send_lag_max_s": round(ls[-1], 4) if ls else 0,
                   "send_lag_p99_s": round(ls[int(0.99 * len(ls))], 4) if ls else 0,
                   "stalls": stalls, "errors": diag_errors}, f)
