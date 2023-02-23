#!/bin/bash

read -p "AWS Region Code: " aws_region_code

aws cloudformation stack-create-complete --region $aws_region_code --stack-name tap-workshop-multicluster-stack --template-body file:///home/ubuntu/tanzu-operations/tap-operations/aws-eks/config/tap-multicluster-stack.yaml
