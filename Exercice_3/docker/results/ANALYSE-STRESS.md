# Analyse des tests de charge (HAProxy 3.4.7) — config principale = v006

Scénario : `webserver1` arrêté puis redémarré 10 fois de suite sous charge continue (`maxconn 100` global conservé : il protège les serveurs d'un déni de service).
Générateur dans des conteneurs Docker (threads à 250 req/s, asyncio au-delà de 1000 req/s), supervision toutes les 0,5 s (`tests/monitor.py`). Chaque ligne = 20 runs (3 pour 6000 req/s, 10 pour 500 et 750). Détail : `3.4/stress-rN/SYNTHESE.md`, `tests/mon-table.sh 3.4`.

## Résultats

| Charge | Config | Erreurs / requêtes | p99 | Conn. HAProxy max | Remarque |
|---|---|---|---|---|---|
| 250 | v006 | 0 / 464 903 | 2 ms | 4 | |
| 250 | v013 (roundrobin) | 1 / 454 173 | 1 s | 51 | débit 244/250 |
| 250 | v002 | 0 / 407 473 | 1,56 s | 100 | débit 219/250, plafond atteint |
| 250 | v004, v009 | ≈ 3,35 % (15 580 / 465 000) | 0,5 s | 85 | 20 runs sur 20 avec erreurs |
| 1500 | v006 / v013 | 16 / 11 sur 2,8 M | 3 / 4 ms | 18 / 59 | indistinguables |
| 3000 | v006 / v013 | 59 / 60 sur 5,7 M | 4 / 5 ms | 100 / 61 | indistinguables |
| 4500 | v006 / v013 | 1561 / 359 sur 8,8 M | 99 / 9 ms | 100 / 73 | médiane 6 / 10 erreurs par run, mais 1 run v006 à 1454 |
| 6000 (3 runs) | v006 / v013 | 23 / 94 sur 1,8 M | 19 / 22 ms | 100 / 83 | hôte à 84 % CPU : limite du banc |

## Ce que les mesures montrent

1. **v004 et v009 perdent 3,35 % des requêtes à 250 req/s, de façon stable (3,23–3,42 %)**. Ce n'est pas un artefact du banc : ce sont des 5xx comptés par HAProxy. Les timeouts de 500 ms et le peu de reprises ne laissent pas assez de marge quand la moitié des connexions part vers un serveur mort. La réactivité extrême de la détection ne compense pas.
2. **v002 ne perd rien mais sature** : 100 connexions ouvertes, débit 219 req/s au lieu de 250, p99 1,6 s. Elle encaisse la panne mais sans marge.
3. **`leastconn` est le paramètre décisif** (v006 contre v013, seule différence). Avec roundrobin, la moitié des requêtes part vers le serveur mort et attend `timeout connect` : p99 de 1 s, 51 connexions HAProxy. Avec leastconn, le serveur mort accumule vite plus de connexions que l'autre et reçoit presque rien : p99 de 2 ms, 4 connexions. Le gain est net de 250 à 750 req/s.
4. **`maxconn 50` par serveur** plafonne les connexions bloquées sur un serveur mort à 50, donc le plafond global de 100 n'est pas atteint (v013 : 50 à 61 connexions). Sans lui, le serveur mort peut consommer tout le budget. La file `timeout queue` n'a jamais servi (qcur max 0 à 3).
5. **De 1500 à 3000 req/s, la différence disparaît** : le taux d'erreur est de 0,001 % pour les deux, et le goulot n'est plus la panne mais le débit brut.
6. **Autour de 4500 req/s, le goulot est le `maxconn 100` global** : HAProxy atteint 100 connexions et son backlog d'accept dépasse 100 (SYN_SENT et files réseau). v006 a un meilleur p99 médian mais une queue de distribution lourde : 1 run sur 20 à 1454 erreurs (0,33 %), alors que v013 reste entre 1 et 91. Taux d'erreur dans les deux cas inférieur à 0,02 % en moyenne.
7. **Ce qui sature d'abord** : CPU de HAProxy (≈ 115 % sur 1 cœur à 4500, c'est un seul thread utile), puis `webserver2` (≈ 87 % à 4500, 89 % à 6000), qui porte seul la charge pendant la panne de l'autre. La mémoire n'est pas un facteur (≥ 3,3 Go libres). Les files d'accept des webservers restent petites (≤ 31 sauf pic ponctuel).

## Conclusion

- **v006 reste la meilleure config pour ce TD** : 0 erreur et p99 de 2 ms à 250 req/s, et elle tient 3000 req/s à égalité avec v013. Elle est la seule à combiner zéro perte et latence faible aux charges réalistes.
- À 4500 req/s ou plus, v006 et v013 se valent à 0,02 % d'erreur près ; v006 a un risque de pic rare quand le `maxconn 100` global est atteint. C'est le prix de la protection anti-déni de service voulue.
- Les pistes pour aller plus loin (non testées) : `nbthread` plus élevé pour HAProxy, un second serveur web (webserver2 est le maillon faible pendant une panne), et un `maxconn` global proportionné au débit visé.

## Limites

Page statique nginx (requête très courte) ; un seul type de panne (arrêt d'un serveur) ; hôte WSL2 partagé de 8 cœurs, avec le générateur et les serveurs sur la même machine ; résultats à 6000 req/s sur 3 runs seulement (hôte à 84 % de CPU, je n'ai pas poussé plus) ; v004/v009 mesurées sur 250 req/s uniquement.
Les colonnes de supervision des webservers (`w1/w2_listen_rq`, `estab`, `timewait`) n'existent que dans les runs récents.
