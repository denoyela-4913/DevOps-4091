# Vérification manuelle du déploiement (Nginx + application Angular)

À lancer depuis `Exercice_1/ansible`, avec `source .venv/bin/activate`.
Remplacer `docker` par `aws` selon la cible (`-i hosts_docker` / `-i hosts_aws`).

## 0. Connectivité
```bash
ansible all -i hosts_docker -m ping
```

## 1. Nginx est installé
```bash
ansible all -i hosts_docker -b -m command -a "dpkg -l nginx"          # ligne "ii nginx 1.24..."
ansible all -i hosts_docker -b -m command -a "nginx -v"
```

## 2. Nginx est fonctionnel et écoute sur le port 80
```bash
ansible all -i hosts_docker -b -m command -a "systemctl is-active nginx"    # active
ansible all -i hosts_docker -b -m command -a "systemctl is-enabled nginx"   # enabled
ansible all -i hosts_docker -b -m shell   -a "ss -tlnp | grep ':80 '"       # LISTEN 0.0.0.0:80 nginx
ansible all -i hosts_docker -b -m command -a "nginx -t"                     # syntax is ok
ansible all -i hosts_docker -b -m command -a "ps -C nginx -o pid,user,lstart,etime,cmd"
```

## 3. L'application Angular est installée
```bash
ansible all -i hosts_docker -b -m command -a "ls -l /var/www/html/olympic-games-starter"
ansible all -i hosts_docker -b -m command -a "ls -ld /var/www/html/olympic-games-starter"   # propriétaire www-data
```

## 4. Nginx est configuré pour servir l'application
```bash
ansible all -i hosts_docker -b -m command -a "ls -l /etc/nginx/sites-enabled/"            # app.conf seul (pas default)
ansible all -i hosts_docker -b -m command -a "cat /etc/nginx/sites-available/app.conf"
ansible all -i hosts_docker -m uri -a "url=http://localhost status_code=200 return_content=true"
ansible all -i hosts_docker -m shell -a "curl -s http://localhost | grep -o '<app-root>'"  # <app-root>
```

## 5. Accès depuis la machine locale / internet
```bash
# Docker : le port 80 de la VM est redirigé vers localhost:80
curl -I http://localhost                         # HTTP/1.1 200 OK

# AWS : nécessite l'ouverture du port 80 dans le security group (terraform apply)
curl -I http://$(cd ../terraform/aws && terraform output -raw public_dns)
```

## 6. Playbooks de test automatiques
```bash
ansible-playbook -i hosts_docker test-docker.yml
ansible-playbook -i hosts_aws    test-aws.yml
```

## 7. Tester le handler (modification de configuration)
```bash
# Ajouter une ligne de commentaire dans nginx/app.conf, puis :
ansible-playbook -i hosts_docker deploy.yml --diff      # "Redémarrer Nginx" doit s'exécuter
ansible-playbook -i hosts_docker deploy.yml             # second passage : changed=0, pas de handler
```
