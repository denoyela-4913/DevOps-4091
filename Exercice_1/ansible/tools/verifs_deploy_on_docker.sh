ansible all -i hosts_docker -b -m command -a "nginx -t"
ansible all -i hosts_docker -m service -a "name=nginx" -b
ansible all -i hosts_docker -m uri -a "url=http://localhost status_code=200"
