#!/usr/bin/env python3
"""Surveille ce qui peut saturer pendant un test de stress.

Appel (par tests/test-stress.sh quand MONITOR=1) :
  python3 monitor.py sample <sortie.tsv> <conteneur_haproxy> <pid_loadgen> <port_stats> [pas_s]
      échantillonne jusqu'à SIGTERM (une ligne par échantillon, colonnes nommées dans COLS)
        sortie.tsv         fichier écrit
        conteneur_haproxy  nom du conteneur HAProxy de test
        pid_loadgen        PID du générateur (plusieurs : séparés par des virgules ; sans effet en mode conteneur)
        port_stats         port hôte publié de la socket stats de HAProxy (STATS_PORT, défaut 19999)
        pas_s              secondes entre deux échantillons (défaut 0.5)
      Variable d'environnement MON_GENS : noms des conteneurs générateurs (pour la colonne d_gen_cpu).
  python3 monitor.py summary <sortie.tsv>
      affiche en JSON les maxima/minima significatifs (champ "mon" des résultats)

Sources :
  - HAProxy (socket "stats" publiée sur <port_stats>) : show info + show stat
      CurrConns, ConnRate, Idle_pct, Run_queue ; file (qcur), sessions (scur), refus (econ, 5xx) par serveur
  - /proc/net/tcp DANS le conteneur HAProxy : backlog d'accept (Recv-Q de l'écoute :80),
      connexions SYN_SENT (en attente d'un serveur mort), ESTABLISHED, TIME_WAIT
  - hôte : CPU global, mémoire disponible, sockets TCP (inuse, TIME_WAIT), CPU et threads/fd du générateur
  - /proc/net/tcp DANS chaque webserver (toutes les ~2 s) : backlog d'accept (:80), ESTABLISHED, TIME_WAIT
  - docker stats (toutes les ~2 s) : CPU et mémoire des conteneurs HAProxy et webservers
"""
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time

# Colonnes du fichier TSV, dans l'ordre. Préfixes : (rien)=HAProxy stats ; fe/be/s1/s2=frontend/backend/serveurs ;
# c_=conteneur HAProxy (/proc/net/tcp) ; h_=hôte ; lg_=générateur ; d_=docker stats ; w1_/w2_=webservers
COLS = [
    "t", "cur_conns", "conn_rate", "idle_pct", "run_queue", "maxconn",
    "fe_scur", "be_qcur", "be_scur", "be_econ", "be_5xx", "be_ereq_fe",
    "s1_scur", "s1_qcur", "s1_status", "s2_scur", "s2_qcur", "s2_status",
    "c_listen_rq", "c_syn_sent", "c_estab", "c_timewait",
    "h_cpu_pct", "h_mem_avail_mb", "h_tcp_inuse", "h_tcp_tw",
    "lg_cpu_pct", "lg_threads", "lg_fds",
    "d_hap_cpu", "d_hap_mem_mb", "d_ws1_cpu", "d_ws2_cpu", "d_gen_cpu",
    "w1_listen_rq", "w1_estab", "w1_timewait", "w2_listen_rq", "w2_estab", "w2_timewait",
]


# query : envoie une commande à la socket stats de HAProxy ("show info", "show stat") et renvoie la réponse
def query(port, cmd):
    s = socket.create_connection(("127.0.0.1", port), timeout=1.5)
    s.sendall((cmd + "\n").encode())
    buf = b""
    while True:
        d = s.recv(65536)
        if not d:
            break
        buf += d
    s.close()
    return buf.decode(errors="replace")


# parse_info : "Clé: valeur" par ligne -> dictionnaire
def parse_info(txt):
    return dict(l.split(": ", 1) for l in txt.splitlines() if ": " in l)


# parse_stat : CSV de "show stat" -> {(proxy, serveur): {colonne: valeur}} ; ex. ("webservers", "webserver1")
def parse_stat(txt):
    lines = [l for l in txt.splitlines() if l.strip()]
    hdr = lines[0].lstrip("# ").rstrip(",").split(",")
    rows = {}
    for l in lines[1:]:
        f = l.split(",")
        r = dict(zip(hdr, f))
        rows[(r["pxname"], r["svname"])] = r
    return rows


