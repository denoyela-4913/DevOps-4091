ansible all -i hosts_aws -m command -a "ps -C nginx -o pid,user,lstart,etime,cmd"
