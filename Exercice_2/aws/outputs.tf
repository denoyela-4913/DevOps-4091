# URL de la BDD ElasticSearch (moteur de la stack ELK)
output "elasticsearch" {
  description = "URL de la base de données ElasticSearch"
  value       = "https://${aws_opensearch_domain.opensearch.endpoint}"
}

# URL de l'instance KIBANA (UI de la stack ELK)
output "kibana" {
  description = "URL de connexion à l'instance Kibana"
  value       = "https://${aws_opensearch_domain.opensearch.dashboard_endpoint}"
}
