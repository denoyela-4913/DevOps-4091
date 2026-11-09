# Synthèse stress HAProxy 3.4 (stress-r750)

Généré le 2026-11-08 12:36:33 par tests/aggregate-stress.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 750 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 3 | 24.314 | 23.812 – 24.723 | 0.463 | 59519.667 | 624.8 | 1.725 | 2.736 | 10/10 | 2.817 | 10/10 |
| v013 | Comme v006 mais balance roundrobin (sans leastconn) : isole l'effet de leastconn. | 3 | 23.919 | 23.108 – 24.416 | 0.709 | 60022.333 | 629.967 | 1.714 | 2.716 | 10/10 | 2.823 | 10/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
