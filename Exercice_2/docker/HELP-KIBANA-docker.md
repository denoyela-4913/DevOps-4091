# Aide Kibana : option Docker (locale)

## Contexte

| Élément | Valeur |
|---|---|
| Plateforme | Docker Compose en local (pas d'EKS ni d'EC2) |
| Stack | Elasticsearch **7.14.0** + Kibana **7.14.0** |
| Images | `docker.elastic.co/elasticsearch/elasticsearch:7.14.0`, `docker.elastic.co/kibana/kibana:7.14.0` |
| Interface Kibana | http://localhost:5601 |
| API Elasticsearch | http://localhost:9200 |
| Démarrage | `docker compose up` depuis `Exercice_2/docker` |

### Résumé de la configuration (`docker-compose.yml`)

- **elasticsearch** :
  - `discovery.type=single-node` : un seul nœud.
  - `xpack.security.enabled=false` : pas d'authentification.
  - `bootstrap.memory_lock=true` avec `memlock` illimité (`ulimits`).
  - Mémoire JVM : `-Xms512m -Xmx512m`.
  - Volume nommé `esdata` pour les données.
  - Ports `9200` (HTTP) et `9300` (transport).
- **kibana** : `ELASTICSEARCH_URL=http://elasticsearch:9200`, port `5601`, démarre après Elasticsearch.
- **Réseau** : bridge `elk`.
- **Logstash** : absent. Kibana envoie directement les données à Elasticsearch avec l'outil d'import de fichier.

### Données

- Fichier source : `samples/nginx-access.log` (période du 23/06/2024 au 20/08/2024).
- Import par l'interface, dans l'index `nginx-access` (voir ci-dessous).

> Les noms de champs dépendent du motif Grok détecté à l'import. Avec le format Apache/Nginx combiné, on obtient généralement `clientip`, `verb`, `request`, `response`, `bytes`, `timestamp`. Vérifie-les dans **Discover** et adapte les noms ci-dessous si besoin.

---

## Étape 1 : importer le fichier de log

1. Ouvre http://localhost:5601.
2. Menu (☰) > **Machine Learning** > **Data Visualizer** > **Upload a file**. Tu peux aussi chercher « Upload a file » dans la barre de recherche.
3. Glisse `nginx-access.log`.
4. Vérifie l'aperçu : format **semi-structured text**, champs découpés. Si besoin, **Override settings** pour ajuster le motif Grok (par exemple `%{COMBINEDAPACHELOG}`) et le champ de date.
5. Clique sur **Import**, saisis l'**Index name** `nginx-access`, coche **Create data view**, puis **Import**.
6. Vérifie dans **Stack Management** > **Index Management** que l'index contient des documents.

## Préparation commune

1. Dans **Discover**, choisis la data view `nginx-access` et relève les noms de champs.
2. Règle la période : **Absolute**, du **23 juin 2024** au **20 août 2024**.
3. Menu (☰) > **Dashboard** > **Create dashboard**, puis **Create visualization** pour ouvrir l'éditeur **Lens**.

---

## Graphique 1 : donut des verbes HTTP

1. Type de graphique : **Donut** (liste déroulante des types, famille Pie/Donut).
2. **Slice by** : champ du verbe (`verb` ou `http.request.method`), fonction **Top values**, **Number of values** `10`.
3. **Metric** : **Count of records**.
4. Optionnel : afficher les pourcentages et la légende dans les paramètres.
5. **Save and return**, puis renomme le panneau `Verbes HTTP`.

## Graphique 2 : histogramme des octets envoyés par 12 h

1. Type : **Bar vertical**.
2. **Horizontal axis** : champ de date (`@timestamp` ou `timestamp`), fonction **Date histogram**. Dans les options du champ, désactive **Use Kibana time interval** (ou choisis **Customize time interval**), puis saisis `12 hours`.
3. **Vertical axis** : champ des octets (`bytes`), fonction **Sum**.
4. **Save and return**, puis renomme le panneau `Octets envoyés par 12h`.

## Graphique 3 : histogramme cumulé du top 5 des requêtes par 12 h

1. Type : **Bar vertical stacked**.
2. **Horizontal axis** : champ de date, **Date histogram**, intervalle `12 hours`.
3. **Vertical axis** : **Count of records**.
4. **Break down by** : champ de la requête (`request`, ou `url.original`), fonction **Top values**, **Number of values** `5`.
   - Si le champ est de type `text`, utilise son sous-champ `.keyword`.
5. **Save and return**, puis renomme le panneau `Top 5 requêtes par 12h`.

> Le top 5 est calculé par tranche de 12 h. Les 5 requêtes peuvent donc changer d'une barre à l'autre.

---

## Enregistrer le dashboard

1. Organise les panneaux : donut en haut à gauche, histogrammes à côté ou dessous.
2. **Save** avec le titre `Métriques serveur HTTP`.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Graphique vide | Période trop courte | Régler la période du 23/06/2024 au 20/08/2024 |
| Sum impossible sur `bytes` | Champ détecté en `keyword` (valeur `-`) | Réimporter en corrigeant le type, ou remplacer `-` par `0` |
| Top values indisponible | Champ `text` | Utiliser le sous-champ `.keyword` |
| Date en 1970 ou absente | Format de date mal détecté | Corriger le format de date dans **Override settings** à l'import |
| Elasticsearch s'arrête au démarrage | `vm.max_map_count` trop bas | `sudo sysctl -w vm.max_map_count=262144` (sous WSL, dans la distribution) |
| Import refusé | Fichier trop volumineux | La limite est de 100 Mo (paramètre avancé de Kibana) |

## Nettoyage

```bash
docker compose down --remove-orphans -v
```

Le `-v` supprime le volume `esdata` et donc l'index importé.
