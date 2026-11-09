# Synthèse stress HAProxy aws (stress-r100)

Généré le 2026-11-09 16:58:17 par tests/aggregate-stress.sh. Version(s) exacte(s) : 2.8.30-0ubuntu0.24.04.2, 3.4.7-1ppa1~resolute.

Scénario : webserver1 est arrêté puis redémarré 3 fois de suite, sous une charge continue d'environ 100 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| aws-2.8 |  | 2 | 0.012 | 0 – 0.023 | 0.016 | 4294.5 | 100 | 0.232 | 2.161 | 3/3 | 1.28 | 0.5/3 |
| aws-3.4 |  | 2 | 0 | 0 – 0 | 0 | 4294.5 | 100 | 0.615 | 2.198 | 3/3 | 1.245 | 0/3 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 3) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
