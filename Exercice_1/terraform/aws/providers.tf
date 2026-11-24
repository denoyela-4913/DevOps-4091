# Configuration du provider "aws"
# Voir https://registry.terraform.io/providers/hashicorp/aws/latest/docs
# pour plus de détails
provider "aws" {
  # Définition de la "région" ciblée par le déploiement
  # Voir https://aws.amazon.com/fr/about-aws/global-infrastructure/
  region = var.aws_region
}
