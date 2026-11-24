terraform {
  # Définition de la version de Terraform requise
  # (>= 1.2.0 : fonctions alltrue/can et validations de variables)
  required_version = ">= 1.2.0"

  # Définition des providers utilisés par le déploiement
  # avec la version souhaitée
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
