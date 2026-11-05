echo "Login docker :"
read
ssh -p 2222 openclassrooms@127.0.0.1
echo "Login aws :"
read
ec2_dns=$(grep -o "ec2-[0-9a-z.-]*" hosts_aws)
ssh -i ~/.ssh/aws_openclassrooms_edo_p5.pem -o IdentitiesOnly=yes ubuntu@$ec2_dns