# num : valeur numérique d'une colonne (0 si vide ou absente)
def num(r, k):
    try:
        return float(r.get(k, "") or 0)
    except ValueError:
        return 0.0


def container_tcp(name):
    """Compte les sockets du conteneur par état + file d'accept de l'écoute :80."""
    try:
        out = subprocess.run(["docker", "exec", name, "cat", "/proc/net/tcp"], capture_output=True, text=True, timeout=2).stdout
    except Exception:
        return 0, 0, 0, 0
    # /proc/net/tcp : colonne 3 = état en hexadécimal (0A écoute, 02 SYN_SENT, 01 ESTABLISHED, 06 TIME_WAIT),
    # colonne 4 = "Tx-Queue:Rx-Queue". Pour une socket en écoute, Rx-Queue = backlog d'accept (connexions non acceptées).
    # Le port 80 s'écrit 0050 en hexadécimal.
    lrq = syn = est = tw = 0
    for l in out.splitlines()[1:]:
        f = l.split()
        if len(f) < 5:
            continue
        st, rq = f[3], f[4].split(":")[1]
        if st == "0A" and f[1].endswith(":0050"):
            lrq = max(lrq, int(rq, 16))
        elif st == "02":
            syn += 1
        elif st == "01":
            est += 1
        elif st == "06":
            tw += 1
    return lrq, syn, est, tw


# HostCpu : % de CPU de toute la machine entre deux appels de pct() (/proc/stat : total moins temps inactif)
class HostCpu:
    def __init__(self):
        self.prev = self.read()

    @staticmethod
    def read():
        f = open("/proc/stat").readline().split()[1:]
        v = list(map(int, f))
        return sum(v), v[3] + v[4]

    def pct(self):
        tot, idle = self.read()
        dt, di = tot - self.prev[0], idle - self.prev[1]
        self.prev = (tot, idle)
        return round(100 * (dt - di) / dt, 1) if dt else 0.0


# ProcCpu : % de CPU d'un ou plusieurs processus (utime+stime dans /proc/<pid>/stat ; 100 % = un cœur)
class ProcCpu:
    def __init__(self, pids):
        self.pids, self.t = str(pids).split(","), time.time()
        self.prev = self.read()

    def read(self):
        tot = 0
        for pid in self.pids:
            try:
                # rsplit(")") : le nom du processus (entre parenthèses) peut contenir des espaces
                f = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
                tot += int(f[11]) + int(f[12])
            except Exception:
                pass
        return tot

    def pct(self):
        now, cur = time.time(), self.read()
        r = 100 * (cur - self.prev) / os.sysconf("SC_CLK_TCK") / max(now - self.t, 1e-3)
        self.prev, self.t = cur, now
        return round(r, 1)


# proc_threads_fds : nombre de threads et de descripteurs de fichiers ouverts des processus
def proc_threads_fds(pids):
    th = fds = 0
    for pid in str(pids).split(","):
        try:
            th += len(os.listdir(f"/proc/{pid}/task"))
            fds += len(os.listdir(f"/proc/{pid}/fd"))
        except Exception:
            pass
    return th, fds


# mem_avail_mb : mémoire disponible de la machine, en Mo
def mem_avail_mb():
    for l in open("/proc/meminfo"):
        if l.startswith("MemAvailable"):
            return int(l.split()[1]) // 1024
    return 0


# sockstat : (sockets TCP en usage, sockets TIME_WAIT) de la machine, d'après /proc/net/sockstat
def sockstat():
    for l in open("/proc/net/sockstat"):
        if l.startswith("TCP:"):
            f = l.split()
            d = dict(zip(f[1::2], f[2::2]))
            return int(d.get("inuse", 0)), int(d.get("tw", 0))
    return 0, 0


