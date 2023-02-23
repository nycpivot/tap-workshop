#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws cloudformation stack-create-complete --region $aws_region_code --stack-name tap-workshop-singlecluster-stack --template-body file:///home/ubuntu/tanzu-operations/tap-operations/aws-eks/config/tap-singlecluster-stack.yaml
