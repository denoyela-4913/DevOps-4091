# Fichier main.tf en UTF-8 (accents autorisés)

# Partition AWS du compte courant ('aws' en règle générale ; d'autres existent,
# ex. 'aws-eusc' pour la région eusc-de-east-1, 'aws-cn', 'aws-us-gov').
# On passe par une data source + un local (et non une variable) car elle est
# calculée dynamiquement. Voir https://aws.amazon.com/fr/about-aws/global-infrastructure/
data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

resource "aws_opensearch_domain" "opensearch" {
  domain_name    = var.domain_name
  engine_version = var.engine_version

  cluster_config {
    instance_type = var.instance_type
  }

  ebs_options {
    ebs_enabled = true
    volume_size = var.ebs_volume_size
    volume_type = var.ebs_volume_type
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "es:*"
      Resource  = "arn:${local.partition}:es:${var.aws_region}:*:domain/${var.domain_name}/*"
      Condition = { IpAddress = { "aws:SourceIp" = var.allowed_source_cidrs } }
    }]
  })
}
