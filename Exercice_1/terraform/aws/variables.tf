variable "allowed_http_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Plages CIDR autorisées à joindre le port 80 (HTTP, site servi par Nginx)."

  validation {
    condition     = alltrue([for c in var.allowed_http_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "Chaque entrée de allowed_http_cidr_blocks doit être un CIDR IPv4 valide (ex. 203.0.113.0/24)."
  }
}

variable "allowed_ssh_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "Plages CIDR autorisées à joindre le port 22 (SSH). À restreindre à votre IP publique (x.x.x.x/32) hors exercice."

  validation {
    condition     = alltrue([for c in var.allowed_ssh_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "Chaque entrée de allowed_ssh_cidr_blocks doit être un CIDR IPv4 valide (ex. 203.0.113.10/32)."
  }
}

variable "ami_id" {
  type        = string
  default     = "ami-06fb1802e2b757f09" # Ubuntu 24.04 LTS, eu-north-1
  description = "Identifiant de l'AMI (modèle d'image disque) de la VM. Spécifique à la région choisie."

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id doit avoir la forme ami-xxxxxxxx (8 à 17 caractères hexadécimaux)."
  }
}

variable "aws_region" {
  type        = string
  default     = "eu-north-1"
  description = "Région AWS ciblée par le déploiement (voir https://aws.amazon.com/fr/about-aws/global-infrastructure/)."

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.aws_region))
    error_message = "aws_region doit avoir la forme d'une région AWS (ex. eu-north-1)."
  }
}

variable "generated_key_name" {
  type        = string
  default     = "openclassrooms_edo_p5"
  description = "Nom de la paire de clés SSH générée par Terraform et enregistrée dans AWS."

  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,255}$", var.generated_key_name))
    error_message = "generated_key_name ne peut contenir que des lettres, chiffres, '_' et '-' (255 caractères max)."
  }
}

variable "instance_name" {
  type        = string
  default     = "OpenClassrooms-EDO-P5"
  description = "Valeur de l'étiquette « Name » de la VM."

  validation {
    condition     = length(var.instance_name) > 0 && length(var.instance_name) <= 255
    error_message = "instance_name doit contenir entre 1 et 255 caractères."
  }
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Type d'instance EC2 (caractéristiques de performance de la VM)."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[0-9][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type doit avoir la forme famille.taille (ex. t3.micro)."
  }
}

variable "security_group_name" {
  type        = string
  default     = "allow-ssh"
  description = "Nom du groupe de sécurité (ouvre SSH et HTTP en entrée)."

  validation {
    condition     = can(regex("^[A-Za-z0-9 ._:/()#,@\\[\\]+=&;{}!$*-]{1,255}$", var.security_group_name))
    error_message = "security_group_name contient des caractères non autorisés par AWS (255 max)."
  }
}

variable "ssh_private_key_directory" {
  type        = string
  default     = "~/.ssh"
  description = "Répertoire local où est écrite la clé privée SSH (fichier aws_<generated_key_name>.pem, droits 600)."
}

variable "ssh_rsa_bits" {
  type        = number
  default     = 4096
  description = "Taille en bits de la clé RSA générée."

  validation {
    condition     = contains([2048, 3072, 4096], var.ssh_rsa_bits)
    error_message = "ssh_rsa_bits doit valoir 2048, 3072 ou 4096."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Étiquettes supplémentaires appliquées à la VM et au groupe de sécurité."
}
