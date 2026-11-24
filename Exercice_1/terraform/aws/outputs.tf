# Nom d'hôte public de la VM, à copier dans l'inventaire Ansible (hosts_aws)
output "public_dns" {
  value = aws_instance.my_server.public_dns
}

# Adresse IP publique de la VM
output "public_ip" {
  value = aws_instance.my_server.public_ip
}
