# Aide Kibana : option AWS (Amazon OpenSearch Service)

## Contexte

| Élément | Valeur |
|---|---|
| Plateforme | Amazon OpenSearch Service (service managé, pas d'EKS ni d'EC2 à administrer) |
| Région | `eu-north-1` (Stockholm) |
| Nom du domaine | `openclassrooms-p5-edo` |
| Moteur | `Elasticsearch_7.10` |
| Interface | Kibana 7.10, accessible sous `/_plugin/kibana/` |
| Déploiement | Terraform (`main.tf`, provider `hashicorp/aws ~> 5.0`) |

### Résumé de la configuration

- **Nœud** : un seul, de type `t3.small.search` (2 vCPU, 2 Go de RAM). Les machines EC2 sous-jacentes sont gérées par AWS.
- **Stockage** : EBS activé, 10 Go.
- **Accès** : politique `es:*` limitée à une seule IP source (`/32`). Il n'y a pas d'authentification utilisateur. Si ton IP publique change, la page Kibana répond « Forbidden » et il faut mettre à jour `aws:SourceIp` dans `main.tf`, puis refaire un `terraform apply`.
- **Sorties Terraform** : `elasticsearch` (endpoint) et `kibana` (dashboard endpoint).

### Données

- Fichier source : `samples/nginx-access.log` (période du 23/06/2024 au 20/08/2024).
- Import : script Python (voir `logboook.txt`) qui parse chaque ligne et l'envoie via l'API `_bulk` dans l'index `nginx-access`. Il n'y a pas d'upload par l'interface (le Data Visualizer n'existe pas dans Kibana 7.10 d'OpenSearch Service).
- Champs créés par le script :

| Champ | Type | Contenu |
|---|---|---|
| `@timestamp` | date | Date de la requête |
| `clientip` | text + `.keyword` | IP du client |
| `method` | text + `.keyword` | Verbe HTTP |
| `url` | text + `.keyword` | URL demandée |
| `status` | long | Code HTTP |
| `bytes` | long | Octets envoyés |
| `referrer`, `agent` | text + `.keyword` | Référent et user-agent |

> Dans les champs de type `text`, seul le sous-champ `.keyword` est utilisable dans une agrégation **Terms**.

---

## Préparation commune

1. Ouvre l'URL Kibana (sortie Terraform `kibana`).
2. Menu (☰) > **Stack Management** > **Index Patterns** > **Create index pattern**. Saisis `nginx-access`, choisis `@timestamp` comme champ de temps, puis valide.
3. Dans **Discover**, vérifie que les champs ci-dessus apparaissent.
4. Règle la période en haut à droite : **Absolute**, du **23 juin 2024** au **20 août 2024**. Sans cela, les graphiques sont vides.

Pour chaque graphique : menu (☰) > **Visualize** > **Create visualization**, puis choisis le type et la source `nginx-access`.

---

## Graphique 1 : donut des verbes HTTP

1. Type : **Pie**.
2. Onglet **Data** > **Metrics** > **Slice size** : Aggregation **Count**.
3. **Buckets** > **Add** > **Split slices** :
   - Aggregation : **Terms**
   - Field : `method.keyword`
   - Order by : **Metric: Count**, **Descending**
   - Size : `10`
4. Onglet **Options** : coche **Donut**. Coche **Show labels** si tu veux les valeurs.
5. Clique sur **Update** (▶ en bas à droite), puis **Save** avec le titre `Verbes HTTP`.

## Graphique 2 : histogramme des octets envoyés par 12 h

1. Type : **Vertical Bar**.
2. **Metrics** > **Y-axis** : Aggregation **Sum**, Field `bytes`.
3. **Buckets** > **Add** > **X-axis** :
   - Aggregation : **Date Histogram**
   - Field : `@timestamp`
   - Minimum interval : **Custom**, valeur `12h`
4. **Update**, puis **Save** avec le titre `Octets envoyés par 12h`.

## Graphique 3 : histogramme cumulé du top 5 des requêtes par 12 h

1. Type : **Vertical Bar**.
2. **Metrics** > **Y-axis** : Aggregation **Count**.
3. **Buckets** > **Add** > **X-axis** : **Date Histogram**, Field `@timestamp`, intervalle **Custom** `12h`.
4. **Buckets** > **Add** > **Split series** :
   - Sub aggregation : **Terms**
   - Field : `url.keyword`
   - Order by : **Metric: Count**, **Descending**
   - Size : `5`
5. Onglet **Metrics & axes** > **Y-axes** > **Advanced** : Mode **stacked** (valeur par défaut avec un Split series).
6. **Update**, puis **Save** avec le titre `Top 5 requêtes par 12h`.

> Le top 5 est calculé par tranche de 12 h. Les 5 URLs peuvent donc changer d'une barre à l'autre. Pour fixer un top 5 global, ajoute d'abord une visualisation **Data Table** triée par Count, puis filtre sur ces 5 URLs.

> L'URL de départ utilisait `horizontal_bar` avec `clientip.keyword`. Pour un histogramme vertical sur les requêtes, prends **Vertical Bar** et `url.keyword`.

---

## Assembler le dashboard

1. Menu (☰) > **Dashboard** > **Create new dashboard**.
2. **Add**, puis clique sur les trois visualisations.
3. Ajuste les tailles par glisser-déposer.
4. **Save** avec le titre `Métriques serveur HTTP`.

## Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Graphique vide | Période trop courte | Régler la période du 23/06/2024 au 20/08/2024 |
| `bytes` absent du champ Sum | Champ indexé en texte | Recréer l'index avec un mapping `long` |
| Champ absent de Terms | Champ `text` | Utiliser le sous-champ `.keyword` |
| Page « Forbidden » | IP publique modifiée | Mettre à jour `aws:SourceIp` dans `main.tf` et relancer `terraform apply` |
| Liste de champs obsolète | Index pattern en cache | **Stack Management** > **Index Patterns** > **Refresh field list** |

## Nettoyage

```bash
terraform destroy
```

Le domaine OpenSearch est facturé tant qu'il existe.
