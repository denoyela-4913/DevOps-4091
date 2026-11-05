#curl -s http://ec2-13-48-248-203.eu-north-1.compute.amazonaws.com | grep -i "<title>"
curl -s http://$(cd ../terraform/aws; terraform output -raw public_dns) | grep -i "<title>"
