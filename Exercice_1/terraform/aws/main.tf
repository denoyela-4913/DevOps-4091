# Définit d'une ressource de type
# "aws_instance" permettant de créer un serveur
# sur l'infrastructure Amazon EC2
resource "aws_instance" "my_server" {
  # Définition de l'AMI (identifiant du modèle d'image disque)
  # et du type d'instance (i.e. caractéristiques de performance)
  # de la machine virtuelle à créer
  ami           = var.ami_id
  instance_type = var.instance_type

  # Définition des étiquettes à associer à la machine
  # virtuelle, ici "Name" pour définir un nom
  tags = merge(var.tags, { Name = var.instance_name })

  # Optionnel - Définition des éléments permettant une connexion SSH
  # sur la machine déployée
  vpc_security_group_ids = [aws_security_group.my_security_group.id]
  key_name               = aws_key_pair.generated_key.key_name
}

// La suite de la configuration permet de configurer un accès SSH
// sur la machine AWS. 
// Cette section n'est pas demandée pour ce premier exercice car
// un peu technique mais sera nécessaire pour la seconde partie.

resource "aws_security_group" "my_security_group" {
  name = var.security_group_name
  tags = var.tags

  // Port 22 (SSH)
  ingress {
    cidr_blocks = var.allowed_ssh_cidr_blocks
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
  }
  // Port 80 (HTTP) : nécessaire pour accéder au site servi par Nginx
  ingress {
    cidr_blocks = var.allowed_http_cidr_blocks
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

// On créait une nouvelle paire de clés SSH
// afin que celle ci soit utilisable pour se connecter
// à notre serveur
resource "tls_private_key" "my_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = var.ssh_rsa_bits
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.generated_key_name
  public_key = tls_private_key.my_ssh_key.public_key_openssh
}

// On stocke notre clé SSH privée localement dans le répertoire
// var.ssh_private_key_directory (~/.ssh par défaut).
resource "local_sensitive_file" "pem_file" {
  filename             = pathexpand("${var.ssh_private_key_directory}/aws_${aws_key_pair.generated_key.key_name}.pem")
  file_permission      = "600"
  directory_permission = "700"

  content = tls_private_key.my_ssh_key.private_key_pem
  # Attention, sur MacOS il est possible qu'il soit nécessaire de modifier la ligne précédente par:
  # content              = tls_private_key.my_ssh_key.private_key_openssh
}
