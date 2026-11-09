# Synthèse stress HAProxy 3.4 (stress-r3000)

Généré le 2026-11-09 04:34:25 par tests/aggregate-stress.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 3000 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 20 | 0.001 | 0 – 0.006 | 0.002 | 287147.95 | 2997.095 | 0.004 | 2.006 | 10/10 | 2.851 | 0.95/10 |
| v013 | Comme v006 mais balance roundrobin (sans leastconn) : isole l'effet de leastconn. | 20 | 0.001 | 0 – 0.003 | 0.001 | 287154.3 | 2996.99 | 0.005 | 1.019 | 10/10 | 2.85 | 1.6/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
