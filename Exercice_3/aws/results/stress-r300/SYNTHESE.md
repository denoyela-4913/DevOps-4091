# Synthèse stress HAProxy aws (stress-r300)

Généré le 2026-11-09 17:37:40 par tests/aggregate-stress.sh. Version(s) exacte(s) : 2.8.30-0ubuntu0.24.04.2, 3.4.7-1ppa1~resolute.

Scénario : webserver1 est arrêté puis redémarré 3 fois de suite, sous une charge continue d'environ 300 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| aws-2.8 |  | 2 | 0.023 | 0.023 – 0.023 | 0 | 12906 | 300 | 1.121 | 3.001 | 3/3 | 1.17 | 2/3 |
| aws-3.4 |  | 2 | 0.016 | 0 – 0.031 | 0.022 | 12922 | 300 | 1.124 | 3.001 | 3/3 | 1.145 | 1/3 |
| aws-3.4-diag |  | 5 | 0.002 | 0 – 0.008 | 0.004 | 12936 | 300 | 0.119 | 2.177 | 3/3 | 1.144 | 0.2/3 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 3) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