# Valeurs mises à jour en tâche de fond (toutes les ~2 s) par docker_loop et web_tcp_loop, relues à chaque échantillon
dock = {"d_gen_cpu": 0.0, "d_hap_cpu": 0.0, "d_hap_mem_mb": 0.0, "d_ws1_cpu": 0.0, "d_ws2_cpu": 0.0,
        "w1_listen_rq": 0, "w1_estab": 0, "w1_timewait": 0, "w2_listen_rq": 0, "w2_estab": 0, "w2_timewait": 0}
WEBSERVERS = (("w1", "docker-webserver1-1"), ("w2", "docker-webserver2-1"))


def web_tcp_loop(stop):
    """Files réseau des webservers (échantillonnées toutes les ~2 s, en tâche de fond)."""
    while not stop.is_set():
        for k, name in WEBSERVERS:
            lrq, _syn, est, tw = container_tcp(name)
            dock[k + "_listen_rq"], dock[k + "_estab"], dock[k + "_timewait"] = lrq, est, tw
        stop.wait(2)


# docker_loop : CPU/mémoire des conteneurs via `docker stats` (lent : ~1-2 s par appel, d'où la tâche de fond)
def docker_loop(hap, stop):
    while not stop.is_set():
        try:
            out = subprocess.run(
                ["docker", "stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}} {{.MemUsage}}",
                 hap, "docker-webserver1-1", "docker-webserver2-1"] + os.environ.get("MON_GENS", "").split(),
                capture_output=True, text=True, timeout=8).stdout
            gen = 0.0
            for l in out.splitlines():
                f = l.split()
                cpu = float(f[1].rstrip("%"))
                if f[0].split("-")[-1].startswith("g"):  # conteneurs générateurs (hastress-<pid>-gN)
                    gen += cpu
                    dock["d_gen_cpu"] = round(gen, 1)
                    continue
                if f[0] == hap:
                    m = f[2]
                    dock["d_hap_cpu"] = cpu
                    dock["d_hap_mem_mb"] = float(m.rstrip("MiBGk")) if m.endswith("MiB") else 0.0
                elif f[0].endswith("webserver1-1"):
                    dock["d_ws1_cpu"] = cpu
                elif f[0].endswith("webserver2-1"):
                    dock["d_ws2_cpu"] = cpu
        except Exception:
            pass


# sample : boucle d'échantillonnage. Chaque tour : stats HAProxy, files réseau du conteneur, hôte, générateur ;
# une ligne TSV est écrite puis le tour est complété pour durer "step" secondes.
def sample(out, hap, lg_pid, port, step):
    stop = threading.Event()
    # SIGTERM/SIGINT déclenchent l'arrêt propre (le fichier est fermé)
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    threading.Thread(target=docker_loop, args=(hap, stop), daemon=True).start()
    threading.Thread(target=web_tcp_loop, args=(stop,), daemon=True).start()
    hc, lc = HostCpu(), ProcCpu(lg_pid)
    f = open(out, "w")
    f.write("\t".join(COLS) + "\n")
    while not stop.is_set():
        t0 = time.time()
        row = dict.fromkeys(COLS, 0)   # toutes les colonnes à 0 par défaut (si une source échoue)
        row["t"] = round(t0, 3)
        try:
            info = parse_info(query(port, "show info"))
            st = parse_stat(query(port, "show stat"))
            row.update(cur_conns=info.get("CurrConns", 0), conn_rate=info.get("ConnRate", 0),
                       idle_pct=info.get("Idle_pct", 0), run_queue=info.get("Run_queue", 0),
                       maxconn=info.get("Maxconn", 0))
            fe, be = st.get(("http_in", "FRONTEND"), {}), st.get(("webservers", "BACKEND"), {})
            s1, s2 = st.get(("webservers", "webserver1"), {}), st.get(("webservers", "webserver2"), {})
            row.update(fe_scur=num(fe, "scur"), be_qcur=num(be, "qcur"), be_scur=num(be, "scur"),
                       be_econ=num(be, "econ"), be_5xx=num(be, "hrsp_5xx"), be_ereq_fe=num(fe, "ereq"),
                       s1_scur=num(s1, "scur"), s1_qcur=num(s1, "qcur"), s1_status=s1.get("status", "?"),
                       s2_scur=num(s2, "scur"), s2_qcur=num(s2, "qcur"), s2_status=s2.get("status", "?"))
        except Exception:
            pass
        lrq, syn, est, tw = container_tcp(hap)
        th, fds = proc_threads_fds(lg_pid)
        inuse, hw = sockstat()
        row.update(c_listen_rq=lrq, c_syn_sent=syn, c_estab=est, c_timewait=tw,
                   h_cpu_pct=hc.pct(), h_mem_avail_mb=mem_avail_mb(), h_tcp_inuse=inuse, h_tcp_tw=hw,
                   lg_cpu_pct=lc.pct(), lg_threads=th, lg_fds=fds, **dock)
        f.write("\t".join(str(row[c]) for c in COLS) + "\n")
        f.flush()
        stop.wait(max(0.0, step - (time.time() - t0)))
    f.close()


