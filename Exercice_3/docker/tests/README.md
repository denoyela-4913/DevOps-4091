# Tests de bascule

## Ce que mesure le test

`test-failover.sh` simule la panne de `webserver1` et mesure ce que voit un utilisateur, et ce que fait HAProxy :

1. Valide la syntaxe de la config (`haproxy -c`).
2. Démarre un HAProxy **temporaire** avec cette config, sur le port 18080 (le HAProxy principal, port 8080, n'est pas touché).
3. Vérifie la répartition initiale (2 serveurs distincts sur 10 requêtes).
4. Arrête `webserver1` et envoie des requêtes en continu pendant 15 s.
5. Lit les logs de HAProxy pour savoir quand il a déclaré le serveur HS.
6. Redémarre `webserver1`, mesure le temps avant que les deux serveurs répondent, et quand HAProxy le déclare UP.
7. Nettoie le conteneur de test et remet les serveurs en marche.

## Indicateurs (un fichier `run-<date>.json` par run)

| Champ | Sens |
|---|---|
| `haproxy_tag`, `haproxy_version` | Tag de l'image demandée et version exacte constatée |
| `requests`, `ok`, `errors` | Requêtes envoyées, réussies (HTTP 200), en échec (autre code ou délai de 3 s dépassé) |
| `last_error_s` | Secondes entre l'arrêt du serveur et la dernière erreur (0 = aucune erreur) |
| `max_latency_s`, `avg_latency_s` | Latence maximale et moyenne des requêtes |
| `detection_s` | Secondes avant que HAProxy déclare le serveur HS (`-1` = jamais) |
| `recovery_s` | Secondes avant le retour des 2 serveurs côté utilisateur (`-1` = non revenu) |
| `up_s` | Secondes avant que HAProxy déclare le serveur UP (`-1` = jamais) |

## Organisation des résultats : par version de HAProxy

```
results/
├── 2.3/                      campagne de référence HAProxy 2.3
│   ├── v001/run-<date>.json  un fichier par run
│   ├── v002/ ...
│   ├── SYNTHESE.md           moyennes de la version (générée)
│   └── SYNTHESE.json
├── 3.4/                      même organisation pour la version suivante
├── COMPARATIF-VERSIONS.md    mêmes configs, versions côte à côte (généré)
└── _preliminaire-2.3-1run/   premiers essais à 1 run, conservés mais exclus des moyennes
```

Les dossiers dont le nom ne commence pas par un chiffre (comme `_preliminaire-...`) sont ignorés par le calcul des moyennes.

## Utilisation

```bash
# Campagne : 5 runs de chaque config sur HAProxy 2.3
./run-all-tests.sh --runs 5 --version 2.3 v001 v002 v003 v004 v005 v006 v007 v008

# Série suivante sur HAProxy 3.4 (3 runs)
./run-all-tests.sh --runs 3 --version 3.4

# Une seule config, un seul run
HAPROXY_VERSION=2.3 tests/test-failover.sh configs/v002/haproxy.cfg results/2.3/v002

# Moyennes seules (sans relancer de test), éventuellement sur les 3 derniers runs
tests/aggregate.sh                  # toutes les versions
tests/aggregate.sh --last 3 2.3     # les 3 derniers runs de la 2.3
./run-all-tests.sh --report --version 2.3
```

Le tag de version est celui de l'image Docker (`haproxy:<tag>`), choisi par la variable `HAPROXY_VERSION` (défaut `2.3`) lue par `docker-compose.yml`.

## Durée

Environ 30 à 40 s par run. Les runs sont entrelacés (run 1 de toutes les configs, puis run 2...) pour que les variations de la machine pèsent de la même façon sur chaque config. La syntaxe n'est vérifiée qu'au premier run.

## Scénario « stress » (`test-stress.sh`)

Même HAProxy temporaire, mais :

- **10 pannes à la suite** de `webserver1` : arrêté 3 s, redémarré, 5 s de répit, et on recommence.
- **~250 requêtes/s** en continu (le test simple en envoie environ 5 : x50), envoyées par `loadgen.py` (150 connexions concurrentes, délai de 3 s par requête).
- 3 s de charge avant la 1re panne, 5 s après la dernière.

Résultats dans `results/<version>/stress/<config>/run-<date>.json`, moyennés par `tests/aggregate-stress.sh` (`results/<version>/stress/SYNTHESE.md`).

```bash
./run-all-tests.sh --scenario stress --runs 10 --version 2.3 v001 v002 ...   # ~100 s par run
CYCLES=2 tests/test-stress.sh configs/v002/haproxy.cfg /tmp/essai            # essai rapide
KEEP_RAW=/tmp/raw tests/test-stress.sh ...   # garde les requêtes brutes et les logs HAProxy pour diagnostic
```

Réglages par variables d'environnement : `CYCLES`, `DOWN_S`, `UP_S`, `RATE`, `WORKERS`, `WARMUP`, `COOLDOWN`.

Indicateurs propres au stress : `error_rate_pct`, `p99_latency_s`, `rps_actual` (débit réellement obtenu), `detected_cycles` (pannes que HAProxy a eu le temps de déclarer HS), `detection_mean_s`, `up_events` (passages UP), `cycles_with_errors`, `errors_per_cycle`.

Point d'attention : le bloc `global` de toutes les configs a `maxconn 100`. Sous 250 req/s, cette limite suffit à provoquer des erreurs 503 (« Cannot get a server socket ») quand beaucoup de connexions attendent un serveur mort. Sur v002, 0 erreur avec `maxconn 1000` contre environ 10 % avec `maxconn 100` (essai de 2 pannes). Les résultats du stress mesurent donc aussi cette limite, pas seulement la stratégie de vérification de santé.

### Charges différentes, supervision, générateur dans Docker

```bash
./run-all-tests.sh --scenario stress --rate 750 --runs 10 --version 3.4 v006 v013   # results/3.4/stress-r750/
tests/mon-table.sh 3.4      # tableau comparatif charge x config avec les indicateurs de saturation
```

- `--rate N` : charge visée ; les résultats vont dans `results/<version>/stress-rN/`. Active `MONITOR=1` et `GEN=container`.
- `MONITOR=1` (`tests/monitor.py`) : toutes les 0,5 s :
  - **HAProxy** (socket stats) : connexions, file `qcur`, refus (`econ`, 5xx), et pour chacun des 2 webservers (vus par HAProxy) sessions `scur`, file `qcur` et état UP/DOWN ;
  - **files réseau du conteneur HAProxy uniquement** (`/proc/net/tcp`) : `SYN_SENT`, backlog d'accept, `ESTABLISHED`, `TIME_WAIT` ;
  - **files réseau de chaque webserver** (`/proc/net/tcp`, ~toutes les 2 s) : backlog d'accept (`w1_listen_rq`, `w2_listen_rq`), `ESTABLISHED`, `TIME_WAIT`. Un backlog qui se remplit côté webserver indique que le goulot est le serveur et non HAProxy ;
  - **CPU et mémoire** (`docker stats`, ~toutes les 2 s) : conteneurs HAProxy, `webserver1` et `webserver2` ;
  - **hôte** : CPU global, mémoire disponible, sockets TCP, CPU et threads/fd du générateur de charge. Résumé dans le champ `mon` du JSON, série complète dans `run-<date>.mon.tsv`.
- `GEN=container` : le générateur tourne dans des conteneurs `python:3-slim` sur le réseau Docker du test. **À utiliser dès 500 req/s** : depuis l'hôte, le port publié (`docker-proxy`) perd des connexions (5 % d'erreurs à 500 req/s, 24 % à 750 req/s alors que HAProxy était quasi inactif). Ces mesures invalides sont conservées dans `results/_invalide-docker-proxy-3.4/`. Le CPU du générateur n'est pas relevé dans ce mode : contrôler que `rps_actual` reste proche de la cible.
- Un processus générateur par tranche de 250 req/s (un seul sature un cœur vers 300 req/s).
- `LOADGEN=async` (automatique avec `--rate` ≥ 1000) : `tests/loadgen_async.py`, générateur asyncio en boucle ouverte, un processus par 1500 req/s ; `WORKERS` y sert de garde-fou (requêtes en vol, code -1 si dépassé). Le CPU des conteneurs générateurs est relevé dans `d_gen_cpu` (`max_gen_cpu_pct` du résumé).
- `tests/check-round.py [--strict] <version> [charges…]` : tableau par charge × config avec verdict (débit < 97 % de la cible, CPU hôte > 88 %, mémoire libre < 1,5 Go). Avec `--strict`, code retour 2 si problème. Utilisé entre deux tranches de runs d'une campagne.
- Campagne par tranches : lancer `run-all-tests.sh` avec 6, 6 puis 5 runs (les runs s'ajoutent), vérifier avec `check-round.py` après chaque tranche, ajuster si besoin.
- Bilan complet des campagnes de charge : `results/ANALYSE-STRESS.md`.

## Limites

- Les tests s'exécutent l'un après l'autre : ils partagent `webserver1` et `webserver2`.
- Pendant un test, la stack principale (port 8080) perd brièvement `webserver1`.
- Un seul scénario : un serveur arrêté. Un serveur lent, qui renvoie des erreurs 500, ou un réseau qui flappe n'est pas simulé : l'intérêt de v003 n'est donc pas mesuré.
- Le serveur arrêté ne refuse pas la connexion, elle reste sans réponse : cela favorise les configs à `timeout connect` court.
- Les durées varient de quelques dixièmes de seconde d'un run à l'autre : d'où les moyennes.

## Logs vers ELK (Filebeat)

`docker-compose.elk.yml` (surcharge) envoie les logs de HAProxy et des webservers vers Elasticsearch via Filebeat, avec le pilote de logs syslog de Docker (sous Docker Desktop, les fichiers de logs ne sont pas lisibles depuis un conteneur). La config principale `haproxy.cfg` journalise une ligne par requête (`option httplog`) ; `elk/filebeat.yml` en extrait les champs (`haproxy.status_code`, `haproxy.server`, `haproxy.t_response`...). Index : `exo3-logs-AAAA.MM.JJ`, champ `app` = `haproxy` ou `webserver`.

```bash
docker compose -f docker-compose.yml -f docker-compose.elk.yml up -d --force-recreate   # démarrer
tests/elk-demo.sh                                  # petit run : 20 req/s pendant 40 s, panne de webserver1 de 10 s à 25 s
docker compose up -d --force-recreate haproxy webserver1 webserver2                         # revenir à la normale
```

Les campagnes de test (`run-all-tests.sh`) n'utilisent pas cette surcharge et n'envoient rien à ELK.
