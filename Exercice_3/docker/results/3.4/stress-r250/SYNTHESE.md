# Synthèse stress HAProxy 3.4 (stress-r250)

Généré le 2026-11-09 04:34:25 par tests/aggregate-stress.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 250 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout check 1s, timeout connect 1s, retries 2 + redispatch. | 20 | 0 | 0 – 0 | 0 | 20373.65 | 218.88 | 1.562 | 2.587 | 10/10 | 2.967 | 0/10 |
| v004 | Ultra-réactive (latence critique) : inter 500ms, fall 2, timeouts 500ms, retries 1 + redispatch, coupe les sessions d'un serveur déclaré HS. | 20 | 3.347 | 3.233 – 3.423 | 0.055 | 23266.65 | 250 | 0.502 | 0.527 | 10/10 | 1.565 | 10/10 |
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 20 | 0 | 0 – 0 | 0 | 23245.15 | 249.79 | 0.002 | 1.004 | 10/10 | 2.986 | 0/10 |
| v009 | Ultra-réactive avec marge : identique à v004 sauf retries 2 (au lieu de 1), pour tester si l'erreur rare de v004 vient du manque de nouvelle tentative. | 20 | 3.351 | 3.26 – 3.389 | 0.028 | 23260.95 | 250 | 0.502 | 0.532 | 10/10 | 1.592 | 10/10 |
| v013 | Comme v006 mais balance roundrobin (sans leastconn) : isole l'effet de leastconn. | 20 | 0 | 0 – 0.004 | 0.001 | 22708.65 | 244.07 | 1.002 | 2.003 | 10/10 | 2.973 | 0.05/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
