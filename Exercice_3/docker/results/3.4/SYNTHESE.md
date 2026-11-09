# Synthèse HAProxy 3.4

Généré le 2026-11-09 08:24:36 par tests/aggregate.sh. Version(s) exacte(s) : 3.4.7-8872a26.

Test : arrêt de webserver1 pendant 15 s avec des requêtes en continu, puis redémarrage. Valeurs : moyenne sur les runs (± écart-type pour le taux d'erreur et la détection).

| Config | Description | Runs | Taux d'erreur moyen (%) | Pire run (%) | Erreurs moy. | Latence max moy. (s) | Latence max pire (s) | Détection HAProxy (s) | Retour à 2 serveurs (s) | Déclaré UP (s) |
|---|---|---|---|---|---|---|---|---|---|---|
| v001 | Config de départ : tests de santé par défaut (inter 2s, fall 3), timeout connect 5s, sans redispatch. | 3 | 2.757 ± 1.736 | 4.762 | 1.333 | 3.002 | 3.003 | 3.563 ± 0.283 | 4.867 | 4.22 |
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout check 1s, timeout connect 1s, retries 2 + redispatch. | 10 | 0 ± 0 | 0 | 0 | 1.004 | 1.004 | 2.949 ± 0.152 | 2.75 | 2.112 |
| v003 | Réseau instable (anti-flapping, v2) : inter 3s, fall 4, rise 4, downinter 5s ; l'utilisateur est protégé par timeout connect 1s + retries 3 + redispatch. | 3 | 0 ± 0 | 0 | 0 | 1.004 | 1.005 | 9.407 ± 0.006 | 8.8 | 8.1 |
| v004 | Ultra-réactive (latence critique) : inter 500ms, fall 2, timeouts 500ms, retries 1 + redispatch, coupe les sessions d'un serveur déclaré HS. | 10 | 0.303 ± 0.639 | 1.515 | 0.2 | 0.503 | 0.504 | 1.646 ± 0.018 | 2.05 | 1.128 |
| v005 | Détection passive + active lente : tests toutes les 5s (peu de charge), plus observe layer4 / error-limit 2 / on-error mark-down sur le vrai trafic. | 3 | 0 ± 0 | 0 | 0 | 1.004 | 1.004 | 2.44 ± 0 | 6.7 | 6.133 |
| v006 | Forte charge / requêtes longues : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue 5s, détection réactive. | 10 | 0 ± 0 | 0 | 0 | 1.004 | 1.004 | 2.903 ± 0.007 | 3.16 | 2.112 |
| v007 | Application avec sessions : persistance par cookie (cookie SRV insert indirect nocache) + redispatch, détection réactive comme v002. | 3 | 0 ± 0 | 0 | 0 | 1.004 | 1.004 | 2.9 ± 0 | 2.6 | 2.037 |
| v008 | Vérification légère : http-check send meth HEAD, inter 3s, fastinter 500ms, downinter 5s, fall 2, rise 2 (peu de charge, confirmation rapide). | 3 | 0 ± 0 | 0 | 0 | 1.004 | 1.004 | 4.9 ± 0 | 1.9 | 1.05 |
| v009 | Ultra-réactive avec marge : identique à v004 sauf retries 2 (au lieu de 1), pour tester si l'erreur rare de v004 vient du manque de nouvelle tentative. | 10 | 0.455 ± 0.732 | 1.515 | 0.3 | 0.503 | 0.504 | 1.651 ± 0.003 | 2.1 | 1.132 |
| v010 | Ultra-réactive + init-state down (3.1+) : serveur utilisé seulement après ses tests de santé. | 10 | 0.455 ± 0.732 | 1.515 | 0.3 | 0.503 | 0.504 | 1.65 ± 0.008 | 2.1 | 1.131 |
| v011 | Ultra-réactive + check-reuse-pool (3.2+) : tests de santé sur connexions du pool. | 10 | 0.152 ± 0.479 | 1.515 | 0.1 | 0.503 | 0.504 | 1.65 ± 0.005 | 2.1 | 1.137 |
| v012 | Ultra-réactive avec section healthcheck (3.4+) : test de santé défini une fois, réutilisable. | 10 | 0.455 ± 0.732 | 1.515 | 0.3 | 0.503 | 0.504 | 1.652 ± 0.006 | 2.1 | 1.138 |

Lecture : "Détection HAProxy" est le délai entre l'arrêt du serveur et son passage HS dans les logs de HAProxy. Un serveur "jamais HS" est resté en service pendant tout le test. Le taux d'erreur est ce que voit l'utilisateur.
