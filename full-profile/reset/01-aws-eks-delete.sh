#!/bin/bash

read -p "AWS Account Id: " aws_account_id
read -p "AWS Region Code: " aws_region_code

if [ -z $aws_account_id ]
then
    aws_account_id=964978768106
fi

if [ -z $aws_region_code ]
then
    aws_region_code=us-west-1
fi

aws elb describe-load-balancers
aws elb delete-load-balancer --load-balancer-name 

arn=arn:aws:eks:${aws_region_code}:${aws_account_id}:cluster

aws cloudformation delete-stack --region $aws_region_code --stack-name tap-multicluster-stack
aws cloudformation wait stack-delete-complete --region $aws_region_code --stack-name tap-multicluster-stack

rm .kube/config
