# Plages d'adresses autorisées à accéder au domaine OpenSearch / Kibana
variable "allowed_source_cidrs" {
  type        = list(string)
  description = "Plages CIDR autorisées à accéder au domaine OpenSearch (ex. [\"203.0.113.10/32\"] pour votre IP publique). Pas de valeur par défaut : à fournir via terraform.tfvars ou -var."

  validation {
    condition     = length(var.allowed_source_cidrs) > 0 && alltrue([for c in var.allowed_source_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_source_cidrs doit contenir au moins un CIDR IPv4 valide (ex. 203.0.113.10/32)."
  }
}

# Région AWS utilisée
variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "Région AWS ciblée par le déploiement (voir https://aws.amazon.com/fr/about-aws/global-infrastructure/)."

  validation {
    # La validation de la région est faite comme suit :
    # - début de la variable = ^
    # - exactement 2 lettres = [a-z]{2}
    # - un certain nombre de caractères, soit des lettres soit '-' avec au minimum une lettre après le '-' et au moins un groupe = (-[a-z]+)+
    # - un tiret '-' = -
    # - un chiffre = [0-9]
    # - fin de variable = $
    #
    # Regle générale => condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    # --------------
    # La région eusc-de-east-1 est une région spéciale "AWS European Sovereign Cloud" et doit être aussi gérée
    # Dans ce cas, la partition n'est plus 'aws' mais 'aws-eusc'
    condition     = can(regex("^[a-z]{2,4}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region doit avoir la forme d'une région AWS (ex. eu-north-1)."
  }
}

# Nom du domaine OpenSearch (immuable : un changement détruit et recrée le domaine)
variable "domain_name" {
  type        = string
  default     = "openclassrooms-p5-edo"
  description = "Nom du domaine OpenSearch. Fait partie de l'URL et de l'ARN ; non modifiable après création (un changement recrée le domaine et perd les données)."

  validation {
    # minuscule initiale, puis minuscules/chiffres/tirets, 3 à 28 caractères au total
    condition     = can(regex("^[a-z][a-z0-9-]{2,27}$", var.domain_name))
    error_message = "domain_name doit commencer par une minuscule et contenir 3 à 28 caractères parmi a-z, 0-9 et '-'."
  }
}

# Taille du volume EBS de chaque nœud
variable "ebs_volume_size" {
  type        = number
  default     = 10
  description = "Taille (Go) du volume EBS de chaque nœud. Le minimum et le maximum autorisés dépendent du type d'instance (10 Go minimum pour t3.small.search)."

  validation {
    condition     = var.ebs_volume_size >= 10 && var.ebs_volume_size <= 100
    error_message = "ebs_volume_size doit être compris entre 10 et 100 (Go)."
  }
}

# Type de volume EBS de chaque nœud
variable "ebs_volume_type" {
  type        = string
  default     = "gp3"
  description = "Type de volume EBS des nœuds : gp3 (recommandé, moins cher et plus performant que gp2) ou gp2."

  validation {
    condition     = contains(["gp2", "gp3"], var.ebs_volume_type)
    error_message = "ebs_volume_type doit valoir gp2 ou gp3."
  }
}

# Moteur et version du domaine
variable "engine_version" {
  type        = string
  default     = "Elasticsearch_7.10"
  description = "Moteur et version du domaine (ex. Elasticsearch_7.10, OpenSearch_2.11). Elasticsearch_7.10 est la dernière version d'Elasticsearch supportée par AWS."

  validation {
    condition     = can(regex("^(Elasticsearch|OpenSearch)_[0-9]+\\.[0-9]+$", var.engine_version))
    error_message = "engine_version doit avoir la forme Elasticsearch_X.Y ou OpenSearch_X.Y."
  }
}

# Type d'instance des nœuds
variable "instance_type" {
  type        = string
  default     = "t3.small.search"
  description = "Type d'instance des nœuds du cluster (ex. t3.small.search)."

  validation {
    condition     = can(regex("^[a-z0-9]+\\.[a-z0-9]+\\.search$", var.instance_type))
    error_message = "instance_type doit avoir la forme famille.taille.search (ex. t3.small.search)."
  }
}

# Étiquettes communes à toutes les ressources
variable "tags" {
  type        = map(string)
  default     = { Domain = "OpenClassrooms_P5_EDO" }
  description = "Étiquettes appliquées à toutes les ressources via default_tags du provider."
}
