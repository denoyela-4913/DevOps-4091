# Analyse des tests de charge AWS — config = `haproxy.cfg.tpl` alignée sur docker v006

Deux campagnes très courtes le 2026-11-09, sur 3 VM `t3.micro` (HAProxy + 2 webservers nginx dans Docker), eu-north-1, créées puis détruites à chaque fois (7 ressources) :

| Campagne | OS des VM | HAProxy | Dossiers |
|---|---|---|---|
| `aws-2.8` | Ubuntu 24.04 | 2.8.30 (paquet Ubuntu) | `stress-rN/aws-2.8/` |
| `aws-3.4` | Ubuntu 26.04 | **3.4.7** (PPA `vbernat/haproxy-3.4`) | `stress-rN/aws-3.4/` |

**Pourquoi 3.4** : c'est une branche LTS (sortie 2026-06-03, supportée jusqu'à ~2031) et la version testée côté docker. Ubuntu 24.04 s'arrête à 2.8 (paquet officiel) / 3.3 (PPA, branche non-LTS) : la 3.4 n'existe que pour Ubuntu 26.04, d'où le changement d'AMI (HAProxy et webservers, pour avoir le même OS partout). Sur 26.04, il faut aussi désactiver la variante d'architecture `amd64v3` d'apt, absente du PPA (voir `main.tf`).

Scénario identique à docker, mais **3 pannes** de `webserver1` (`docker stop` par SSH, 3 s arrêté, 8 s entre deux) au lieu de 10, sous charge continue. 2 runs par charge. Même générateur (`loadgen_async.py`) et mêmes métriques (`stress_metrics.py`) que docker.

## Résultats

| Charge | HAProxy | Erreurs / requêtes | p99 (par run) | Latence max | Détection moy. | Pannes avec erreurs | Conn. frontend max |
|---|---|---|---|---|---|---|---|
| 100 req/s | 2.8.30 | 1 / 8 589 (0,012 %) | 0,14 ; 0,32 s | 2,16 s | 1,26 ; 1,30 s | 1/6 | 6 ; 20 |
| 100 req/s | **3.4.7** | **0 / 8 589** | 0,11 ; 1,12 s | 2,20 s | 1,27 ; 1,22 s | 0/6 | 3 ; 5 |
| 300 req/s | 2.8.30 | 6 / 25 812 (0,023 %) | 1,12 ; 1,12 s | 3,00 s | 1,13 ; 1,21 s | 4/6 | 9 ; 14 |
| 300 req/s | **3.4.7** | 4 / 25 844 (0,015 %) | 1,12 ; 1,13 s | 3,00 s | 1,19 ; 1,10 s | 2/6 | 8 ; 24 |

