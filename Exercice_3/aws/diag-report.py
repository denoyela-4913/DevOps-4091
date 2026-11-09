#!/usr/bin/env python3
"""Diagnostic des erreurs d'un run AWS : d'où viennent-elles ?  (appelé par test-stress-aws.sh)

Appel : diag-report.py <cycles.txt> <diag_principal.json> <diag_temoin.json|-> <stats_haproxy.json> <logs_anormaux.txt> <decalage_s>
Affiche un résumé lisible et écrit le détail en JSON sur la sortie standard (dernière ligne).

Sources croisées :
  - générateur principal (ce poste -> Internet -> HAProxy) : classe + phase de chaque erreur, blocages du générateur ;
  - générateur témoin (127.0.0.1 sur la VM HAProxy, même débit) : si le témoin n'a pas d'erreur alors que le principal en a,
    la cause est entre ce poste et HAProxy (Internet, WSL2, générateur) ; si le témoin en a aussi, elle est dans HAProxy/serveurs ;
  - compteurs HAProxy (sessions acceptées, abandons client/serveur) et logs HTTP anormaux (statut != 200 ou drapeaux != ----).
"""
import json, re, sys
from collections import Counter

cycles = [tuple(map(float, l.split())) for l in open(sys.argv[1]) if l.strip()]
main = json.load(open(sys.argv[2]))
ctl = json.load(open(sys.argv[3])) if sys.argv[3] != "-" else None
st = json.load(open(sys.argv[4]))
off = float(sys.argv[6])


def where(t):
    """Position d'une erreur par rapport aux pannes : (n° de panne, secondes depuis l'arrêt) ou None hors panne."""
    for i, (stop, start) in enumerate(cycles):
        nxt = cycles[i + 1][0] if i + 1 < len(cycles) else stop + 1e9
        if stop - 4 <= t_ref(t) < nxt:   # -4 s : une requête en erreur à 3 s a commencé avant l'arrêt
            return i + 1, round(t_ref(t) - stop, 2)
    return None


def t_ref(t):
    return t


def summarize(d, shift=0.0):
    errs = d["errors"]
    for e in errs:
        e["t"] = round(e["t"] - shift, 3)
        e["panne"] = where(e["t"])
    kinds = Counter(f'{e["class"]}/{e.get("phase", "?")}' for e in errs)
    return {"sent": d["sent"], "connected": d["connected"], "errors": len(errs), "kinds": dict(kinds),
            "stalls": len(d["stalls"]), "stall_max_s": max([s[1] for s in d["stalls"]], default=0),
            "send_lag_max_s": d["send_lag_max_s"], "send_lag_p99_s": d["send_lag_p99_s"], "detail": errs}


m = summarize(main)
c = summarize(ctl, off) if ctl else None

# Logs HAProxy anormaux : statut et drapeaux de terminaison (httplog : "... <statut> <octets> - - <flags> ...")
abn = Counter()
for l in open(sys.argv[5]):
    r = re.search(r" (-?\d+) \d+ \S+ \S+ (\S{4}) ", l)
    if r and (r.group(1) != "200" or r.group(2) != "----"):
        abn[f"statut {r.group(1)} drapeaux {r.group(2)}"] += 1

conn_total = m["connected"] + (c["connected"] if c else 0)
out = {"principal": m, "temoin": c, "haproxy": {**st, "logs_anormaux": dict(abn),
       "sessions_acceptees_moins_connexions_generateurs": st.get("frontend_stot", 0) - conn_total}}

# --- résumé lisible ---
print(f"   diag générateur principal : {m['errors']} erreur(s) {m['kinds'] or ''} · blocages > 50 ms : {m['stalls']} (max {m['stall_max_s']}s) · retard d'émission max {m['send_lag_max_s']}s")
for e in m["detail"]:
    print(f"      - {e['class']} en phase {e.get('phase','?')} (connexion {e.get('t_conn','-')}s, 1er octet {e.get('t_first','-')}s, durée {e['lat_s']}s) · panne {e['panne']}")
if c:
    print(f"   témoin interne (127.0.0.1 sur la VM HAProxy) : {c['sent']} requêtes, {c['errors']} erreur(s) {c['kinds'] or ''}")
    for e in c["detail"]:
        print(f"      - {e['class']} en phase {e.get('phase','?')} (durée {e['lat_s']}s) · panne {e['panne']}")
h = out["haproxy"]
print(f"   HAProxy : {st.get('frontend_stot')} sessions acceptées pour {conn_total} connexions établies par les générateurs "
      f"(écart {h['sessions_acceptees_moins_connexions_generateurs']:+d}) · abandons client {st.get('backend_cli_abrt')} / serveur {st.get('backend_srv_abrt')} · logs anormaux : {dict(abn) or 'aucun'}")
print(json.dumps(out))
