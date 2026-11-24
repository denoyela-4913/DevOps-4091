terraform {
  # Définition de la version de Terraform requise
  required_version = ">= 1.2.0"

  # Définition des providers utilisés par le déploiement
  # avec la version souhaitée
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    local = {
      source = "hashicorp/local"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}
