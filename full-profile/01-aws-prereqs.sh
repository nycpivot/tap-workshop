#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws cloudformation create-stack --region $aws_region_code --stack-name tap-workshop-singlecluster-stack --template-body file:///home/ubuntu/tap-workshop/full-profile/config/tap-singlecluster-stack.yaml