# summary : lit le TSV et affiche en JSON les maximum (ou minimum) de chaque indicateur sur la durée du run
def summary(path):
    rows = [l.rstrip("\n").split("\t") for l in open(path)]
    hdr, data = rows[0], rows[1:]
    ix = {c: i for i, c in enumerate(hdr)}
    if not data:
        print(json.dumps({"samples": 0}))
        return

    def col(c):
        out = []
        for r in data:
            try:
                out.append(float(r[ix[c]]))
            except (ValueError, IndexError):
                pass
        return out

    def mx(c):
        v = col(c)
        return max(v) if v else 0

    # idle_pct : 0 = pas de mesure, on l'ignore pour le minimum
    mem = col("h_mem_avail_mb")
    idle = [x for x in col("idle_pct") if x > 0] or [0]
    print(json.dumps({
        "samples": len(data),
        "max_cur_conns": mx("cur_conns"), "maxconn": mx("maxconn"),
        "max_conn_rate": mx("conn_rate"), "min_idle_pct": min(idle), "max_run_queue": mx("run_queue"),
        "max_fe_scur": mx("fe_scur"), "max_be_qcur": mx("be_qcur"), "max_be_scur": mx("be_scur"),
        "max_s1_scur": mx("s1_scur"), "max_s2_scur": mx("s2_scur"),
        "max_s1_qcur": mx("s1_qcur"), "max_s2_qcur": mx("s2_qcur"),
        "be_econ_total": mx("be_econ"), "be_5xx_total": mx("be_5xx"),
        "max_listen_rq": mx("c_listen_rq"), "max_syn_sent": mx("c_syn_sent"),
        "max_estab": mx("c_estab"), "max_timewait_ctn": mx("c_timewait"),
        "max_host_cpu_pct": mx("h_cpu_pct"), "min_mem_avail_mb": min(mem) if mem else 0,
        "max_host_tcp_inuse": mx("h_tcp_inuse"), "max_host_tcp_tw": mx("h_tcp_tw"),
        "max_loadgen_cpu_pct": mx("lg_cpu_pct"), "max_loadgen_threads": mx("lg_threads"), "max_loadgen_fds": mx("lg_fds"),
        "max_haproxy_cpu_pct": mx("d_hap_cpu"), "max_gen_cpu_pct": mx("d_gen_cpu"), "max_ws1_cpu_pct": mx("d_ws1_cpu"), "max_ws2_cpu_pct": mx("d_ws2_cpu"),
        "max_ws1_listen_rq": mx("w1_listen_rq"), "max_ws2_listen_rq": mx("w2_listen_rq"),
        "max_ws1_estab": mx("w1_estab"), "max_ws2_estab": mx("w2_estab"),
        "max_ws1_timewait": mx("w1_timewait"), "max_ws2_timewait": mx("w2_timewait"),
    }))


# Point d'entrée : mode sample (pas facultatif, défaut 0.5 s) ou summary
if __name__ == "__main__":
    if sys.argv[1] == "sample":
        sample(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), float(sys.argv[6]) if len(sys.argv) > 6 else 0.5)
    else:
        summary(sys.argv[2])
