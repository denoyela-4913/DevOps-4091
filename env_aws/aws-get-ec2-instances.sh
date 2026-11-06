#!/bin/bash

param="$1"

if [ "$param" == "stopped" ] || [ "$param" == "running" ] || [ "$param" == "all" ] || [ "$param" == "" ] ; then
	#echo param OK		
	echo -n ""
else
	echo ""
	echo param NOK = $param
	echo ""
	echo "Valid values = [running] / stopped / all"
	echo ""
	echo "=> Select running by default"
	echo ""
	param=""
fi

if [ ! -n "$param" ]; then
	param="running" # RUNNING by default
fi

echo ""
echo "Selected instances = $param"
echo ""

read -t 1

if [ "$param" == "all" ] ; then
	aws ec2 describe-instances \
	  --region eu-north-1 \
	  --query "Reservations[].Instances[].[InstanceId,InstanceType,PublicDnsName,PublicIpAddress,Tags[?Key=='Name']|[0].Value]" \
	  --output table
else
	aws ec2 describe-instances \
	  --region eu-north-1 \
	  --filters "Name=instance-state-name,Values=$param" \
	  --query "Reservations[].Instances[].[InstanceId,InstanceType,PublicDnsName,PublicIpAddress,Tags[?Key=='Name']|[0].Value]" \
	  --output table
fi


exit 0

# unused code
aws ec2 describe-instances \
  --region eu-north-1 \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].[InstanceId,InstanceType,PublicDnsName,PublicIpAddress,Tags[?Key=='Name']|[0].Value]" \
  --output table
