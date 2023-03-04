#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws cloudformation create-stack --stack-name tap-workshop-singlecluster-stack --region $aws_region_code --template-body file:///home/ubuntu/tap-workshop/full-profile/config/tap-singlecluster-stack.yaml

aws cloudformation wait stack-create-complete --stack-name tap-workshop-singlecluster-stack --region $aws_region_code
