# Comparatif des configurations HAProxy

Généré le 2026-11-07 00:05:09 par run-all-tests.sh. Test : arrêt de webserver1 pendant la durée indiquée, requêtes en continu, puis redémarrage.

| Config | Description | Syntaxe | Requêtes réussies | Erreurs | Taux d'erreur | Dernière erreur (s) | Latence max (s) | Latence moy. (s) | Retour à 2 serveurs (s) | Date du test |
|---|---|---|---|---|---|---|---|---|---|---|
| **main** | Config principale (haproxy.cfg), identique à v001 | ok | 11/15 | 4 | 26.7 % | 10.50 | 3.002 | 0.001 | 5.2 | 20261106-233043 |
| v001 | Config de départ : tests de santé par défaut (inter 2s, fall 3), timeout connect 5s, sans redispatch. | ok | 11/15 | 4 | 26.7 % | 10.49 | 3.002 | 0.001 | 5.2 | 20261106-233105 |
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout check 1s, timeout connect 1s, retries 2 + redispatch. | ok | 57/57 | 0 | 0 % | 0.00 | 1.003 | 0.054 | 3.6 | 20261106-233127 |
| v003 | Réseau instable (anti-flapping) : inter 5s, fall 5, rise 3, timeouts 3s, retries 3 + redispatch. Détection lente, peu de faux positifs. | ok | 1/6 | 5 | 83.3 % | 13.09 | 3.003 | 0.001 | 0.5 | 20261107-000326 |
| v004 | Ultra-réactive (latence critique) : inter 500ms, fall 2, timeouts 500ms, retries 1 + redispatch, coupe les sessions d'un serveur déclaré HS. | ok | 65/66 | 1 | 1.5 % | 1.64 | 0.503 | 0.016 | 2.1 | 20261107-000346 |
| v005 | Détection passive + active lente : tests toutes les 5s (peu de charge), plus observe layer4 / error-limit 2 / on-error mark-down sur le vrai trafic. | ok | 62/62 | 0 | 0 % | 0.00 | 1.002 | 0.034 | 7.2 | 20261107-000405 |
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | ok | 52/52 | 0 | 0 % | 0.00 | 2.004 | 0.078 | 3.6 | 20261107-000429 |
| v007 | Application avec sessions : persistance par cookie (cookie SRV insert indirect nocache) + redispatch, détection réactive comme v002. | ok | 57/57 | 0 | 0 % | 0.00 | 1.003 | 0.054 | 3.6 | 20261107-000449 |

Lecture : moins il y a d'erreurs et de latence max, moins l'utilisateur perçoit la panne. "Dernière erreur" est le temps écoulé depuis l'arrêt du serveur jusqu'à la dernière requête en échec (0 = aucune erreur).
