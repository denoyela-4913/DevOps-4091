ansible all -i hosts_docker -m command -a "ps -C nginx -o pid,user,lstart,etime,cmd"
