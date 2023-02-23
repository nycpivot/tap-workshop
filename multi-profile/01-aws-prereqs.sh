#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws cloudformation stack-create-complete --region $aws_region_code --stack-name tap-workshop-multicluster-stack --template-body file:///home/ubuntu/tap-workshop/full-profile/config/tap-multicluster-stack.yaml
