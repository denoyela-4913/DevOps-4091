#!/usr/bin/env python3
"""Vérifie les runs de stress supervisés (MONITOR=1) : débit tenu, ressources de l'hôte, erreurs.

Appel (depuis Exercice_3/docker/) :
  python3 tests/check-round.py [--strict] <version> [charge ...]
    version   version de HAProxy, ex. 3.4 (obligatoire)
    charge    charges à examiner, ex. 1500 3000          (défaut : tous les dossiers results/<version>/stress-r*)
    --strict  code retour 2 si un problème est détecté pour une charge >= 1000 req/s
              (sert à arrêter une campagne enchaînée, voir run-all-tests.sh)

Lit    : results/<version>/stress-r<charge>/<config>/run-*.json
Écrit  : un tableau Markdown (une ligne par charge et par config) avec un verdict.
Problèmes signalés : débit réel < 97 % de la cible (cible >= 1000), CPU hôte > 88 % (cible < 6000),
mémoire disponible < 1,5 Go.
"""
import glob, json, statistics as st, sys
# --strict est retiré de argv pour que argv[1] soit bien la version
strict = "--strict" in sys.argv; sys.argv = [a for a in sys.argv if a != "--strict"]
bad = []
# Charges : arguments, sinon déduites des noms de dossiers stress-r<N>
v = sys.argv[1]; rates = sys.argv[2:] or [d.split("stress-r")[1] for d in sorted(glob.glob(f"results/{v}/stress-r*"))]
print("| Charge | Config | Runs | Erreurs tot / req | Runs avec err | Débit réel / visé | p99 s | Lat. max s | CPU hôte max % | Mém. libre min Mo | CPU HAProxy max % | CPU gén. max % | CPU ws1/ws2 max % | Backlog HAProxy max | Backlog ws max | Conn. HAProxy max | SYN_SENT max | Verdict |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
# Une ligne par (charge, config), calculée sur tous les runs valides (syntaxe ok)
for r in rates:
    for d in sorted(glob.glob(f"results/{v}/stress-r{r}/v*/")):
        cfg = d.rstrip("/").split("/")[-1]
        R = [json.load(open(f)) for f in sorted(glob.glob(d + "run-*.json"))]
        R = [x for x in R if x.get("syntax") == "ok"]
        if not R: continue
        # m(clé, fonction) : max (ou min) du champ de supervision sur les runs ; None si aucun run ne l'a
        # (les anciens runs n'ont pas les champs des webservers)
        m = lambda k, f=max: f(x["mon"][k] for x in R if x.get("mon") and k in x["mon"]) if any(x.get("mon") and k in x["mon"] for x in R) else None
        rps = st.mean(x["rps_actual"] for x in R); tgt = int(r)
        # plus grand backlog d'accept observé sur l'un des deux webservers
        ws = max([a for a in (m("max_ws1_listen_rq"), m("max_ws2_listen_rq")) if a is not None], default=None)
        # Contrôles de validité du banc d'essai (pas du HAProxy testé)
        issues = []
        if rps < 0.97 * tgt and tgt >= 1000: issues.append("débit < 97 % de la cible")
        if (m("max_host_cpu_pct") or 0) > 88 and tgt < 6000: issues.append("CPU hôte > 85 %")
        if (m("min_mem_avail_mb", min) or 9e9) < 1500: issues.append("mémoire < 1,5 Go")
        if issues and tgt >= 1000: bad.append((r, cfg, issues))
        # Totaux et ligne du tableau
        errs = sum(x["errors"] for x in R); req = sum(x["requests"] for x in R)
        print(f"| {r} | {cfg} | {len(R)} | {errs} / {req} | {sum(1 for x in R if x['errors']>0)} | {rps:.0f} / {tgt} | {st.mean(x['p99_latency_s'] for x in R):.3f} | {max(x['max_latency_s'] for x in R):.2f} | {m('max_host_cpu_pct')} | {m('min_mem_avail_mb', min)} | {m('max_haproxy_cpu_pct')} | {m('max_gen_cpu_pct')} | {m('max_ws1_cpu_pct')}/{m('max_ws2_cpu_pct')} | {m('max_listen_rq')} | {ws} | {m('max_cur_conns')} | {m('max_syn_sent')} | {'; '.join(issues) or 'ok'} |")

# Sortie en erreur pour interrompre une campagne si le banc est hors limites
if strict and bad:
    print("\nARRÊT : ", bad)
    sys.exit(2)
