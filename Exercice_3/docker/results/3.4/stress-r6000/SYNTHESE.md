# Synthèse stress HAProxy 3.4 (stress-r6000)

Généré le 2026-11-09 04:34:26 par tests/aggregate-stress.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 6000 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 3 | 0.001 | 0.001 – 0.002 | 0.001 | 596073.667 | 5981.933 | 0.019 | 2.022 | 10/10 | 2.86 | 3.333/10 |
| v013 | Comme v006 mais balance roundrobin (sans leastconn) : isole l'effet de leastconn. | 3 | 0.005 | 0.003 – 0.007 | 0.002 | 596008.667 | 5981.033 | 0.022 | 2.003 | 10/10 | 2.643 | 4.667/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
