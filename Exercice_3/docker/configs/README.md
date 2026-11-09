# Versions de configuration HAProxy

## Convention

- `haproxy.cfg` (à la racine de `docker/`) est la **config principale** : actuellement **identique à v006** (la meilleure mesurée, voir `results/ANALYSE-STRESS.md`). C'est celle que monte `docker-compose.yml`.
- Chaque autre config est conservée dans `configs/vNNN/` (`v001`, `v002`, ...). On n'écrase jamais une version : on en crée une nouvelle.
- Quand une version devient la meilleure, on la copie vers `haproxy.cfg`.
- Les **résultats ne sont plus dans ce dossier** : ils sont rangés par version de HAProxy testée dans `results/<version>/<config>/` (voir `tests/README.md`).

## Contenu d'un dossier de version

| Fichier | Rôle |
|---|---|
| `haproxy.cfg` | La configuration |
| `DESCRIPTION.txt` | Une ligne : ce qui la distingue (reprise dans les tableaux) |
| `REQUIRES` | Facultatif : version minimale de HAProxy (ex. `3.1`). La config est ignorée avec une version plus ancienne. |

## Ajouter une version

```bash
mkdir configs/v009
cp haproxy.cfg configs/v009/haproxy.cfg      # puis modifier
echo "Ce qui change dans cette version" > configs/v009/DESCRIPTION.txt
echo "3.1" > configs/v009/REQUIRES           # seulement si elle utilise une fonction récente
./run-all-tests.sh --runs 3 --version 3.4 v009
```

## Versions actuelles (campagne HAProxy 2.3)

| Version | Description |
|---|---|
| v001 | Config de départ (réglages de santé par défaut) |
| v002 | Réactive : inter 1s, fall 2, rise 2, timeout connect 1s, retries 2 + redispatch |
| v003 | Réseau instable (v2) : décisions prudentes (fall 4, rise 4), utilisateur protégé par retries + redispatch |
| v004 | Ultra-réactive : inter 500ms, fall 2, timeouts 500ms, shutdown-sessions |
| v005 | Passive + active lente : inter 5s, observe layer4, error-limit 2, on-error mark-down |
| v006 | Forte charge : leastconn, slowstart 10s, maxconn 50 par serveur, timeout queue |
| v007 | Sessions : persistance par cookie + redispatch |
| v008 | Vérification légère : HEAD, inter 3s, fastinter 500ms, downinter 5s |
| v009 | Comme v004 mais retries 2 (test de l'erreur rare observée sur v004) |
| v013 | Comme v006 mais `balance roundrobin` : isole l'effet de `leastconn` (protections maxconn 50 / timeout queue / slowstart conservées) |

## Versions qui demandent HAProxy récent (campagne 3.4)

Fonctions absentes de la 2.3, d'après la page de documentation des health checks. Chaque config qui les utilise a un fichier `REQUIRES`. Les numéros de version minimale viennent de cette page : seule l'existence des mots-clés a été vérifiée avec `haproxy:3.4` (3.4.7) ; elle est refusée par la 2.3.

| Version | Requiert | Description |
|---|---|---|
| v010 | 3.1 | v004 + `init-state down` : serveur utilisé seulement après ses tests de santé |
| v011 | 3.2 | v004 + `check-reuse-pool` : tests de santé sur les connexions du pool |
| v012 | 3.4 | v004 avec une section `healthcheck` (type httpchk, http-check connect/send/expect) ; `inter`, `fall`, `rise` restent sur le serveur |

Dans la 3.4.7, la section `healthcheck` accepte `type` et `http-check` ; `option httpchk`, `timeout check` et `inter` y sont refusés (constaté avec `haproxy -c`).
Le `maxconn 100` global est volontairement conservé dans toutes les versions : il protège les serveurs d'un déni de service.
