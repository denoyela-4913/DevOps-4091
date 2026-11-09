# Synthèse stress HAProxy 3.4 (stress)

Généré le 2026-11-09 04:34:25 par tests/aggregate-stress.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 250 requêtes/s. Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v001 | Config de départ : tests de santé par défaut (inter 2s, fall 3), timeout connect 5s, sans redispatch. | 3 | 5.748 | 5.732 – 5.773 | 0.022 | 17542.333 | 188.633 | 3.003 | 3.006 | 0/10 | n/a | 10/10 |
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout check 1s, timeout connect 1s, retries 2 + redispatch. | 10 | 0 | 0 – 0 | 0 | 20494.6 | 219.86 | 1.547 | 2.578 | 10/10 | 2.952 | 0/10 |
| v003 | Réseau instable (anti-flapping, v2) : inter 3s, fall 4, rise 4, downinter 5s ; l'utilisateur est protégé par timeout connect 1s + retries 3 + redispatch. | 3 | 0 | 0 – 0 | 0 | 19689 | 211.533 | 1.607 | 1.684 | 0/10 | n/a | 0/10 |
| v004 | Ultra-réactive (latence critique) : inter 500ms, fall 2, timeouts 500ms, retries 1 + redispatch, coupe les sessions d'un serveur déclaré HS. | 10 | 3.122 | 3.001 – 3.288 | 0.09 | 23273.3 | 250 | 0.502 | 0.514 | 10/10 | 1.279 | 10/10 |
| v005 | Détection passive + active lente : tests toutes les 5s (peu de charge), plus observe layer4 / error-limit 2 / on-error mark-down sur le vrai trafic. | 3 | 0 | 0 – 0 | 0 | 23245.667 | 250 | 0.002 | 1.003 | 2/10 | 0.09 | 0/10 |
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 10 | 0.001 | 0 – 0.004 | 0.002 | 23376.6 | 249.79 | 0.002 | 1.006 | 10/10 | 3.11 | 0.2/10 |
| v007 | Application avec sessions : persistance par cookie (cookie SRV insert indirect nocache) + redispatch, détection réactive comme v002. | 3 | 0 | 0 – 0 | 0 | 20127.333 | 216.1 | 1.56 | 2.654 | 10/10 | 3.22 | 0/10 |
| v008 | Vérification légère : http-check send meth HEAD, inter 3s, fastinter 500ms, downinter 5s, fall 2, rise 2 (peu de charge, confirmation rapide). | 3 | 0 | 0 – 0 | 0 | 21078 | 226.633 | 1.579 | 1.674 | 5/10 | 4.017 | 0/10 |
| v009 | Ultra-réactive avec marge : identique à v004 sauf retries 2 (au lieu de 1), pour tester si l'erreur rare de v004 vient du manque de nouvelle tentative. | 10 | 3.218 | 3.016 – 3.497 | 0.186 | 23269.9 | 249.57 | 0.502 | 2.45 | 10/10 | 1.431 | 10/10 |
| v010 | Ultra-réactive + init-state down (3.1+) : serveur utilisé seulement après ses tests de santé. | 10 | 3.299 | 3.015 – 3.504 | 0.175 | 23244 | 250 | 0.502 | 0.516 | 10/10 | 1.509 | 10/10 |
| v011 | Ultra-réactive + check-reuse-pool (3.2+) : tests de santé sur connexions du pool. | 10 | 3.124 | 3.002 – 3.266 | 0.084 | 23245.8 | 250 | 0.502 | 0.515 | 10/10 | 1.274 | 10/10 |
| v012 | Ultra-réactive avec section healthcheck (3.4+) : test de santé défini une fois, réutilisable. | 10 | 3.144 | 3.004 – 3.504 | 0.168 | 23247.3 | 250 | 0.502 | 0.512 | 10/10 | 1.284 | 10/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
