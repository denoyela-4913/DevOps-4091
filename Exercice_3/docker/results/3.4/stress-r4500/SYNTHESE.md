# Synthèse stress HAProxy 3.4 (stress-r4500)

Généré le 2026-11-09 04:34:26 par tests/aggregate-stress.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 4500 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 20 | 0.018 | 0 – 0.333 | 0.074 | 439710.5 | 4490.72 | 0.099 | 3.08 | 10/10 | 3.007 | 2.9/10 |
| v013 | Comme v006 mais balance roundrobin (sans leastconn) : isole l'effet de leastconn. | 20 | 0.004 | 0 – 0.021 | 0.005 | 439545.45 | 4490.7 | 0.009 | 2.596 | 10/10 | 2.997 | 3.85/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