Côté HAProxy 3.4 (socket admin) : `backend_smax` 3 à 23 (limite : 50 par serveur), `qmax` 0 (la file `timeout queue` n'a jamais servi), `5xx` 0, `econ` 0, `eresp` 0, `wretr` 0, redispatch (`wredis`) de 192 à 572 par run. Toutes les pannes ont été détectées (12/12) et chaque panne a eu son retour UP.

## Ce que les mesures montrent

1. **La config v006 tient la panne sur AWS avec HAProxy 3.4** : 0 erreur à 100 req/s, 4 requêtes perdues sur 25 844 à 300 req/s (0,015 %), sans aucune trace de saturation (file vide, au plus 23 connexions sur 50).
2. **Détection rapide et régulière : 1,1 à 1,3 s** (max 1,62 s), conforme à `inter 1s` + `fastinter 500ms` + `fall 2`. Identique en 2.8 et en 3.4. Docker v006 mesurait 3,1 s, mais ce n'est pas comparable (voir limites).
3. **Le p99 de ~1,12 s à 300 req/s n'est pas stable** : il valait 1,12 s dans les 4 premiers runs 300 req/s (2.8 et 3.4) et 0,12 s dans les 5 runs de la campagne de diagnostic (même config, mêmes VM). L'explication « `timeout connect 1s` avant redispatch » que j'avais proposée n'est donc pas établie ; je n'ai pas de cause pour cet écart.
4. **Les erreurs à 3,0 s (4 sur 25 844 en 3.4, 6 sur 25 812 en 2.8) n'ont pas été reproduites** par la campagne de diagnostic (0 sur ~130 000 requêtes, voir ci-dessous). Leur origine reste inconnue.
5. **2.8 et 3.4 ne se distinguent pas avec cet échantillon** : 4 à 6 erreurs sur ~25 800 requêtes, soit un écart de 2 requêtes. L'avantage apparent de la 3.4 (0 erreur à 100 req/s) n'est pas significatif.
6. **Les connexions HAProxy (3 à 24) dépassent celles de docker v006 à 250 req/s (4)** : attendu, chaque requête dure plus longtemps à cause de la latence réseau.

## Contrôle interne (campagne `aws-3.4-diag`, 5 runs × 300 req/s, HAProxy 3.4.7)

Ajouté pour localiser les erreurs : classe et phase de chaque erreur dans le générateur, blocages du générateur, compteurs et logs HAProxy, et un **générateur témoin sur la VM HAProxy** (127.0.0.1, même débit, en même temps). La charge sur HAProxy est doublée (2 × 300 req/s) : ces résultats ne sont pas comparables aux campagnes précédentes.

| | Principal (poste → Internet) | Témoin (127.0.0.1 sur la VM HAProxy) |
|---|---|---|
| Requêtes | 64 680 | 65 478 |
| Erreurs | 1 (HTTP 502) | 1 (HTTP 502) |
| Erreurs à 3 s (`TimeoutError`) | 0 | 0 |

- **Aucune perte avant HAProxy** : dans chaque run, les sessions acceptées par HAProxy égalent exactement les connexions établies par les deux générateurs (écart 0 sur 5 runs, ~130 000 sessions). Aucun abandon client ni serveur, aucune erreur de requête frontend.
- **Le générateur n'est pas en cause** dans cette campagne : aucun blocage de la boucle (> 50 ms), retard d'émission max 22 ms.
- **Les 2 seules erreurs sont des 502 `SH--`** (le serveur a coupé avant d'envoyer ses en-têtes), apparues 0,11 s et 0,14 s après l'arrêt de `webserver1` : ce sont des requêtes en vol sur le conteneur tué (`docker stop -t 0`). HAProxy ne rejoue pas une requête déjà envoyée. Elles sont vues par HAProxy (une ligne de log chacune), et une est apparue côté témoin interne : ce n'est pas un problème réseau.
- **Limite** : ce contrôle prouve que les 502 viennent de la panne elle-même, mais ne dit rien des erreurs à 3 s, qui ne sont pas apparues. Elles venaient peut-être de la route Internet à ce moment-là, ou d'un état particulier des VM ; avec 0 occurrence sur ~130 000 requêtes, on ne peut pas trancher.

## Conclusion

- La config alignée sur v006 fonctionne sur AWS avec HAProxy 3.4.7 : bascule détectée en ~1,2 s, retour UP à chaque panne, pertes ≤ 0,015 % à 300 req/s et nulles à 100 req/s. Les erreurs identifiées avec certitude sont des requêtes en vol sur le serveur tué (502 `SH--`), pas des pertes réseau ni du générateur.
- Le « 0 erreur » docker à 250 req/s n'est pas reproduit à l'identique à 300 req/s (quelques requêtes perdues), mais l'échantillon est trop petit pour conclure à une différence réelle.
- Passer de 2.8 à 3.4 ne change pas le comportement mesuré ; le choix de la 3.4 repose sur le support LTS et la cohérence avec docker, pas sur un gain de performance démontré.

## Limites

- **Très petit échantillon** : 3 pannes × 2 runs par charge et par version (docker : 10 × 20). Un écart de 1 ou 2 requêtes change le taux ; aucune barre d'erreur crédible.
- **Charges de 100 et 300 req/s seulement** : on ne sait rien de la saturation (docker : jusqu'à 6000 req/s).
- **2.8 et 3.4 diffèrent aussi par l'OS** (Ubuntu 24.04 contre 26.04) : l'effet de la version de HAProxy n'est pas isolé.
- **Pas comparable à docker en l'état** : générateur sur Internet depuis WSL2 (horloge locale décalée de ~1,2 à 1,4 s, corrigée par mesure SSH), `t3.micro` (crédits CPU) contre un hôte de 8 cœurs, résolution par IP privée (pas de DNS Docker), arrêt du conteneur par SSH (quelques dizaines de ms de biais sur l'heure d'arrêt).
- Une seule config testée sur AWS (pas de v013 roundrobin pour isoler l'effet de `leastconn`).
- Pas de supervision CPU/mémoire des VM.
- Page statique nginx et un seul type de panne, comme côté docker.
