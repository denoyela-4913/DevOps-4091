# Synthèse stress HAProxy 2.3

Généré le 2026-11-07 13:53:32 par tests/aggregate-stress.sh. Version(s) exacte(s) : 2.3.21-3ce4ee0.

Scénario : webserver1 est arrêté puis redémarré 10 fois de suite, sous une charge continue d'environ 250 requêtes/s (50 fois le test simple). Valeurs : moyenne sur les runs.

| Config | Description | Runs | Taux d'erreur moyen (%) | min – max (%) | Écart-type | Requêtes/run | Débit réel (req/s) | p99 (s) | Latence max pire (s) | Pannes détectées | Détection (s) | Pannes avec erreurs |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| v001 | Config de départ : tests de santé par défaut (inter 2s, fall 3), timeout connect 5s, sans redispatch. | 10 | 5.759 | 5.68 – 5.874 | 0.079 | 17553.9 | 188.57 | 3.003 | 3.016 | 0/10 | n/a | 10/10 |
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout check 1s, timeout connect 1s, retries 2 + redispatch. | 10 | 18.7 | 10.268 – 23.781 | 4.835 | 22113.6 | 237.15 | 1.003 | 3.003 | 10/10 | 2.722 | 10/10 |
| v003 | Réseau instable (anti-flapping, v2) : inter 3s, fall 4, rise 4, downinter 5s ; l'utilisateur est protégé par timeout connect 1s + retries 3 + redispatch. | 10 | 21.745 | 21.683 – 21.856 | 0.057 | 21993.1 | 236.05 | 1.003 | 2.053 | 0/10 | n/a | 10/10 |
| v004 | Ultra-réactive (latence critique) : inter 500ms, fall 2, timeouts 500ms, retries 1 + redispatch, coupe les sessions d'un serveur déclaré HS. | 10 | 6.369 | 5.324 – 8.255 | 0.87 | 23248.9 | 250 | 0.502 | 0.638 | 10/10 | 1.52 | 10/10 |
| v005 | Détection passive + active lente : tests toutes les 5s (peu de charge), plus observe layer4 / error-limit 2 / on-error mark-down sur le vrai trafic. | 10 | 0 | 0 – 0 | 0 | 23231.4 | 250 | 0.002 | 1.003 | 4/10 | 0.086 | 0/10 |
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 10 | 0 | 0 – 0 | 0 | 23117.7 | 248.64 | 0.003 | 2.011 | 10/10 | 3.148 | 0/10 |
| v007 | Application avec sessions : persistance par cookie (cookie SRV insert indirect nocache) + redispatch, détection réactive comme v002. | 10 | 17.473 | 11.797 – 26.151 | 4.083 | 22093.6 | 237.2 | 1.003 | 3.003 | 9.9/10 | 2.637 | 10/10 |
| v008 | Vérification légère : http-check send meth HEAD, inter 3s, fastinter 500ms, downinter 5s, fall 2, rise 2 (peu de charge, confirmation rapide). | 10 | 17.44 | 11.762 – 21.013 | 3.271 | 22252.1 | 238.99 | 1.003 | 3.003 | 5.7/10 | 3.085 | 8.2/10 |
| v009 | Ultra-réactive avec marge : identique à v004 sauf retries 2 (au lieu de 1), pour tester si l'erreur rare de v004 vient du manque de nouvelle tentative. | 10 | 6.821 | 4.264 – 9.377 | 1.545 | 23266.9 | 250 | 0.502 | 0.962 | 10/10 | 1.57 | 10/10 |

Lecture : "Pannes détectées" = nombre moyen de pannes (sur 10) que HAProxy a eu le temps de déclarer (serveur HS) pendant que le serveur était arrêté. "Pannes avec erreurs" = pannes pendant lesquelles au moins une requête a échoué.
