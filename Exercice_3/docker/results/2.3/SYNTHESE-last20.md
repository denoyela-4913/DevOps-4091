# Synthèse HAProxy 2.3

Généré le 2026-11-07 11:03:55 par tests/aggregate.sh (--last 20). Version(s) exacte(s) : 2.3.21-3ce4ee0.

Test : arrêt de webserver1 pendant 15 s avec des requêtes en continu, puis redémarrage. Valeurs : moyenne sur les runs (± écart-type pour le taux d'erreur et la détection).

| Config | Description | Runs | Taux d'erreur moyen (%) | Pire run (%) | Erreurs moy. | Latence max moy. (s) | Latence max pire (s) | Détection HAProxy (s) | Retour à 2 serveurs (s) | Déclaré UP (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| v001 | Config de départ : tests de santé par défaut (inter 2s, fall 3), timeout connect 5s, sans redispatch. | 5 | 28.19 ± 0.852 | 28.571 | 4 | 3.003 | 3.003 | 11.89 ± 0.007 | 5.5 | 4.648 |
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout check 1s, timeout connect 1s, retries 2 + redispatch. | 20 | 0 ± 0 | 0 | 0 | 1.003 | 1.004 | 3.388 ± 0.004 | 3.15 | 2.53 |
| v003 | Réseau instable (anti-flapping, v2) : inter 3s, fall 4, rise 4, downinter 5s ; l'utilisateur est protégé par timeout connect 1s + retries 3 + redispatch. | 5 | 0 ± 0 | 0 | 0 | 1.004 | 1.005 | 9.888 ± 0.004 | 9.3 | 8.596 |
| v004 | Ultra-réactive (latence critique) : inter 500ms, fall 2, timeouts 500ms, retries 1 + redispatch, coupe les sessions d'un serveur déclaré HS. | 20 | 0 ± 0 | 0 | 0 | 0.503 | 0.504 | 1.637 ± 0.005 | 2.1 | 1.098 |
| v005 | Détection passive + active lente : tests toutes les 5s (peu de charge), plus observe layer4 / error-limit 2 / on-error mark-down sur le vrai trafic. | 5 | 0 ± 0 | 0 | 0 | 1.003 | 1.005 | 2.44 ± 0 | 7.24 | 6.638 |
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 5 | 0 ± 0 | 0 | 0 | 2.003 | 2.004 | 3.392 ± 0.004 | 3.32 | 2.546 |
| v007 | Application avec sessions : persistance par cookie (cookie SRV insert indirect nocache) + redispatch, détection réactive comme v002. | 5 | 0 ± 0 | 0 | 0 | 1.004 | 1.005 | 3.386 ± 0.005 | 3.1 | 2.504 |
| v008 | Vérification légère : http-check send meth HEAD, inter 3s, fastinter 500ms, downinter 5s, fall 2, rise 2 (peu de charge, confirmation rapide). | 5 | 0 ± 0 | 0 | 0 | 1.004 | 1.005 | 5.384 ± 0.005 | 2.6 | 1.618 |
| v009 | Ultra-réactive avec marge : identique à v004 sauf retries 2 (au lieu de 1), pour tester si l'erreur rare de v004 vient du manque de nouvelle tentative. | 20 | 0 ± 0 | 0 | 0 | 0.503 | 0.504 | 1.638 ± 0.004 | 2.1 | 1.095 |

Lecture : "Détection HAProxy" est le délai entre l'arrêt du serveur et son passage HS dans les logs de HAProxy. Un serveur "jamais HS" est resté en service pendant tout le test. Le taux d'erreur est ce que voit l'utilisateur.
